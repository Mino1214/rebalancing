# Learning Parameter Discovery

Phase 3 discovery result for the self-learning loop. The bot may only tune
bot-side parameters that already live in `EngineConfig`; TradingView/Pine signal
parameters remain human-reviewed suggestions only.

## Current Data State

- `decisions`: 6 paper records
- `trade_results`: 0 records
- `evaluations`: 0 records

The learning loop can build prompts from decisions now, but profit/loss diagnosis
will be weak until `trade_results` or equivalent closed-trade PnL records are
populated.

## Suggested Auto-Tunable Parameters

These are good first candidates for an approve-mode tuning layer because they
change exposure, thresholds, or rebalance sensitivity without changing core
control flow.

| Parameter | Default | Role | Suggested Guard |
| --- | ---: | --- | --- |
| `bull_target_leverage` | 2.0 | broad bull long exposure | 0.5 to 2.0 |
| `btc_only_target_leverage` | 1.0 | BTC-led bull core exposure | 0.25 to 1.5 |
| `range_target_leverage` | 0.0 | range-mode retained exposure | 0.0 to 0.5 |
| `bear_initial_leverage` | 0.5 | early bear short exposure | 0.0 to 1.0 |
| `bear_confirmed_leverage` | 1.0 | confirmed bear short exposure | 0.25 to 1.5 |
| `bear_strong_leverage` | 2.0 | strong bear short exposure | 0.5 to 2.0 |
| `bear_initial_hours` | 24.0 | duration of reduced early-bear sizing | 4.0 to 72.0 |
| `bear_strong_adx` | 30.0 | ADX needed for strong bear sizing | 22.0 to 45.0 |
| `adx_threshold` | 18.0 | BTC trend confirmation threshold | 12.0 to 30.0 |
| `market_index_adx_threshold` | 16.0 | TOTAL/TOTAL2/TOTAL3 confirmation threshold | 10.0 to 30.0 |
| `bull_score_threshold` | 70.0 | broad bull score threshold | 50.0 to 90.0 |
| `bear_score_threshold` | -70.0 | broad bear score threshold | -90.0 to -50.0 |
| `confirmation_candles` | 3 | raw regime persistence before confirmation | 1 to 6 |
| `min_neutral_hours` | 12.0 | wait before direct long/short flip after neutral | 1.0 to 48.0 |
| `chaotic_cooldown_hours` | 24.0 | pause duration after chaotic regime | 4.0 to 96.0 |
| `post_loss_cooldown_hours` | 72.0 | pause duration after monthly risk stop | 12.0 to 168.0 |
| `chaotic_4h_change_pct` | 6.0 | 4h shock threshold | 3.0 to 12.0 |
| `chaotic_atr_multiplier` | 2.0 | ATR shock threshold | 1.25 to 4.0 |
| `chaotic_volume_multiplier` | 3.0 | volume shock threshold | 1.5 to 6.0 |
| `overheated_funding_rate` | 0.001 | funding shock threshold | 0.0003 to 0.003 |
| `min_quote_volume_24h` | 50000000.0 | liquidity floor | 10000000.0 to 200000000.0 |
| `max_spread_bps` | 10.0 | spread quality filter | 2.0 to 30.0 |
| `min_listed_days` | 30 | listing-age filter | 7 to 180 |
| `max_abs_change_24h_pct` | 35.0 | single-coin shock exclusion | 10.0 to 80.0 |
| `long_universe_size` | 10 | broad bull universe size | 2 to 15 |
| `short_alt_count` | 4 | number of alt shorts beside BTC/ETH | 0 to 8 |
| `drift_threshold` | 0.25 | order trigger sensitivity vs target notional | 0.05 to 0.5 |
| `order_split_notional` | 200.0 | planned child order size | 20.0 to 1000.0 |
| `regular_rebalance_hours` | 168.0 | scheduled rebalance interval | 24.0 to 336.0 |
| `daily_loss_limit_pct` | -0.02 | block new entries after daily loss | -0.08 to -0.005 |
| `weekly_loss_limit_pct` | -0.05 | reduce half after weekly loss | -0.15 to -0.01 |
| `monthly_loss_limit_pct` | -0.1 | close all and pause after monthly loss | -0.25 to -0.03 |

## Keep Manual For Now

These should not be auto-tuned in the first implementation:

- `max_leverage`: global safety cap; keep hard-coded or human-approved only.
- `min_order_notional`: exchange/account-size dependent operational setting.
- `deposit_min_usdt`: wallet accounting sensitivity, not strategy quality.
- `deposit_timeframe_hours`: tied to operational candle timing.
- TradingView/Pine fields such as source regime, source target leverage, alert
  timeframe, and multi-timeframe signal logic.

## Apply Policy

Start with `approve` mode:

1. Store suggestions in `evaluations.param_suggestions`.
2. Clamp every suggested value to the guard range.
3. Insert a new inactive `bot_params` version.
4. Only activate after human approval.

Switch to `auto` only after enough paper data exists to evaluate at least several
closed trades across multiple regimes.
