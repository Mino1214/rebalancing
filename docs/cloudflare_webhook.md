# Cloudflare Webhook Receiver

TradingView webhook 수신은 Cloudflare Workers로 시작하는 것이 좋습니다. TradingView는 웹훅 서버가 3초 안에 응답하지 않으면 요청을 취소하므로, Worker는 빠르게 검증하고 `202 Accepted`를 반환한 뒤 Queue나 private backend로 넘기는 역할에 집중합니다.

## 권장 구조

```text
TradingView Alert
-> Cloudflare Worker
   - POST only
   - JSON schema validation
   - passphrase check
   - stale alert check
   - max leverage check
   - signal_id dedupe
-> Cloudflare Queue or Tunnel
-> Private execution engine
-> Binance
```

초기에는 Worker가 직접 Binance 주문을 실행하지 않게 두는 편이 안전합니다. Binance key는 실행 엔진 쪽 환경변수에 두고, Worker에는 TradingView passphrase와 Queue/Tunnel 연결 정보만 둡니다.

## 왜 Cloudflare가 맞는가

- Workers는 HTTPS endpoint를 빠르게 만들기 좋습니다.
- Secrets를 Worker 환경변수처럼 사용할 수 있습니다.
- Queues로 요청 처리와 실제 실행을 분리할 수 있습니다.
- Tunnel로 집이나 개인 서버의 실행 엔진을 공개 포트 없이 연결할 수 있습니다.

## 배포 순서

```bash
cd workers/tradingview-webhook
npm install
npx wrangler login
npx wrangler secret put TV_WEBHOOK_PASSPHRASE
npx wrangler kv namespace create TV_ALERT_DEDUPE
```

`wrangler.toml`의 `[[kv_namespaces]]` 주석을 풀고 발급된 `id`를 넣습니다.

```bash
npm run deploy
```

TradingView webhook URL에는 배포된 Worker URL을 넣습니다.

## Queue를 붙일 때

```bash
npx wrangler queues create tv-alerts
```

`wrangler.toml`의 `[[queues.producers]]` 주석을 풀면 Worker가 검증된 alert를 Queue에 넣습니다. 실행 엔진은 Queue consumer 또는 별도 private endpoint 방식으로 이어 붙입니다.

## 최소 운영 규칙

- TradingView alert에는 `schema`, `signal_id`, `time_ms`, `bar_time_ms`, `confirmed`, `passphrase`를 넣습니다.
- Worker는 3초 안에 응답해야 합니다.
- 중복 signal은 7일 정도 dedupe합니다.
- stale alert는 기본 300초 초과 시 폐기합니다.
- 실거래 주문은 Worker가 아니라 private execution engine에서 처리합니다.

