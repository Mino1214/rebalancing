# Flutter Personal App Direction

민오 앱은 매매 버튼 많은 트레이딩 앱보다, 자동 자산배분 엔진을 관제하고 승인하는 개인용 콘솔로 시작하는 게 좋습니다.

## 권장 구조

```text
Flutter App
-> Dashboard / Settings / Backtest / Paper / Live Monitor
-> Local or private backend API
-> Rebalancing Engine
-> Exchange adapter
```

앱 안에 Binance API secret을 직접 넣는 구조는 피합니다. 모바일 앱은 분실, 백업, 로그, 디컴파일 위험이 있어서 키 보관에 약합니다. 개인용이라도 키는 로컬 Mac, NAS, VPS 같은 실행 환경의 환경변수나 secret manager에 두고, Flutter는 결과 조회와 설정 변경만 담당하게 둡니다.

## MVP 화면

1. Dashboard
   - 총자산, 현재 노출, 사용 레버리지
   - 현재 레짐: `BULL / BEAR / RANGE / CHAOTIC`
   - 세부 바이어스: `BROAD_BULL / BTC_ONLY_BULL / BROAD_BEAR / ALT_WEAK_BEAR`
   - 레짐 점수, BTC/TOTAL/TOTAL2/TOTAL3/BTC.D 방향

2. Portfolio
   - 현재 포지션
   - 목표 포지션
   - 차이와 주문 계획
   - reduce-only 여부, 분할 주문 개수

3. Universe
   - 상위 도미넌스 10 코인
   - 스테이블코인 제외 결과
   - 거래량, 스프레드, 상장 기간 필터 통과 여부

4. Risk
   - 일/주/월 손실률
   - 신규 진입 차단 여부
   - 쿨다운 종료 시각

5. Backtest / Paper
   - 기간 선택
   - 레짐별 손익
   - 최대 낙폭
   - 회전율과 수수료/슬리피지

6. Settings
   - 최대 레버리지
   - 레짐 점수 임계값
   - 리밸런싱 주기
   - 손실 제한
   - 실거래 모드 잠금

## 단계별 개발

1. Flutter read-only dashboard
   - 엔진 결과 JSON을 읽어서 보여주기만 합니다.

2. Paper mode
   - 주문을 거래소로 보내지 않고 체결 시뮬레이션만 합니다.

3. Approval mode
   - 엔진이 주문 계획을 만들고, 앱에서 승인해야 실행됩니다.

4. Small live mode
   - 매우 작은 금액과 낮은 노출로만 시작합니다.

5. Autonomous mode
   - 충분한 백테스트와 페이퍼 로그가 쌓인 뒤에만 켭니다.

## Flutter 상태 관리

처음에는 `Riverpod` 기반이 적당합니다.

- `engineStatusProvider`: 레짐, 점수, 바이어스
- `portfolioProvider`: 현재/목표 포지션
- `ordersProvider`: 계획 주문
- `riskProvider`: 손실 제한과 쿨다운
- `settingsProvider`: 로컬 설정

차트는 MVP에서는 단순 라인/바 차트로 충분하고, 고급 차트는 나중에 붙입니다.

