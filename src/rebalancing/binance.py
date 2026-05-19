from __future__ import annotations

import hashlib
import hmac
import json
import os
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any
from urllib.parse import urlencode
from urllib.request import Request, urlopen

from .indicators import build_btc_snapshot
from .models import AccountSnapshot, Candle, MarketCandidate, Position, PositionSide


@dataclass(frozen=True)
class BinanceCredentials:
    api_key: str
    api_secret: str

    @classmethod
    def from_env(cls) -> "BinanceCredentials":
        api_key = os.environ.get("BINANCE_API_KEY")
        api_secret = os.environ.get("BINANCE_API_SECRET")
        if not api_key or not api_secret:
            raise RuntimeError("BINANCE_API_KEY and BINANCE_API_SECRET must be set")
        return cls(api_key=api_key, api_secret=api_secret)


class BinanceFuturesClient:
    def __init__(
        self,
        credentials: BinanceCredentials | None = None,
        *,
        base_url: str | None = None,
        timeout: float = 10.0,
        recv_window: int = 5_000,
    ) -> None:
        self.credentials = credentials
        self.base_url = (base_url or os.environ.get("BINANCE_FAPI_BASE_URL") or "https://fapi.binance.com").rstrip("/")
        self.timeout = timeout
        self.recv_window = recv_window

    @classmethod
    def from_env(cls) -> "BinanceFuturesClient":
        return cls(credentials=BinanceCredentials.from_env())

    def exchange_info(self) -> dict[str, Any]:
        return self._request("GET", "/fapi/v1/exchangeInfo")

    def ticker_24hr(self, symbol: str | None = None) -> dict[str, Any] | list[dict[str, Any]]:
        params = {"symbol": symbol} if symbol else None
        return self._request("GET", "/fapi/v1/ticker/24hr", params=params)

    def klines(self, symbol: str, interval: str, *, limit: int = 500) -> list[Candle]:
        data = self._request(
            "GET",
            "/fapi/v1/klines",
            params={"symbol": symbol, "interval": interval, "limit": limit},
        )
        return [self._candle_from_kline(item) for item in data]

    def btc_market_snapshot(self):
        daily = self.klines("BTCUSDT", "1d", limit=240)
        four_hour = self.klines("BTCUSDT", "4h", limit=120)
        return build_btc_snapshot(daily=daily, four_hour=four_hour)

    def account(self) -> dict[str, Any]:
        self._require_credentials()
        return self._request("GET", "/fapi/v3/account", signed=True)

    def account_snapshot(
        self,
        *,
        day_start_equity: float,
        week_start_equity: float,
        month_start_equity: float,
    ) -> AccountSnapshot:
        account = self.account()
        return AccountSnapshot(
            equity=float(account["totalMarginBalance"]),
            wallet_balance=float(account["totalWalletBalance"]),
            day_start_equity=day_start_equity,
            week_start_equity=week_start_equity,
            month_start_equity=month_start_equity,
        )

    def positions(self) -> list[Position]:
        account = self.account()
        positions: list[Position] = []
        for raw in account.get("positions", []):
            position = self._position_from_account_position(raw)
            if position is not None:
                positions.append(position)
        return positions

    def market_candidates(self, now: datetime | None = None) -> list[MarketCandidate]:
        now = now or datetime.now(timezone.utc)
        exchange_info = self.exchange_info()
        tickers = self.ticker_24hr()
        tickers_by_symbol = {ticker["symbol"]: ticker for ticker in tickers}

        candidates = []
        for raw_symbol in exchange_info.get("symbols", []):
            ticker = tickers_by_symbol.get(raw_symbol.get("symbol"))
            candidate = self._market_candidate_from_raw(raw_symbol, ticker, now)
            if candidate is not None:
                candidates.append(candidate)
        return candidates

    def _request(
        self,
        method: str,
        path: str,
        params: dict[str, Any] | None = None,
        *,
        signed: bool = False,
    ):
        params = dict(params or {})
        headers = {}

        if signed:
            self._require_credentials()
            params.setdefault("recvWindow", self.recv_window)
            params["timestamp"] = int(time.time() * 1000)
            query = urlencode(params, doseq=True)
            params["signature"] = self._signature(query)
            headers["X-MBX-APIKEY"] = self.credentials.api_key  # type: ignore[union-attr]

        query_string = urlencode(params, doseq=True)
        url = f"{self.base_url}{path}"
        if query_string:
            url = f"{url}?{query_string}"

        request = Request(url, method=method, headers=headers)
        with urlopen(request, timeout=self.timeout) as response:
            payload = response.read().decode("utf-8")
        return json.loads(payload)

    def _signature(self, query: str) -> str:
        self._require_credentials()
        return hmac.new(
            self.credentials.api_secret.encode("utf-8"),  # type: ignore[union-attr]
            query.encode("utf-8"),
            hashlib.sha256,
        ).hexdigest()

    def _require_credentials(self) -> None:
        if self.credentials is None:
            raise RuntimeError("Binance credentials are required for signed endpoints")

    @staticmethod
    def _candle_from_kline(kline: list[Any]) -> Candle:
        return Candle(
            timestamp=datetime.fromtimestamp(kline[0] / 1000, tz=timezone.utc),
            open=float(kline[1]),
            high=float(kline[2]),
            low=float(kline[3]),
            close=float(kline[4]),
            volume=float(kline[7]),
        )

    @staticmethod
    def _position_from_account_position(raw: dict[str, Any]) -> Position | None:
        amount = float(raw.get("positionAmt", 0.0))
        notional = abs(float(raw.get("notional", 0.0)))
        if notional == 0 and amount == 0:
            return None

        raw_side = raw.get("positionSide", "BOTH")
        if raw_side == "LONG" or (raw_side == "BOTH" and amount > 0):
            side = PositionSide.LONG
        elif raw_side == "SHORT" or (raw_side == "BOTH" and amount < 0):
            side = PositionSide.SHORT
        else:
            return None

        return Position(symbol=raw["symbol"], side=side, notional=notional)

    @staticmethod
    def _market_candidate_from_raw(
        raw_symbol: dict[str, Any],
        ticker: dict[str, Any] | None,
        now: datetime,
    ) -> MarketCandidate | None:
        if raw_symbol.get("contractType") != "PERPETUAL":
            return None
        if raw_symbol.get("status") != "TRADING":
            return None
        if raw_symbol.get("quoteAsset") != "USDT":
            return None

        onboard_ms = int(raw_symbol.get("onboardDate", 0))
        onboard = datetime.fromtimestamp(onboard_ms / 1000, tz=timezone.utc) if onboard_ms else now
        listed_days = max(0, (now - onboard).days)

        return MarketCandidate(
            symbol=raw_symbol["symbol"],
            base_asset=raw_symbol["baseAsset"],
            quote_asset=raw_symbol["quoteAsset"],
            is_usdt_m_perp=True,
            quote_volume_24h=float((ticker or {}).get("quoteVolume", 0.0)),
            listed_days=listed_days,
            change_24h_pct=float((ticker or {}).get("priceChangePercent", 0.0)),
        )

