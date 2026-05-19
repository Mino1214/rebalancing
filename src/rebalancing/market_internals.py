from __future__ import annotations

import json
import os
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass, field, replace
from typing import Any
from urllib.parse import urlencode
from urllib.request import Request, urlopen

from .binance import BinanceFuturesClient, STABLE_BASE_ASSETS
from .models import MarketCandidate


STABLE_COINGECKO_IDS = (
    "tether",
    "usd-coin",
    "dai",
    "first-digital-usd",
    "true-usd",
    "ethena-usde",
    "binance-usd",
    "frax",
    "paypal-usd",
    "usds",
)


@dataclass(frozen=True)
class MarketCapCoin:
    id: str
    symbol: str
    name: str
    market_cap: float
    market_cap_rank: int | None
    price_change_24h_pct: float


@dataclass(frozen=True)
class MarketInternals:
    source: str
    stable_dominance_pct: float | None = None
    top10_dominance_total_pct: float | None = None
    top10_dominance_total2_pct: float | None = None
    total_market_cap_usd: float | None = None
    stable_market_cap_usd: float | None = None
    top10_market_cap_usd: float | None = None
    top10_market_cap_coins: tuple[MarketCapCoin, ...] = tuple()
    volume_breadth_pct: float | None = None
    volume_breadth_count: int = 0
    volume_breadth_total: int = 0
    advance_count: int = 0
    decline_count: int = 0
    flat_count: int = 0
    advance_decline_ratio: float | None = None
    breadth_universe_size: int = 0
    risk_label: str = "UNKNOWN"
    messages: tuple[str, ...] = field(default_factory=tuple)

    def to_payload(self) -> dict[str, Any]:
        return {
            "source": self.source,
            "stable_dominance_pct": self.stable_dominance_pct,
            "top10_dominance_total_pct": self.top10_dominance_total_pct,
            "top10_dominance_total2_pct": self.top10_dominance_total2_pct,
            "total_market_cap_usd": self.total_market_cap_usd,
            "stable_market_cap_usd": self.stable_market_cap_usd,
            "top10_market_cap_usd": self.top10_market_cap_usd,
            "top10_market_cap_coins": [
                {
                    "id": coin.id,
                    "symbol": coin.symbol,
                    "name": coin.name,
                    "market_cap": coin.market_cap,
                    "market_cap_rank": coin.market_cap_rank,
                    "price_change_24h_pct": coin.price_change_24h_pct,
                }
                for coin in self.top10_market_cap_coins
            ],
            "volume_breadth_pct": self.volume_breadth_pct,
            "volume_breadth_count": self.volume_breadth_count,
            "volume_breadth_total": self.volume_breadth_total,
            "advance_count": self.advance_count,
            "decline_count": self.decline_count,
            "flat_count": self.flat_count,
            "advance_decline_ratio": self.advance_decline_ratio,
            "breadth_universe_size": self.breadth_universe_size,
            "risk_label": self.risk_label,
            "messages": list(self.messages),
        }


class CoinGeckoClient:
    def __init__(
        self,
        *,
        base_url: str | None = None,
        api_key: str | None = None,
        timeout: float = 10.0,
    ) -> None:
        self.base_url = (base_url or os.environ.get("COINGECKO_BASE_URL") or "https://api.coingecko.com/api/v3").rstrip("/")
        self.api_key = api_key or os.environ.get("COINGECKO_API_KEY") or os.environ.get("CG_DEMO_API_KEY")
        self.timeout = timeout

    def global_data(self) -> dict[str, Any]:
        return self._request("/global")

    def coins_markets(
        self,
        *,
        ids: tuple[str, ...] | None = None,
        order: str = "market_cap_desc",
        per_page: int = 250,
        page: int = 1,
    ) -> list[dict[str, Any]]:
        params: dict[str, Any] = {
            "vs_currency": "usd",
            "order": order,
            "per_page": per_page,
            "page": page,
            "sparkline": "false",
            "price_change_percentage": "24h",
        }
        if ids:
            params["ids"] = ",".join(ids)
        data = self._request("/coins/markets", params)
        if not isinstance(data, list):
            raise ValueError("CoinGecko /coins/markets response must be a list")
        return data

    def _request(self, path: str, params: dict[str, Any] | None = None):
        url = f"{self.base_url}{path}"
        if params:
            url = f"{url}?{urlencode(params, doseq=True)}"
        headers = {"accept": "application/json", "user-agent": "mino-rebalancing/0.1"}
        if self.api_key:
            header = "x-cg-pro-api-key" if "pro-api" in self.base_url else "x-cg-demo-api-key"
            headers[header] = self.api_key
        request = Request(url, headers=headers)
        with urlopen(request, timeout=self.timeout) as response:
            return json.loads(response.read().decode("utf-8"))


_CACHE: tuple[float, MarketInternals] | None = None


def build_market_internals(
    *,
    binance: BinanceFuturesClient,
    candidates: list[MarketCandidate],
    coingecko: CoinGeckoClient | None = None,
) -> MarketInternals:
    global _CACHE
    ttl_seconds = _env_int("MARKET_INTERNALS_CACHE_SECONDS", 300)
    now = time.time()
    if _CACHE and now - _CACHE[0] < ttl_seconds:
        cached = _CACHE[1]
        return replace(cached, messages=cached.messages + ("market internals cache hit",))

    coingecko = coingecko or CoinGeckoClient()
    messages: list[str] = []
    cap_snapshot = _market_cap_internals(coingecko, messages)
    breadth_snapshot = _breadth_internals(binance, candidates, messages)
    result = _merge_internals(cap_snapshot, breadth_snapshot, messages)
    _CACHE = (now, result)
    return result


def apply_market_cap_dominance(
    candidates: list[MarketCandidate],
    internals: MarketInternals,
) -> list[MarketCandidate]:
    if not internals.top10_market_cap_coins:
        return candidates

    rank_by_symbol = {
        coin.symbol.upper(): (rank, coin)
        for rank, coin in enumerate(internals.top10_market_cap_coins, start=1)
    }
    updated: list[MarketCandidate] = []
    for candidate in candidates:
        match = rank_by_symbol.get(candidate.base_asset.upper())
        if match is None:
            fallback_rank = candidate.dominance_rank if candidate.dominance_rank is not None else 10_000
            updated.append(replace(candidate, dominance_rank=10_000 + fallback_rank))
            continue
        rank, coin = match
        dominance_pct = (
            coin.market_cap / internals.total_market_cap_usd * 100
            if internals.total_market_cap_usd and internals.total_market_cap_usd > 0
            else candidate.dominance_pct
        )
        updated.append(
            replace(
                candidate,
                dominance_rank=rank,
                dominance_pct=dominance_pct,
                market_cap_rank=coin.market_cap_rank or rank,
            )
        )
    return updated


def advance_decline_from_candidates(candidates: list[MarketCandidate], *, limit: int = 200) -> tuple[int, int, int, float | None]:
    universe = _eligible_candidates(candidates)[:limit]
    advance = sum(1 for candidate in universe if candidate.change_24h_pct > 0)
    decline = sum(1 for candidate in universe if candidate.change_24h_pct < 0)
    flat = len(universe) - advance - decline
    ratio = None
    if decline > 0:
        ratio = advance / decline
    elif advance > 0:
        ratio = float(advance)
    return advance, decline, flat, ratio


def _market_cap_internals(coingecko: CoinGeckoClient, messages: list[str]) -> MarketInternals:
    try:
        global_data = coingecko.global_data()
        total_market_cap = float(global_data["data"]["total_market_cap"]["usd"])
        markets = [_coin_from_market(item) for item in coingecko.coins_markets(per_page=250, page=1)]
        stable_markets = [_coin_from_market(item) for item in coingecko.coins_markets(ids=STABLE_COINGECKO_IDS)]
        stable_cap = sum(coin.market_cap for coin in stable_markets if coin.market_cap > 0)
        top10 = tuple(
            coin
            for coin in markets
            if coin.symbol.upper() not in STABLE_BASE_ASSETS and coin.market_cap > 0
        )[:10]
        top10_cap = sum(coin.market_cap for coin in top10)
        top10_alt_cap = sum(coin.market_cap for coin in top10 if coin.symbol.upper() != "BTC")
        btc_cap = next((coin.market_cap for coin in markets if coin.symbol.upper() == "BTC"), 0.0)
        total2_cap = total_market_cap - btc_cap

        messages.append("CoinGecko market-cap internals loaded")
        return MarketInternals(
            source="coingecko",
            stable_dominance_pct=_pct(stable_cap, total_market_cap),
            top10_dominance_total_pct=_pct(top10_cap, total_market_cap),
            top10_dominance_total2_pct=_pct(top10_alt_cap, total2_cap),
            total_market_cap_usd=total_market_cap,
            stable_market_cap_usd=stable_cap,
            top10_market_cap_usd=top10_cap,
            top10_market_cap_coins=top10,
        )
    except Exception as exc:
        messages.append(f"CoinGecko market-cap internals unavailable: {exc}")
        return MarketInternals(source="binance")


def _breadth_internals(
    binance: BinanceFuturesClient,
    candidates: list[MarketCandidate],
    messages: list[str],
) -> MarketInternals:
    universe_limit = _env_int("MARKET_INTERNALS_UNIVERSE_LIMIT", 200)
    breadth_limit = _env_int("MARKET_INTERNALS_BREADTH_LIMIT", 100)
    universe = _eligible_candidates(candidates)[:universe_limit]
    top10 = universe[:10]
    total_volume = sum(candidate.quote_volume_24h for candidate in universe if candidate.quote_volume_24h > 0)
    btc_volume = next((candidate.quote_volume_24h for candidate in universe if candidate.base_asset.upper() == "BTC"), 0.0)
    total2_volume = total_volume - btc_volume
    top10_volume = sum(candidate.quote_volume_24h for candidate in top10)
    top10_alt_volume = sum(candidate.quote_volume_24h for candidate in top10 if candidate.base_asset.upper() != "BTC")
    advance, decline, flat, ratio = advance_decline_from_candidates(universe, limit=universe_limit)
    breadth_count = 0
    breadth_total = 0

    if os.environ.get("MARKET_INTERNALS_DISABLE_VOLUME_BREADTH", "").lower() == "true":
        messages.append("volume breadth disabled by MARKET_INTERNALS_DISABLE_VOLUME_BREADTH")
    else:
        max_workers = max(1, _env_int("MARKET_INTERNALS_BREADTH_WORKERS", 8))
        with ThreadPoolExecutor(max_workers=max_workers) as executor:
            futures = {
                executor.submit(_volume_above_ema20, binance, candidate): candidate
                for candidate in universe[:breadth_limit]
            }
            for future in as_completed(futures):
                candidate = futures[future]
                try:
                    above = future.result()
                except Exception as exc:
                    messages.append(f"volume breadth skipped {candidate.symbol}: {exc}")
                    continue
                if above is None:
                    continue
                breadth_total += 1
                if above:
                    breadth_count += 1

    volume_breadth_pct = _pct(breadth_count, breadth_total) if breadth_total else None
    messages.append(f"advance/decline loaded for {len(universe)} candidates")
    if breadth_total:
        messages.append(f"volume breadth loaded for {breadth_total} candidates")

    return MarketInternals(
        source="binance",
        top10_dominance_total_pct=_pct(top10_volume, total_volume),
        top10_dominance_total2_pct=_pct(top10_alt_volume, total2_volume),
        volume_breadth_pct=volume_breadth_pct,
        volume_breadth_count=breadth_count,
        volume_breadth_total=breadth_total,
        advance_count=advance,
        decline_count=decline,
        flat_count=flat,
        advance_decline_ratio=ratio,
        breadth_universe_size=len(universe),
    )


def _merge_internals(
    cap: MarketInternals,
    breadth: MarketInternals,
    messages: list[str],
) -> MarketInternals:
    risk_label = _risk_label(
        stable_dominance_pct=cap.stable_dominance_pct,
        volume_breadth_pct=breadth.volume_breadth_pct,
        advance_decline_ratio=breadth.advance_decline_ratio,
    )
    source = "coingecko+binance" if cap.top10_market_cap_coins else "binance"
    return MarketInternals(
        source=source,
        stable_dominance_pct=cap.stable_dominance_pct,
        top10_dominance_total_pct=cap.top10_dominance_total_pct
        if cap.top10_dominance_total_pct is not None
        else breadth.top10_dominance_total_pct,
        top10_dominance_total2_pct=cap.top10_dominance_total2_pct
        if cap.top10_dominance_total2_pct is not None
        else breadth.top10_dominance_total2_pct,
        total_market_cap_usd=cap.total_market_cap_usd,
        stable_market_cap_usd=cap.stable_market_cap_usd,
        top10_market_cap_usd=cap.top10_market_cap_usd,
        top10_market_cap_coins=cap.top10_market_cap_coins,
        volume_breadth_pct=breadth.volume_breadth_pct,
        volume_breadth_count=breadth.volume_breadth_count,
        volume_breadth_total=breadth.volume_breadth_total,
        advance_count=breadth.advance_count,
        decline_count=breadth.decline_count,
        flat_count=breadth.flat_count,
        advance_decline_ratio=breadth.advance_decline_ratio,
        breadth_universe_size=breadth.breadth_universe_size,
        risk_label=risk_label,
        messages=tuple(messages),
    )


def _coin_from_market(item: dict[str, Any]) -> MarketCapCoin:
    return MarketCapCoin(
        id=str(item.get("id", "")),
        symbol=str(item.get("symbol", "")).upper(),
        name=str(item.get("name", "")),
        market_cap=float(item.get("market_cap") or 0.0),
        market_cap_rank=int(item["market_cap_rank"]) if item.get("market_cap_rank") is not None else None,
        price_change_24h_pct=float(
            item.get("price_change_percentage_24h_in_currency")
            if item.get("price_change_percentage_24h_in_currency") is not None
            else item.get("price_change_percentage_24h") or 0.0
        ),
    )


def _eligible_candidates(candidates: list[MarketCandidate]) -> list[MarketCandidate]:
    return sorted(
        (
            candidate
            for candidate in candidates
            if not candidate.stablecoin and candidate.base_asset.upper() not in STABLE_BASE_ASSETS
        ),
        key=lambda candidate: candidate.quote_volume_24h,
        reverse=True,
    )


def _volume_above_ema20(binance: BinanceFuturesClient, candidate: MarketCandidate) -> bool | None:
    candles = binance.klines(candidate.symbol, "1d", limit=21)
    volumes = [candle.volume for candle in candles]
    if len(volumes) < 20:
        return None
    baseline = _ema(volumes[:-1], 20) if len(volumes) > 20 else _ema(volumes, 20)
    return volumes[-1] > baseline


def _ema(values: list[float], period: int) -> float:
    if not values:
        return 0.0
    alpha = 2 / (period + 1)
    ema = values[0]
    for value in values[1:]:
        ema = value * alpha + ema * (1 - alpha)
    return ema


def _pct(numerator: float, denominator: float) -> float | None:
    if denominator <= 0:
        return None
    return numerator / denominator * 100


def _risk_label(
    *,
    stable_dominance_pct: float | None,
    volume_breadth_pct: float | None,
    advance_decline_ratio: float | None,
) -> str:
    if volume_breadth_pct is not None and advance_decline_ratio is not None:
        if volume_breadth_pct >= 60 and advance_decline_ratio >= 1.5:
            return "BROAD_RISK_ON"
        if volume_breadth_pct <= 35 or advance_decline_ratio <= 0.7:
            return "BROAD_RISK_OFF"
    if stable_dominance_pct is not None and stable_dominance_pct >= 10:
        return "STABLE_DEFENSIVE"
    return "MIXED"


def _env_int(name: str, default: int) -> int:
    try:
        return int(os.environ.get(name, default))
    except ValueError:
        return default
