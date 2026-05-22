from __future__ import annotations

from datetime import datetime, timedelta

from .models import (
    BtcMarketSnapshot,
    EngineConfig,
    EngineState,
    MarketBias,
    MarketCandidate,
    Position,
    PositionSide,
    TargetPosition,
)


STABLE_BASE_ASSETS = {
    "USDT",
    "USDC",
    "BUSD",
    "FDUSD",
    "DAI",
    "TUSD",
    "USDE",
    "USDS",
    "USD1",
    "PYUSD",
    "FRAX",
    "LUSD",
    "GUSD",
    "USDP",
    "EURC",
    "EURS",
    "SUSD",
}


class PortfolioBuilder:
    def __init__(self, config: EngineConfig | None = None) -> None:
        self.config = config or EngineConfig()

    def select_long_universe(self, candidates: list[MarketCandidate]) -> list[MarketCandidate]:
        eligible = [candidate for candidate in candidates if self._eligible(candidate)]
        market_cap_matched = [candidate for candidate in eligible if candidate.market_cap_rank is not None]
        if market_cap_matched:
            eligible = market_cap_matched
        return sorted(
            eligible,
            key=self._dominance_sort_key,
        )[: self.config.long_universe_size]

    def select_short_universe(self, candidates: list[MarketCandidate]) -> list[MarketCandidate]:
        eligible = [candidate for candidate in candidates if self._eligible(candidate)]
        by_symbol = {candidate.symbol: candidate for candidate in eligible}

        core = [by_symbol[symbol] for symbol in ("BTCUSDT", "ETHUSDT") if symbol in by_symbol]
        core_symbols = {candidate.symbol for candidate in core}
        alts = [
            candidate
            for candidate in eligible
            if candidate.symbol not in core_symbols and candidate.squeeze_risk_score < 0.75
        ]
        weakest_alts = sorted(
            alts,
            key=lambda item: (item.change_24h_pct, item.squeeze_risk_score, -item.quote_volume_24h),
        )[: self.config.short_alt_count]

        return core + weakest_alts

    def build_long_targets(
        self,
        equity: float,
        candidates: list[MarketCandidate],
        leverage: float | None = None,
        market_bias: MarketBias = MarketBias.BROAD_BULL,
    ) -> tuple[TargetPosition, ...]:
        if market_bias == MarketBias.BTC_ONLY_BULL:
            universe = self._select_core_long_universe(candidates)
            target_notional = self._capped_notional(equity, leverage or self.config.btc_only_target_leverage)
            return self._weighted_targets(
                symbols=[candidate.symbol for candidate in universe],
                side=PositionSide.LONG,
                target_notional=target_notional,
                core_weights={"BTCUSDT": 0.65, "ETHUSDT": 0.35},
                residual_weight=0.0,
            )

        universe = self.select_long_universe(candidates)
        target_notional = self._capped_notional(equity, leverage or self.config.bull_target_leverage)
        return self._weighted_targets(
            symbols=[candidate.symbol for candidate in universe],
            side=PositionSide.LONG,
            target_notional=target_notional,
            core_weights={"BTCUSDT": 0.25, "ETHUSDT": 0.20},
            residual_weight=0.55,
        )

    def build_short_targets(
        self,
        equity: float,
        candidates: list[MarketCandidate],
        btc: BtcMarketSnapshot,
        state: EngineState,
        now: datetime,
        market_bias: MarketBias = MarketBias.BROAD_BEAR,
    ) -> tuple[TargetPosition, ...]:
        universe = self.select_short_universe(candidates)
        leverage = self.bear_leverage(btc=btc, state=state, now=now)
        target_notional = self._capped_notional(equity, leverage)
        core_weights = {"BTCUSDT": 0.35, "ETHUSDT": 0.25} if market_bias == MarketBias.ALT_WEAK_BEAR else {"BTCUSDT": 0.40, "ETHUSDT": 0.30}
        residual_weight = 0.40 if market_bias == MarketBias.ALT_WEAK_BEAR else 0.30
        return self._weighted_targets(
            symbols=[candidate.symbol for candidate in universe],
            side=PositionSide.SHORT,
            target_notional=target_notional,
            core_weights=core_weights,
            residual_weight=residual_weight,
        )

    def build_range_targets(self, equity: float, positions: list[Position]) -> tuple[TargetPosition, ...]:
        if self.config.range_target_leverage <= 0:
            return tuple()

        max_notional = self._capped_notional(equity, self.config.range_target_leverage)
        return self.cap_positions_to_notional(positions, max_notional)

    def scale_positions(self, positions: list[Position], fraction: float) -> tuple[TargetPosition, ...]:
        if fraction <= 0:
            return tuple()
        return tuple(
            TargetPosition(symbol=position.symbol, side=position.side, notional=position.notional * fraction)
            for position in positions
            if position.notional * fraction >= self.config.min_order_notional
        )

    def cap_positions_to_notional(self, positions: list[Position], max_notional: float) -> tuple[TargetPosition, ...]:
        total = sum(position.notional for position in positions)
        if total <= 0 or max_notional <= 0:
            return tuple()
        fraction = min(1.0, max_notional / total)
        return self.scale_positions(positions, fraction)

    def bear_leverage(self, btc: BtcMarketSnapshot, state: EngineState, now: datetime) -> float:
        if btc.adx_1d >= self.config.bear_strong_adx:
            return self.config.bear_strong_leverage

        if state.mode_started_at is not None and now - state.mode_started_at < timedelta(hours=self.config.bear_initial_hours):
            return self.config.bear_initial_leverage

        return self.config.bear_confirmed_leverage

    def _select_core_long_universe(self, candidates: list[MarketCandidate]) -> list[MarketCandidate]:
        eligible = {candidate.symbol: candidate for candidate in candidates if self._eligible(candidate)}
        core = [eligible[symbol] for symbol in ("BTCUSDT", "ETHUSDT") if symbol in eligible]
        if core:
            return core
        return self.select_long_universe(candidates)[:2]

    def _eligible(self, candidate: MarketCandidate) -> bool:
        if not candidate.is_usdt_m_perp:
            return False
        if candidate.quote_asset != "USDT":
            return False
        if candidate.stablecoin or candidate.base_asset.upper() in STABLE_BASE_ASSETS:
            return False
        if candidate.quote_volume_24h < self.config.min_quote_volume_24h:
            return False
        if candidate.spread_bps > self.config.max_spread_bps:
            return False
        if candidate.listed_days < self.config.min_listed_days:
            return False
        if abs(candidate.change_24h_pct) > self.config.max_abs_change_24h_pct:
            return False
        return True

    def _dominance_sort_key(self, candidate: MarketCandidate) -> tuple[int, float, int, float]:
        dominance_rank = candidate.dominance_rank if candidate.dominance_rank is not None else 10_000
        dominance_pct = candidate.dominance_pct if candidate.dominance_pct is not None else -1.0
        market_cap_rank = candidate.market_cap_rank if candidate.market_cap_rank is not None else 10_000
        return (dominance_rank, -dominance_pct, market_cap_rank, -candidate.quote_volume_24h)

    def _weighted_targets(
        self,
        symbols: list[str],
        side: PositionSide,
        target_notional: float,
        core_weights: dict[str, float],
        residual_weight: float,
    ) -> tuple[TargetPosition, ...]:
        if not symbols or target_notional <= 0:
            return tuple()

        symbol_set = set(symbols)
        weights: dict[str, float] = {}
        missing_weight = 0.0

        for symbol, weight in core_weights.items():
            if symbol in symbol_set:
                weights[symbol] = weight
            else:
                missing_weight += weight

        residual_symbols = [symbol for symbol in symbols if symbol not in weights]
        residual_total = residual_weight + missing_weight
        if residual_symbols:
            each = residual_total / len(residual_symbols)
            for symbol in residual_symbols:
                weights[symbol] = each
        elif weights:
            scale = 1.0 / sum(weights.values())
            weights = {symbol: weight * scale for symbol, weight in weights.items()}

        total_weight = sum(weights.values())
        if total_weight <= 0:
            return tuple()

        normalized = {symbol: weight / total_weight for symbol, weight in weights.items()}
        return tuple(
            TargetPosition(
                symbol=symbol,
                side=side,
                notional=target_notional * weight,
                weight=weight,
            )
            for symbol, weight in normalized.items()
            if target_notional * weight >= self.config.min_order_notional
        )

    def _capped_notional(self, equity: float, leverage: float) -> float:
        return equity * min(leverage, self.config.max_leverage)
