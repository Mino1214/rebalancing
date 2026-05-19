# Cloudflare Tunnel

Cloudflare Tunnel is for exposing the private execution engine without opening inbound ports on the machine.

Recommended path:

```text
TradingView
-> Cloudflare Worker webhook receiver
-> private execution engine through Cloudflare Tunnel
-> Binance
```

The Worker remains the public webhook gate. The tunnel is for the local/private service that runs state storage, paper trading, and eventually live execution.

## Current Tunnel

A named tunnel was created:

```text
name: rebalancing-engine
id: 69925190-71e3-4b34-8dd2-4bc4583bf65a
```

The credentials file is outside the repo under the local Cloudflare directory. Keep it secret and never commit it.

## Local Service

Use port `8788` for the private engine API.

```text
http://localhost:8788
```

Initial endpoints to implement:

- `GET /health`
- `GET /status`
- `GET /positions`
- `GET /orders/recent`
- `GET /risk`

The Flutter app should read from the private API. It should not send trade commands.

## Route A Hostname

Pick a hostname on a domain that is already in the Cloudflare account.

Example:

```bash
cloudflared tunnel route dns rebalancing-engine engine.example.com
```

Then copy the example config:

```bash
mkdir -p ~/.cloudflared
cp deploy/cloudflared/rebalancing-engine.example.yml ~/.cloudflared/rebalancing-engine.yml
```

Edit it:

```yaml
tunnel: 69925190-71e3-4b34-8dd2-4bc4583bf65a
credentials-file: /absolute/path/to/69925190-71e3-4b34-8dd2-4bc4583bf65a.json

ingress:
  - hostname: engine.example.com
    service: http://localhost:8788
  - service: http_status:404
```

Run it:

```bash
cloudflared tunnel --config ~/.cloudflared/rebalancing-engine.yml run rebalancing-engine
```

## Temporary Test Tunnel

For a short-lived test without a stable hostname:

```bash
cloudflared tunnel --url http://localhost:8788
```

This creates a temporary `trycloudflare.com` URL. Do not use it for TradingView production alerts because the URL changes whenever the tunnel restarts.

## Production Notes

- Run `cloudflared` as a service on the machine that runs the engine.
- Protect non-webhook endpoints with Cloudflare Access.
- Keep Binance API keys only on the private engine host.
- Keep Flutter read-only.
- Do not expose manual trade endpoints.
- Do not commit tunnel credentials.
