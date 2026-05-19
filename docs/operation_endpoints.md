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

Production signal timeframe:

```text
240 minutes / 4H
```

Use `1` minute only for receive tests. After confirming the webhook receives alerts, switch TradingView back to `240`.

Recommended test flow:

```text
1m alert
-> Worker accepts payload
-> duplicate signal_id is rejected
-> switch TradingView Signal Timeframe to 240
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

Current expected state before the engine API exists:

```text
502 from engine.medicalnewshub.info
```

When the read-only engine API is running on `localhost:8788`, the tunnel will serve it through `engine.medicalnewshub.info`.

## Observer App

The Flutter observer app lives here:

```text
apps/rebalancing_observer
```

Run a local web build:

```bash
cd apps/rebalancing_observer
flutter build web --dart-define=API_BASE_URL=https://engine.medicalnewshub.info
python -m http.server 8789 --directory build/web --bind 127.0.0.1
```

Open:

```text
http://127.0.0.1:8789
```

The app is read-only. It has no order approval, manual trade, or leverage-change controls.

