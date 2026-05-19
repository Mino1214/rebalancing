from __future__ import annotations

from dataclasses import dataclass

from .models import (
    BtcMarketSnapshot,
    CryptoMarketSnapshot,
    EngineConfig,
    EngineState,
    MarketBias,
    MarketIndexSnapshot,
    Regime,
    TrendDirection,
)


@dataclass(frozen=True)
class RegimeResult:
    raw: Regime
    confirmed: Regime
    bias: MarketBias
    score: float
    history: tuple[Regime, ...]
    reasons: tuple[str, ...]


class RegimeDetector:
    def __init__(self, config: EngineConfig | None = None) -> None:
        self.config = config or EngineConfig()

    def detect(self, market: BtcMarketSnapshot | CryptoMarketSnapshot, state: EngineState) -> RegimeResult:
        snapshot = self._as_market_snapshot(market)
        raw, bias, score, reasons = self.raw_signal(snapshot)
        history = (state.raw_regime_history + (raw,))[-self.config.confirmation_candles :]

        if raw == Regime.CHAOTIC:
            confirmed = Regime.CHAOTIC
            confirmed_bias = MarketBias.CHAOTIC
        elif self._persisted(history, Regime.BULL):
            confirmed = Regime.BULL
            confirmed_bias = bias
        elif self._persisted(history, Regime.BEAR):
            confirmed = Regime.BEAR
            confirmed_bias = bias
        else:
            confirmed = Regime.RANGE
            confirmed_bias = MarketBias.RANGE

        return RegimeResult(
            raw=raw,
            confirmed=confirmed,
            bias=confirmed_bias,
            score=score,
            history=history,
            reasons=tuple(reasons),
        )

    def raw_signal(self, market: CryptoMarketSnapshot) -> tuple[Regime, MarketBias, float, list[str]]:
        if self.is_chaotic(market):
            return Regime.CHAOTIC, MarketBias.CHAOTIC, 0.0, ["chaotic volatility guard triggered"]

        if self._missing_market_internals(market):
            btc_direction = self._btc_direction(market.btc)
            if btc_direction == TrendDirection.UP:
                return Regime.BULL, MarketBias.BROAD_BULL, 40.0, [
                    "BTC-only fallback: BTC above EMA200, EMA20>EMA60 on 1D/4H, ADX confirmed"
                ]
            if btc_direction == TrendDirection.DOWN:
                return Regime.BEAR, MarketBias.BROAD_BEAR, -40.0, [
                    "BTC-only fallback: BTC below EMA200, EMA20<EMA60 on 1D/4H, ADX confirmed"
                ]
            return Regime.RANGE, MarketBias.RANGE, 0.0, ["BTC-only fallback: trend filters are mixed or ADX is too low"]

        btc_direction = self._btc_direction(market.btc)
        total_direction = self._index_direction(market.total)
        total2_direction = self._index_direction(market.total2)
        total3_direction = self._index_direction(market.total3)
        dominance_direction = self._index_direction(market.btc_dominance, require_adx=False)

        alt_score, alt_direction = self._alt_score(total2_direction, total3_direction)
        score = (
            self._direction_score(btc_direction, 40.0)
            + self._direction_score(total_direction, 25.0)
            + alt_score
            + self._dominance_score(dominance_direction)
        )

        reasons = [
            f"market score {score:.1f}",
            f"BTC={btc_direction}",
            f"TOTAL={total_direction}",
            f"TOTAL2={total2_direction}",
            f"TOTAL3={total3_direction}",
            f"BTC.D={dominance_direction}",
        ]

        broad_bull = score >= self.config.bull_score_threshold
        btc_only_bull = (
            btc_direction == TrendDirection.UP
            and total_direction == TrendDirection.UP
            and (
                alt_direction != TrendDirection.UP
                or dominance_direction == TrendDirection.UP
            )
        )
        broad_bear = score <= self.config.bear_score_threshold
        alt_weak_bear = (
            btc_direction == TrendDirection.DOWN
            and total_direction == TrendDirection.DOWN
            and alt_direction == TrendDirection.DOWN
            and dominance_direction == TrendDirection.UP
        )

        if broad_bull:
            return Regime.BULL, MarketBias.BROAD_BULL, score, reasons + ["broad crypto risk-on confirmed"]
        if btc_only_bull:
            return Regime.BULL, MarketBias.BTC_ONLY_BULL, score, reasons + ["BTC-led bull; alt exposure should be reduced"]
        if alt_weak_bear:
            return Regime.BEAR, MarketBias.ALT_WEAK_BEAR, score, reasons + ["alt weakness bear confirmed"]
        if broad_bear:
            return Regime.BEAR, MarketBias.BROAD_BEAR, score, reasons + ["broad crypto risk-off confirmed"]

        return Regime.RANGE, MarketBias.RANGE, score, reasons + ["market internals are mixed"]

    def is_chaotic(self, market: BtcMarketSnapshot | CryptoMarketSnapshot) -> bool:
        snapshot = self._as_market_snapshot(market)
        if self._is_btc_chaotic(snapshot.btc):
            return True

        for index in (snapshot.total, snapshot.total2, snapshot.total3):
            if self._is_index_chaotic(index):
                return True

        return False

    def _is_btc_chaotic(self, btc: BtcMarketSnapshot) -> bool:
        if abs(btc.change_4h_pct) >= self.config.chaotic_4h_change_pct:
            return True

        if (
            btc.atr_1d is not None
            and btc.atr_1d_baseline is not None
            and btc.atr_1d_baseline > 0
            and btc.atr_1d / btc.atr_1d_baseline >= self.config.chaotic_atr_multiplier
        ):
            return True

        if (
            btc.volume_4h is not None
            and btc.volume_4h_baseline is not None
            and btc.volume_4h_baseline > 0
            and btc.volume_4h / btc.volume_4h_baseline >= self.config.chaotic_volume_multiplier
        ):
            return True

        if btc.funding_rate is not None and abs(btc.funding_rate) >= self.config.overheated_funding_rate:
            return True

        return False

    def _is_index_chaotic(self, index: MarketIndexSnapshot | None) -> bool:
        if index is None:
            return False

        if abs(index.change_4h_pct) >= self.config.chaotic_4h_change_pct:
            return True

        if (
            index.atr_1d is not None
            and index.atr_1d_baseline is not None
            and index.atr_1d_baseline > 0
            and index.atr_1d / index.atr_1d_baseline >= self.config.chaotic_atr_multiplier
        ):
            return True

        if (
            index.volume_4h is not None
            and index.volume_4h_baseline is not None
            and index.volume_4h_baseline > 0
            and index.volume_4h / index.volume_4h_baseline >= self.config.chaotic_volume_multiplier
        ):
            return True

        return False

    def _btc_direction(self, btc: BtcMarketSnapshot) -> TrendDirection:
        up = (
            btc.close_1d > btc.ema200_1d
            and btc.ema20_1d > btc.ema60_1d
            and btc.ema20_4h > btc.ema60_4h
            and btc.adx_1d >= self.config.adx_threshold
        )
        if up:
            return TrendDirection.UP

        down = (
            btc.close_1d < btc.ema200_1d
            and btc.ema20_1d < btc.ema60_1d
            and btc.ema20_4h < btc.ema60_4h
            and btc.adx_1d >= self.config.adx_threshold
        )
        if down:
            return TrendDirection.DOWN

        return TrendDirection.MIXED

    def _index_direction(
        self,
        index: MarketIndexSnapshot | None,
        *,
        require_adx: bool = True,
    ) -> TrendDirection:
        if index is None:
            return TrendDirection.MIXED

        adx_ok = (
            not require_adx
            or index.adx_1d is None
            or index.adx_1d >= self.config.market_index_adx_threshold
        )
        ema200_up_ok = index.ema200_1d is None or index.close_1d > index.ema200_1d
        ema200_down_ok = index.ema200_1d is None or index.close_1d < index.ema200_1d
        four_hour_up_ok = (
            index.ema20_4h is None
            or index.ema60_4h is None
            or index.ema20_4h > index.ema60_4h
        )
        four_hour_down_ok = (
            index.ema20_4h is None
            or index.ema60_4h is None
            or index.ema20_4h < index.ema60_4h
        )

        if index.ema20_1d > index.ema60_1d and ema200_up_ok and four_hour_up_ok and adx_ok:
            return TrendDirection.UP
        if index.ema20_1d < index.ema60_1d and ema200_down_ok and four_hour_down_ok and adx_ok:
            return TrendDirection.DOWN
        return TrendDirection.MIXED

    def _alt_score(
        self,
        total2_direction: TrendDirection,
        total3_direction: TrendDirection,
    ) -> tuple[float, TrendDirection]:
        directions = (total2_direction, total3_direction)
        if directions == (TrendDirection.UP, TrendDirection.UP):
            return 25.0, TrendDirection.UP
        if directions == (TrendDirection.DOWN, TrendDirection.DOWN):
            return -25.0, TrendDirection.DOWN
        if TrendDirection.UP in directions and TrendDirection.DOWN not in directions:
            return 12.5, TrendDirection.MIXED
        if TrendDirection.DOWN in directions and TrendDirection.UP not in directions:
            return -12.5, TrendDirection.MIXED
        return 0.0, TrendDirection.MIXED

    def _direction_score(self, direction: TrendDirection, weight: float) -> float:
        if direction == TrendDirection.UP:
            return weight
        if direction == TrendDirection.DOWN:
            return -weight
        return 0.0

    def _dominance_score(self, direction: TrendDirection) -> float:
        if direction == TrendDirection.DOWN:
            return 10.0
        if direction == TrendDirection.UP:
            return -10.0
        return 0.0

    def _as_market_snapshot(self, market: BtcMarketSnapshot | CryptoMarketSnapshot) -> CryptoMarketSnapshot:
        if isinstance(market, CryptoMarketSnapshot):
            return market
        return CryptoMarketSnapshot(btc=market)

    def _missing_market_internals(self, market: CryptoMarketSnapshot) -> bool:
        return all(
            item is None
            for item in (
                market.total,
                market.total2,
                market.total3,
                market.btc_dominance,
            )
        )

    def _persisted(self, history: tuple[Regime, ...], regime: Regime) -> bool:
        return len(history) >= self.config.confirmation_candles and all(item == regime for item in history)
