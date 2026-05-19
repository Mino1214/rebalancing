# TradingView Alerts

TradingView는 레짐 신호를 만들고, 실행 엔진은 그 신호를 검증한 뒤 리스크/전환/포지션 로직을 적용하는 구조가 좋습니다.

## 꼭 보강할 점

1. EMA는 `request.security()` 안에서 계산합니다.
   - `close`만 가져와서 바깥에서 `ta.ema()`를 계산하면 차트 타임프레임이 `tf`와 다를 때 값이 왜곡될 수 있습니다.

2. JSON에는 스키마와 식별자를 넣습니다.
   - `schema`, `source`, `tf`, `bar_time_ms`, `signal_id`

3. 시간은 문자열보다 숫자 밀리초가 좋습니다.
   - `time_ms`: alert 생성 시각
   - `bar_time_ms`: 신호 캔들 마감 시각

4. 중복과 지연은 수신 서버에서 막습니다.
   - `signal_id` 기준 dedupe
   - 예: 5분 이상 지난 alert는 폐기

5. `CHAOTIC`을 TradingView 단계에서도 먼저 걸러냅니다.
   - 급변동일 때 롱/숏 신호보다 정지 신호가 우선입니다.

6. 웹훅 passphrase를 넣습니다.
   - 완벽한 보안은 아니지만, 임의 요청을 1차로 걸러낼 수 있습니다.

## 권장 Pine v5 예시

운영할 때는 차트 타임프레임을 `Signal Timeframe`과 같게 맞추는 것을 권장합니다.

```pine
//@version=5
indicator("Crypto Regime Engine", overlay=false)

// === Inputs ===
btcSymbol    = input.symbol("BINANCE:BTCUSDT", "BTC")
totalSymbol  = input.symbol("CRYPTOCAP:TOTAL", "TOTAL")
total2Symbol = input.symbol("CRYPTOCAP:TOTAL2", "TOTAL2")
total3Symbol = input.symbol("CRYPTOCAP:TOTAL3", "TOTAL3")
btcdSymbol   = input.symbol("CRYPTOCAP:BTC.D", "BTC Dominance")

tf = input.timeframe("240", "Signal Timeframe")
confirmBars = input.int(3, "Confirm Bars", minval=1)
chaoticPct = input.float(6.0, "BTC 4H Chaotic Change %", minval=0.1)
maxLeverage = input.float(2.0, "Max Leverage", minval=0.0, maxval=2.0)
passphrase = input.string("", "Webhook Passphrase")

// === HTF data. Indicators are calculated inside request.security. ===
btcClose = request.security(btcSymbol, tf, close, barmerge.gaps_off, barmerge.lookahead_off)
btcPrevClose = request.security(btcSymbol, tf, close[1], barmerge.gaps_off, barmerge.lookahead_off)
btcEma20 = request.security(btcSymbol, tf, ta.ema(close, 20), barmerge.gaps_off, barmerge.lookahead_off)
btcEma60 = request.security(btcSymbol, tf, ta.ema(close, 60), barmerge.gaps_off, barmerge.lookahead_off)

totalEma20 = request.security(totalSymbol, tf, ta.ema(close, 20), barmerge.gaps_off, barmerge.lookahead_off)
totalEma60 = request.security(totalSymbol, tf, ta.ema(close, 60), barmerge.gaps_off, barmerge.lookahead_off)

total2Ema20 = request.security(total2Symbol, tf, ta.ema(close, 20), barmerge.gaps_off, barmerge.lookahead_off)
total2Ema60 = request.security(total2Symbol, tf, ta.ema(close, 60), barmerge.gaps_off, barmerge.lookahead_off)

total3Ema20 = request.security(total3Symbol, tf, ta.ema(close, 20), barmerge.gaps_off, barmerge.lookahead_off)
total3Ema60 = request.security(total3Symbol, tf, ta.ema(close, 60), barmerge.gaps_off, barmerge.lookahead_off)

btcdEma20 = request.security(btcdSymbol, tf, ta.ema(close, 20), barmerge.gaps_off, barmerge.lookahead_off)
btcdEma60 = request.security(btcdSymbol, tf, ta.ema(close, 60), barmerge.gaps_off, barmerge.lookahead_off)
barCloseMs = request.security(btcSymbol, tf, time_close, barmerge.gaps_off, barmerge.lookahead_off)

// === Direction ===
btcUp = btcEma20 > btcEma60
btcDown = btcEma20 < btcEma60
totalUp = totalEma20 > totalEma60
totalDown = totalEma20 < totalEma60
total2Up = total2Ema20 > total2Ema60
total2Down = total2Ema20 < total2Ema60
total3Up = total3Ema20 > total3Ema60
total3Weak = total3Ema20 < total3Ema60
btcdUp = btcdEma20 > btcdEma60
btcdDown = btcdEma20 < btcdEma60

// === Confirmation ===
persist(cond) =>
    ta.barssince(not cond) >= confirmBars - 1

strongLongRaw = btcUp and totalUp and total2Up and total3Up and not btcdUp
btcOnlyLongRaw = btcUp and totalUp and not total2Up and btcdUp
bearModeRaw = btcDown and totalDown and total2Down
altWeakShortRaw = btcDown and total3Weak and btcdUp

strongLong = persist(strongLongRaw)
btcOnlyLong = persist(btcOnlyLongRaw)
bearMode = persist(bearModeRaw)
altWeakShort = persist(altWeakShortRaw)

btcChangePct = btcPrevClose == 0.0 ? 0.0 : (btcClose / btcPrevClose - 1.0) * 100.0
chaotic = math.abs(btcChangePct) >= chaoticPct

score = (btcUp ? 40.0 : btcDown ? -40.0 : 0.0) +
     (totalUp ? 25.0 : totalDown ? -25.0 : 0.0) +
     (total2Up and total3Up ? 25.0 : total2Down and total3Weak ? -25.0 : 0.0) +
     (btcdDown ? 10.0 : btcdUp ? -10.0 : 0.0)

regime = chaotic ? "CHAOTIC" :
     strongLong ? "TOP10_LONG" :
     btcOnlyLong ? "BTC_ETH_LONG" :
     altWeakShort ? "ALT_WEAK_SHORT" :
     bearMode ? "SHORT_MODE" :
     "RANGE"

targetLeverageRaw = regime == "TOP10_LONG" ? 2.0 :
     regime == "BTC_ETH_LONG" ? 1.2 :
     regime == "ALT_WEAK_SHORT" ? 1.0 :
     regime == "SHORT_MODE" ? 0.8 :
     0.0

targetLeverage = math.min(targetLeverageRaw, maxLeverage)
signalId = regime + "_" + tf + "_" + str.tostring(barCloseMs)

json = '{"schema":"crypto_regime_v1",' +
     '"source":"tradingview",' +
     '"passphrase":"' + passphrase + '",' +
     '"regime":"' + regime + '",' +
     '"target_leverage":' + str.tostring(targetLeverage) + ',' +
     '"score":' + str.tostring(score) + ',' +
     '"btc_up":' + str.tostring(btcUp) + ',' +
     '"btc_down":' + str.tostring(btcDown) + ',' +
     '"total_up":' + str.tostring(totalUp) + ',' +
     '"total_down":' + str.tostring(totalDown) + ',' +
     '"total2_up":' + str.tostring(total2Up) + ',' +
     '"total2_down":' + str.tostring(total2Down) + ',' +
     '"total3_up":' + str.tostring(total3Up) + ',' +
     '"total3_weak":' + str.tostring(total3Weak) + ',' +
     '"btcd_up":' + str.tostring(btcdUp) + ',' +
     '"btcd_down":' + str.tostring(btcdDown) + ',' +
     '"tf":"' + tf + '",' +
     '"confirmed":true,' +
     '"time_ms":' + str.tostring(timenow) + ',' +
     '"bar_time_ms":' + str.tostring(barCloseMs) + ',' +
     '"signal_id":"' + signalId + '"}'

newSignalClose = barstate.isconfirmed and not na(barCloseMs[1]) and barCloseMs != barCloseMs[1]
if newSignalClose
    alert(json, alert.freq_once_per_bar_close)

plot(targetLeverage, title="Target Leverage")
plot(score, title="Regime Score")
```

## Python 수신 검증

```python
from datetime import datetime, timezone

from rebalancing import TradingViewAlert, TradingViewAlertGate

gate = TradingViewAlertGate()
alert = TradingViewAlert.parse(request_body)

accepted, errors = gate.accept(
    alert,
    expected_passphrase="local-secret",
    max_leverage=2.0,
    max_age_seconds=300,
    now=datetime.now(timezone.utc),
)

if not accepted:
    raise ValueError(errors)

regime, market_bias = alert.to_regime_bias()
```

