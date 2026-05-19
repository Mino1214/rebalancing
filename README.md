# Rebalancing Engine

BTC 레짐을 기준으로 USDT-M 선물 노출을 자동 조절하는 자산배분 엔진입니다.

이 프로젝트는 실거래 주문 봇이 아니라, 아래 결정을 재현 가능하게 만드는 코어 로직입니다.

```text
USDT 입금
-> 총자산 계산
-> BTC 레짐 판단
-> 목표 노출 결정
-> 코인 선정
-> 롱/숏 방향 결정
-> 자동 리밸런싱 주문 계획
-> 리스크 제한
```

## 핵심 규칙

- 최대 노출은 총자산 기준 2배입니다.
- 레짐은 `BULL`, `BEAR`, `RANGE`, `CHAOTIC` 네 가지입니다.
- `LONG -> SHORT`, `SHORT -> LONG` 직접 전환은 금지됩니다.
- 방향 전환은 항상 `LONG -> NEUTRAL -> SHORT` 또는 `SHORT -> NEUTRAL -> LONG`으로 진행됩니다.
- USDT 입금은 즉시 풀진입하지 않고 다음 4시간봉 마감 이후 리밸런싱합니다.
- 일/주/월 손실 제한이 먼저 적용됩니다.
- 청산/축소 주문은 `reduce_only`로 계획됩니다.
- 롱 유니버스는 스테이블코인을 제외한 상위 도미넌스 10개 코인을 기준으로 합니다.

## 구조

```text
src/rebalancing/
  engine.py       전체 의사결정 플로우
  regime.py       BTC + TOTAL + TOTAL2/TOTAL3 + BTC.D 점수제 레짐 감지
  transitions.py  롱/숏 직접 전환 방지
  portfolio.py    상위 도미넌스 코인 선정과 목표 포트폴리오 계산
  orders.py       현재 포지션과 목표 포지션 비교, 주문 분할
  risk.py         일/주/월 손실 제한
  indicators.py   EMA, ATR, ADX 계산 헬퍼
  binance.py      Binance USDT-M public/user-data REST 어댑터
  models.py       공통 데이터 모델
```

Flutter 관전 전용 앱 방향은 [docs/flutter_app_direction.md](docs/flutter_app_direction.md), 무개입 자동 운영 원칙은 [docs/autonomous_operation.md](docs/autonomous_operation.md), 강화 테스트 방향은 [docs/testing_strategy.md](docs/testing_strategy.md)에 정리했습니다.
TradingView 웹훅 alert 보강안은 [docs/tradingview_alerts.md](docs/tradingview_alerts.md)에 정리했습니다.
Cloudflare webhook receiver 방향과 Worker 골격은 [docs/cloudflare_webhook.md](docs/cloudflare_webhook.md), [workers/tradingview-webhook](workers/tradingview-webhook)에 정리했습니다.
Cloudflare Tunnel로 개인 실행 엔진을 붙이는 방법은 [docs/cloudflare_tunnel.md](docs/cloudflare_tunnel.md)에 정리했습니다.
운영 URL, 4시간봉 기준, 수신 테스트, Flutter 앱 실행법은 [docs/operation_endpoints.md](docs/operation_endpoints.md)에 정리했습니다.

## 점수제 레짐

레짐은 BTC 단독이 아니라 시장 내부 체력을 같이 봅니다.

```text
BTC 방향       40점
TOTAL 방향     25점
TOTAL2/TOTAL3 25점
BTC.D 방향     10점
```

- `BROAD_BULL`: BTC, TOTAL, TOTAL2/TOTAL3 상승 + BTC.D 하락/횡보
- `BTC_ONLY_BULL`: BTC와 TOTAL은 강하지만 TOTAL2/TOTAL3가 약하고 BTC.D 상승
- `BROAD_BEAR`: BTC, TOTAL, TOTAL2/TOTAL3 동반 하락
- `ALT_WEAK_BEAR`: BTC/TOTAL 하락 + TOTAL2/TOTAL3 더 약함 + BTC.D 상승
- `RANGE`: 점수가 애매하거나 내부 지표가 엇갈림
- `CHAOTIC`: 급변동, ATR/거래량 급증, 펀딩 과열

고레벨 매매 상태는 기존처럼 `BULL`, `BEAR`, `RANGE`, `CHAOTIC` 네 가지를 유지하고, 세부 시장 성격은 `market_bias`로 분리합니다. 그래서 `BULL`이어도 `BTC_ONLY_BULL`이면 BTC/ETH 위주 1배 롱으로 축소하고, `BROAD_BULL`일 때만 상위 10개 롱 1.5~2배를 허용합니다.

## Binance 키

API 키는 파일에 직접 넣지 않습니다. 환경변수로만 주입하세요.

```bash
export BINANCE_API_KEY="..."
export BINANCE_API_SECRET="..."
export ENGINE_PORT=8788
```

또는 `.env.example`을 참고해 로컬 `.env`를 만들 수 있습니다. `.env`는 `.gitignore`에 포함되어 있습니다.

Binance 어댑터는 USDT-M 선물의 계좌, 포지션, BTC 캔들, 선물 후보군, 호가 스프레드, 주문 실행 파라미터를 가져옵니다. TradingView의 `TOTAL`, `TOTAL2`, `TOTAL3`, `BTC.D`는 Binance USDT-M 원천 데이터가 아니므로 `CryptoMarketSnapshot`에 별도 인덱스 데이터로 넣어야 합니다.

상위 도미넌스 10개 선정은 현재 Binance USDT-M 24시간 quote volume 기반 점유율로 동작합니다. Binance 선물 API는 시가총액 도미넌스를 직접 제공하지 않기 때문에, 시총 기준 도미넌스를 엄밀히 보려면 CoinGecko/CMC/TradingView 같은 외부 데이터로 `MarketCandidate.dominance_rank` 또는 `dominance_pct`를 보강하면 됩니다. `USDT`, `USDC`, `DAI` 등 스테이블코인은 유니버스에서 제외됩니다.

## 로컬 상태 API

Cloudflare Tunnel의 `engine.medicalnewshub.info`는 이 PC의 `127.0.0.1:8788`을 바라봅니다. 앱은 기본적으로 `/status`를 읽습니다.

```bash
PYTHONPATH=src python -m rebalancing.status_server
curl http://127.0.0.1:8788/status
curl https://engine.medicalnewshub.info/status
```

응답에는 앱이 바로 읽는 `watchlist`, `positions`, `orders`, `events`, `equity`, `regime`, `mode`, `risk_state`가 포함됩니다.

맥북에서 버튼으로 서버를 켜고 끄려면 아래 파일을 더블클릭하세요.

```text
tools/server_control_gui.command
```

이 GUI는 기본적으로 3,300 USDT 가상 계좌, 실주문 비활성화 상태로 `status_server`를 실행합니다. 버튼은 `Start Server`, `Stop Server`, `Restart Server`, `Open Status`, `Open Log`, `Refresh`를 제공합니다.

## Market Internal Engine

TradingView는 EMA/TOTAL/BTC.D 기반 시그널 계산기로 두고, 서버는 시장 내부 데이터를 계산합니다.

서버 계산 항목:

- `stable_dominance_pct`: USDT, USDC, DAI, FDUSD, TUSD, USDE 등 스테이블 시총 / 전체 시총
- `top10_dominance_total_pct`: 스테이블 제외 시총 상위 10개 / 전체 시총
- `top10_dominance_total2_pct`: 스테이블 제외 시총 상위 10개 / BTC 제외 시총
- `volume_breadth_pct`: Binance USDT-M 상위 유니버스 중 현재 거래량이 20EMA 거래량보다 큰 비율
- `advance_decline_ratio`: 상승 코인 수 / 하락 코인 수

`/status`의 `market_internals`와 `watchlist`에 같이 노출됩니다. CoinGecko가 응답하면 시총 기준 top10이 포트폴리오 후보군의 `dominance_rank`에 반영되고, CoinGecko가 막히면 Binance 거래대금 기반 점유율로 fallback합니다.

```bash
export COINGECKO_API_KEY="optional_demo_or_pro_key"
export MARKET_INTERNALS_UNIVERSE_LIMIT=200
export MARKET_INTERNALS_BREADTH_LIMIT=100
```

## 주문 실행

주문 실행은 기본적으로 드라이런입니다. 실주문은 코드와 환경변수 양쪽에서 이중 잠금이 걸려 있습니다.

```bash
PYTHONPATH=src python -m rebalancing.execution

export BINANCE_LIVE_TRADING=true
export BINANCE_ENABLE_ORDERS=true
PYTHONPATH=src python -m rebalancing.execution --live
```

실주문 전에는 Binance API 키를 새로 발급하고, 먼저 드라이런 응답의 `execution_results.response.params`를 확인하세요.

## 테스트

```bash
PYTHONPATH=src python -m unittest discover -s tests
PYTHONPATH=src python -m rebalancing.backtest --iterations 500
```

## 사용 예시

```python
from datetime import datetime, timezone

from rebalancing import (
    AccountSnapshot,
    BtcMarketSnapshot,
    CryptoMarketSnapshot,
    EngineState,
    MarketCandidate,
    MarketIndexSnapshot,
    Position,
    PositionSide,
    RebalancingEngine,
)

engine = RebalancingEngine()
state = EngineState()

decision = engine.evaluate(
    now=datetime.now(timezone.utc),
    state=state,
    account=AccountSnapshot(
        equity=1000,
        wallet_balance=1000,
        day_start_equity=1000,
        week_start_equity=1000,
        month_start_equity=1000,
    ),
    market=CryptoMarketSnapshot(
        btc=BtcMarketSnapshot(
            close_1d=70000,
            ema20_1d=68000,
            ema60_1d=65000,
            ema200_1d=50000,
            ema20_4h=70500,
            ema60_4h=69000,
            adx_1d=24,
        ),
        total=MarketIndexSnapshot("TOTAL", close_1d=120, ema20_1d=115, ema60_1d=100, ema200_1d=90),
        total2=MarketIndexSnapshot("TOTAL2", close_1d=110, ema20_1d=105, ema60_1d=95, ema200_1d=80),
        total3=MarketIndexSnapshot("TOTAL3", close_1d=105, ema20_1d=102, ema60_1d=90, ema200_1d=75),
        btc_dominance=MarketIndexSnapshot("BTC.D", close_1d=52, ema20_1d=51, ema60_1d=54),
    ),
    candidates=[
        MarketCandidate("BTCUSDT", "BTC", quote_volume_24h=10_000_000_000, listed_days=3000, market_cap_rank=1),
        MarketCandidate("ETHUSDT", "ETH", quote_volume_24h=5_000_000_000, listed_days=3000, market_cap_rank=2),
    ],
    positions=[],
)

print(decision.regime, decision.market_bias, decision.regime_score, decision.mode, decision.orders)
state = decision.next_state
```

실거래 전에는 반드시 백테스트, 페이퍼 트레이딩, 최소 금액 테스트로 임계값을 검증해야 합니다.
