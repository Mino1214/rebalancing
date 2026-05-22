# Operation Endpoints

## TradingView Webhook

Use this URL in TradingView alerts:

```text
https://tradingview-webhook.mino1214-rebalancing.workers.dev
```

The webhook passphrase is stored locally and is not committed:

```bash
cat workers/tradingview-webhook/.secrets/tradingview_webhook_passphrase.txt
```

## Timeframe

Production alert cadence:

```text
5 minutes / 5M
```

The 5M alert is only the webhook cadence and execution helper. The payload includes 24H/12H direction filters, 8H/4H regime confirmation, 1H timing, and 5M execution flags; the server decides the final action.

Use `1` minute only for receive tests. After confirming the webhook receives alerts, switch TradingView back to the MTF script's default `5M Execution` input.

Recommended test flow:

```text
1m alert
-> Worker accepts payload
-> duplicate signal_id is rejected
-> switch TradingView 5M Execution input back to 5
```

## Private Engine Tunnel

Private engine API hostname:

```text
https://engine.medicalnewshub.info
```

It routes to this PC:

```text
http://localhost:8788
```

Run the local status API:

```bash
PYTHONPATH=src python -m rebalancing.status_server
```

Then verify:

```bash
curl http://127.0.0.1:8788/health
curl https://engine.medicalnewshub.info/status
```

`/status` returns account equity, exposure, regime, positions, planned orders, risk state, events, market internals, and app watchlist rows. Without Binance environment keys it still returns a fallback account plus live public Binance futures universe data.

Market internal fields:

```text
market_internals.stable_dominance_pct
market_internals.top10_dominance_total_pct
market_internals.top10_dominance_total2_pct
market_internals.volume_breadth_pct
market_internals.advance_decline_ratio
```

## Observer App

The Flutter observer app lives here:

```text
apps/rebalancing_observer
```

Run the Flutter app with the tunnel API:

```bash
cd apps/rebalancing_observer
flutter run --dart-define=API_BASE_URL=https://engine.medicalnewshub.info
```

The app is read-only. It has no order approval, manual trade, or leverage-change controls.
