# TradingView Alerts

현재 운영 기본값은 TradingView가 5분마다 알림을 보내되, 서버가 `timeframes` payload 안의 여러 시간축을 함께 보고 최종 레짐/액션을 결정하는 방식입니다.

붙여넣기용 PineScript는 [tradingview_server_decides.pine](tradingview_server_decides.pine)에 있습니다.

## 시간축 역할

- `24h` / `12h`: 큰 방향 필터. 롱만 허용할지, 숏만 허용할지, 관망할지 결정합니다.
- `8h` / `4h`: 실제 레짐 확정. `TOP10_LONG`, `BTC_ETH_LONG`, `ALT_WEAK_SHORT`, `SHORT_MODE`, `RANGE`의 중심 판단입니다.
- `1h`: 진입/축소 타이밍. 상위 방향과 맞으면 `ENTER`, 반대면 `REDUCE`, 애매하면 `HOLD`입니다.
- `5m`: 알림 주기와 빠른 방어 보조. 단독으로 롱/숏 전환을 만들지는 않지만, `1h`가 애매한 상태에서 반대로 꺾이면 `REDUCE`를 냅니다. `btc_fast_bull` / `btc_fast_bear`는 5분 BTC가 EMA9/EMA20, RSI, 30분 고저점 대비 반등/이탈 조건을 동시에 만족할 때 켜지는 조기 경고입니다.

## Payload 계약

기존 top-level 필드는 Worker 검증과 하위 호환을 위해 유지합니다.

```json
{
  "schema": "crypto_regime_v1",
  "source": "tradingview",
  "server_decides": true,
  "regime": "RANGE",
  "target_leverage": 0,
  "tf": "5",
  "bar_time_ms": 1779288900000,
  "signal_id": "MTF_SERVER_DECIDES_5_1779288900000",
  "timeframes": {
    "24h": {"btc_up": true, "total_up": true, "total2_up": true, "btcd_down": true},
    "12h": {"btc_up": true, "total_up": true, "total2_up": true, "btcd_down": true},
    "8h": {"btc_up": true, "total_up": true, "total2_up": true, "btcd_down": true},
    "4h": {"btc_up": true, "total_up": true, "total2_up": true, "btcd_down": true},
    "1h": {"btc_up": true, "total_up": true, "total2_up": true, "btcd_down": true},
    "5m": {"btc_down": true, "btc_fast_bull": false, "btc_fast_bear": true, "total_down": true, "total2_down": true}
  }
}
```

서버 응답과 저장 record에는 `decision_action`이 추가됩니다.

- `ENTER`: 목표 포트폴리오로 진입/리밸런싱
- `HOLD`: 기존 paper 포지션 유지
- `REDUCE`: 기존 paper 포지션 50% 축소
- `EXIT`: 관망/청산

## 운영 메모

- 알림 빈도는 5분이지만 방향 전환은 24h/12h와 8h/4h가 허용해야 합니다.
- 8h/4h가 24h/12h 방향 필터와 정면 충돌하면 `HOLD`가 아니라 `REDUCE`로 먼저 노출을 줄입니다.
- 5분이 반대로 꺾여도 상위 시간축이 유지되면 단독 청산하지 않습니다. 다만 1시간이 애매한 상태에서 `btc_fast_bull` / `btc_fast_bear`가 반대 방향으로 켜지면 빠른 경고로 보고 `REDUCE`합니다.
- 1시간이 상위 방향과 반대로 가면 바로 반대 포지션으로 뒤집지 않고 축소합니다.
