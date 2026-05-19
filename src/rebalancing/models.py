from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime
from enum import StrEnum


class Regime(StrEnum):
    BULL = "BULL"
    BEAR = "BEAR"
    RANGE = "RANGE"
    CHAOTIC = "CHAOTIC"


class MarketBias(StrEnum):
    BROAD_BULL = "BROAD_BULL"
    BTC_ONLY_BULL = "BTC_ONLY_BULL"
    BROAD_BEAR = "BROAD_BEAR"
    ALT_WEAK_BEAR = "ALT_WEAK_BEAR"
    RANGE = "RANGE"
    CHAOTIC = "CHAOTIC"


class TrendDirection(StrEnum):
    UP = "UP"
    DOWN = "DOWN"
    MIXED = "MIXED"


class TradeMode(StrEnum):
    LONG = "LONG"
    SHORT = "SHORT"
    NEUTRAL = "NEUTRAL"
    PAUSED = "PAUSED"


class PositionSide(StrEnum):
    LONG = "LONG"
    SHORT = "SHORT"


class OrderSide(StrEnum):
    BUY = "BUY"
    SELL = "SELL"


class OrderType(StrEnum):
    LIMIT = "LIMIT"
    MARKET = "MARKET"


class RiskAction(StrEnum):
    NONE = "NONE"
    BLOCK_NEW_ENTRIES = "BLOCK_NEW_ENTRIES"
    REDUCE_HALF = "REDUCE_HALF"
    CLOSE_ALL_AND_PAUSE = "CLOSE_ALL_AND_PAUSE"


def is_directional_mode(mode: TradeMode) -> bool:
    return mode in {TradeMode.LONG, TradeMode.SHORT}


def mode_to_position_side(mode: TradeMode) -> PositionSide | None:
    if mode == TradeMode.LONG:
        return PositionSide.LONG
    if mode == TradeMode.SHORT:
        return PositionSide.SHORT
    return None


def opposite_mode(mode: TradeMode) -> TradeMode | None:
    if mode == TradeMode.LONG:
        return TradeMode.SHORT
    if mode == TradeMode.SHORT:
        return TradeMode.LONG
    return None


@dataclass(frozen=True)
class Candle:
    timestamp: datetime
    open: float
    high: float
    low: float
    close: float
    volume: float


@dataclass(frozen=True)
class BtcMarketSnapshot:
    close_1d: float
    ema20_1d: float
    ema60_1d: float
    ema200_1d: float
    ema20_4h: float
    ema60_4h: float
    adx_1d: float
    change_4h_pct: float = 0.0
    atr_1d: float | None = None
    atr_1d_baseline: float | None = None
    volume_4h: float | None = None
    volume_4h_baseline: float | None = None
    funding_rate: float | None = None


@dataclass(frozen=True)
class MarketIndexSnapshot:
    name: str
    close_1d: float
    ema20_1d: float
    ema60_1d: float
    ema200_1d: float | None = None
    ema20_4h: float | None = None
    ema60_4h: float | None = None
    adx_1d: float | None = None
    change_4h_pct: float = 0.0
    atr_1d: float | None = None
    atr_1d_baseline: float | None = None
    volume_4h: float | None = None
    volume_4h_baseline: float | None = None


@dataclass(frozen=True)
class CryptoMarketSnapshot:
    btc: BtcMarketSnapshot
    total: MarketIndexSnapshot | None = None
    total2: MarketIndexSnapshot | None = None
    total3: MarketIndexSnapshot | None = None
    btc_dominance: MarketIndexSnapshot | None = None


@dataclass(frozen=True)
class MarketCandidate:
    symbol: str
    base_asset: str
    quote_asset: str = "USDT"
    is_usdt_m_perp: bool = True
    quote_volume_24h: float = 0.0
    spread_bps: float = 0.0
    listed_days: int = 0
    dominance_rank: int | None = None
    dominance_pct: float | None = None
    market_cap_rank: int | None = None
    change_24h_pct: float = 0.0
    stablecoin: bool = False
    squeeze_risk_score: float = 0.0


@dataclass(frozen=True)
class Position:
    symbol: str
    side: PositionSide
    notional: float
    entry_price: float | None = None

    def __post_init__(self) -> None:
        if self.notional < 0:
            raise ValueError("position notional must be non-negative")


@dataclass(frozen=True)
class TargetPosition:
    symbol: str
    side: PositionSide
    notional: float
    weight: float = 0.0

    def __post_init__(self) -> None:
        if self.notional < 0:
            raise ValueError("target notional must be non-negative")


@dataclass(frozen=True)
class AccountSnapshot:
    equity: float
    wallet_balance: float
    day_start_equity: float
    week_start_equity: float
    month_start_equity: float

    def __post_init__(self) -> None:
        if self.equity <= 0:
            raise ValueError("equity must be positive")
        if self.wallet_balance < 0:
            raise ValueError("wallet_balance must be non-negative")


@dataclass(frozen=True)
class PlannedOrder:
    symbol: str
    side: OrderSide
    position_side: PositionSide
    notional: float
    order_type: OrderType
    reduce_only: bool
    reason: str

    def __post_init__(self) -> None:
        if self.notional <= 0:
            raise ValueError("order notional must be positive")


@dataclass(frozen=True)
class EngineConfig:
    max_leverage: float = 2.0
    bull_target_leverage: float = 2.0
    btc_only_target_leverage: float = 1.0
    range_target_leverage: float = 0.0
    bear_initial_leverage: float = 0.5
    bear_confirmed_leverage: float = 1.0
    bear_strong_leverage: float = 2.0
    bear_initial_hours: float = 24.0
    bear_strong_adx: float = 30.0
    adx_threshold: float = 18.0
    market_index_adx_threshold: float = 16.0
    bull_score_threshold: float = 70.0
    bear_score_threshold: float = -70.0
    confirmation_candles: int = 3
    min_neutral_hours: float = 12.0
    chaotic_cooldown_hours: float = 24.0
    post_loss_cooldown_hours: float = 72.0
    chaotic_4h_change_pct: float = 6.0
    chaotic_atr_multiplier: float = 2.0
    chaotic_volume_multiplier: float = 3.0
    overheated_funding_rate: float = 0.001
    min_quote_volume_24h: float = 50_000_000.0
    max_spread_bps: float = 10.0
    min_listed_days: int = 30
    max_abs_change_24h_pct: float = 35.0
    long_universe_size: int = 10
    short_alt_count: int = 4
    drift_threshold: float = 0.25
    order_split_notional: float = 200.0
    min_order_notional: float = 10.0
    regular_rebalance_hours: float = 24.0 * 7.0
    deposit_min_usdt: float = 1.0
    deposit_timeframe_hours: int = 4
    daily_loss_limit_pct: float = -0.02
    weekly_loss_limit_pct: float = -0.05
    monthly_loss_limit_pct: float = -0.10


@dataclass(frozen=True)
class EngineState:
    mode: TradeMode = TradeMode.NEUTRAL
    mode_started_at: datetime | None = None
    neutral_since: datetime | None = None
    pending_mode: TradeMode | None = None
    cooldown_until: datetime | None = None
    raw_regime_history: tuple[Regime, ...] = field(default_factory=tuple)
    last_confirmed_regime: Regime = Regime.RANGE
    last_directional_mode: TradeMode | None = None
    last_wallet_balance: float | None = None
    pending_deposit_rebalance_at: datetime | None = None
    last_rebalance_at: datetime | None = None


@dataclass(frozen=True)
class RebalanceDecision:
    now: datetime
    raw_regime: Regime
    regime: Regime
    market_bias: MarketBias
    regime_score: float
    mode: TradeMode
    target_positions: tuple[TargetPosition, ...]
    orders: tuple[PlannedOrder, ...]
    risk_action: RiskAction
    should_rebalance: bool
    reasons: tuple[str, ...]
    next_state: EngineState
