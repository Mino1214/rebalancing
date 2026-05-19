# Flutter Observer App Direction

민오 앱은 조종석이 아니라 계기판입니다. 수동 진입, 주문 승인, 포지션 조정 버튼을 두지 않고 자동 자산배분 엔진의 상태만 관전합니다.

## 권장 구조

```text
Flutter App
-> Read-only Dashboard / Portfolio / Risk / Logs / Backtest
-> Read-only private backend API
-> Rebalancing Engine
-> Exchange adapter
```

앱 안에 Binance API secret을 직접 넣는 구조는 피합니다. 모바일 앱은 분실, 백업, 로그, 디컴파일 위험이 있어서 키 보관에 약합니다. 개인용이라도 키는 로컬 Mac, NAS, VPS 같은 실행 환경의 환경변수나 secret manager에 두고, Flutter는 결과 조회만 담당합니다.

설정 변경도 앱에서 하지 않는 것을 기본값으로 둡니다. 운영자가 할 수 있는 개입은 코드와 서버 설정 수정뿐입니다.

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
   - 최근 체결과 미체결 주문
   - reduce-only 여부, 분할 주문 개수

3. Universe
   - 상위 도미넌스 10 코인
   - 스테이블코인 제외 결과
   - 거래량, 스프레드, 상장 기간 필터 통과 여부

4. Risk
   - 일/주/월 손실률
   - 신규 진입 차단 여부
   - 쿨다운 종료 시각
   - 자동 정지 사유

5. Backtest / Paper
   - 저장된 백테스트 결과
   - 저장된 paper run 결과
   - 레짐별 손익
   - 최대 낙폭
   - 회전율과 수수료/슬리피지

6. Logs
   - TradingView alert 수신
   - 레짐 변경
   - 주문 계획 생성
   - 주문 실행 결과
   - 리스크 제한 발동
   - API 오류

## 단계별 개발

1. Flutter read-only dashboard
   - 엔진 결과 JSON을 읽어서 보여주기만 합니다.

2. Paper mode
   - 주문을 거래소로 보내지 않고 체결 시뮬레이션만 합니다.

3. Small autonomous live mode
   - 매우 작은 금액과 낮은 노출로만 시작합니다.
   - 앱 승인 없이 엔진이 자동 실행합니다.

4. Full autonomous mode
   - 충분한 백테스트와 페이퍼 로그가 쌓인 뒤에만 켭니다.
   - 앱은 관전과 알림 확인만 담당합니다.

## Flutter 상태 관리

처음에는 `Riverpod` 기반이 적당합니다.

- `engineStatusProvider`: 레짐, 점수, 바이어스
- `portfolioProvider`: 현재/목표 포지션
- `ordersProvider`: 계획 주문
- `riskProvider`: 손실 제한과 쿨다운
- `logsProvider`: alert, 주문, 오류 로그

`settingsProvider`는 앱 MVP에서 제외합니다. 설정은 서버의 환경변수, 설정 파일, 배포 파이프라인으로만 변경합니다.

차트는 MVP에서는 단순 라인/바 차트로 충분하고, 고급 차트는 나중에 붙입니다.

## 앱에 두지 않을 것

- 수동 매수/매도 버튼
- 포지션 직접 수정 버튼
- 주문 승인 버튼
- 레버리지 즉시 변경 버튼
- live/paper 즉시 전환 버튼

무개입 자동화를 전제로 하면 사람 손이 들어갈 수 있는 UI가 오히려 시스템의 일관성을 깨뜨립니다. 앱은 “왜 지금 이 상태인지”를 보여주는 데 집중합니다.
