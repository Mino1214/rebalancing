export interface Env {
  TV_WEBHOOK_PASSPHRASE: string;
  TV_ALERT_DEDUPE?: KVNamespace;
  TV_ALERT_QUEUE?: Queue<TradingViewAlert>;
  MAX_ALERT_AGE_SECONDS?: string;
  MAX_LEVERAGE?: string;
}

type Regime =
  | "TOP10_LONG"
  | "BTC_ETH_LONG"
  | "ALT_WEAK_SHORT"
  | "SHORT_MODE"
  | "RANGE"
  | "CHAOTIC";

interface TradingViewAlert {
  schema?: string;
  source?: string;
  passphrase?: string;
  regime: Regime;
  target_leverage: number;
  score?: number;
  btc_up: boolean;
  btc_down?: boolean;
  total_up: boolean;
  total_down?: boolean;
  total2_up: boolean;
  total2_down?: boolean;
  total3_up?: boolean;
  total3_weak: boolean;
  btcd_up: boolean;
  btcd_down?: boolean;
  tf?: string;
  confirmed?: boolean;
  time?: string | number;
  time_ms?: number;
  bar_time_ms?: number;
  signal_id?: string;
}

interface AcceptedAlert extends TradingViewAlert {
  schema: string;
  source: string;
  confirmed: boolean;
  time_ms: number;
  signal_id: string;
  received_at_ms: number;
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    if (request.method !== "POST") {
      return jsonResponse({ ok: false, error: "method_not_allowed" }, 405);
    }

    let payload: TradingViewAlert;
    try {
      payload = await request.json();
    } catch {
      return jsonResponse({ ok: false, error: "invalid_json" }, 400);
    }

    const normalized = normalizeAlert(payload);
    const errors = validateAlert(normalized, env);
    if (errors.length > 0) {
      return jsonResponse({ ok: false, error: "invalid_alert", details: errors }, 400);
    }

    const duplicate = await isDuplicate(normalized, env);
    if (duplicate) {
      return jsonResponse({ ok: true, duplicate: true, signal_id: normalized.signal_id }, 200);
    }

    if (env.TV_ALERT_QUEUE) {
      await env.TV_ALERT_QUEUE.send(normalized);
    }

    return jsonResponse(
      {
        ok: true,
        accepted: true,
        signal_id: normalized.signal_id,
        regime: normalized.regime,
        target_leverage: normalized.target_leverage,
      },
      202,
    );
  },
};

function normalizeAlert(payload: TradingViewAlert): AcceptedAlert {
  const timeMs = Number(payload.time_ms ?? payload.time);
  const schema = payload.schema ?? "crypto_regime_v1";
  const source = payload.source ?? "tradingview";
  const confirmed = payload.confirmed ?? true;
  const signalId =
    payload.signal_id ??
    `${schema}:${payload.tf ?? "unknown"}:${payload.bar_time_ms ?? timeMs}:${payload.regime}`;

  return {
    ...payload,
    schema,
    source,
    confirmed,
    time_ms: timeMs,
    signal_id: signalId,
    received_at_ms: Date.now(),
  };
}

function validateAlert(alert: AcceptedAlert, env: Env): string[] {
  const errors: string[] = [];
  const maxLeverage = Number(env.MAX_LEVERAGE ?? "2");
  const maxAgeSeconds = Number(env.MAX_ALERT_AGE_SECONDS ?? "300");
  const allowedRegimes: Regime[] = [
    "TOP10_LONG",
    "BTC_ETH_LONG",
    "ALT_WEAK_SHORT",
    "SHORT_MODE",
    "RANGE",
    "CHAOTIC",
  ];

  if (alert.schema !== "crypto_regime_v1") errors.push("unsupported_schema");
  if (alert.source !== "tradingview") errors.push("unsupported_source");
  if (alert.passphrase !== env.TV_WEBHOOK_PASSPHRASE) errors.push("invalid_passphrase");
  if (!allowedRegimes.includes(alert.regime)) errors.push("invalid_regime");
  if (!Number.isFinite(alert.target_leverage)) errors.push("invalid_target_leverage");
  if (alert.target_leverage < 0 || alert.target_leverage > maxLeverage) errors.push("leverage_out_of_bounds");
  if (!alert.confirmed) errors.push("unconfirmed_alert");
  if (!Number.isFinite(alert.time_ms)) errors.push("invalid_time_ms");

  const ageSeconds = (Date.now() - alert.time_ms) / 1000;
  if (ageSeconds > maxAgeSeconds) errors.push("stale_alert");
  if (ageSeconds < -60) errors.push("future_alert");

  if (alert.btc_up && alert.btc_down) errors.push("btc_direction_conflict");
  if (alert.total_up && alert.total_down) errors.push("total_direction_conflict");
  if (alert.total2_up && alert.total2_down) errors.push("total2_direction_conflict");
  if (alert.total3_up && alert.total3_weak) errors.push("total3_direction_conflict");
  if (alert.btcd_up && alert.btcd_down) errors.push("btcd_direction_conflict");

  if (alert.regime === "TOP10_LONG" && !(alert.btc_up && alert.total_up && alert.total2_up)) {
    errors.push("top10_long_inconsistent");
  }
  if (alert.regime === "BTC_ETH_LONG" && !(alert.btc_up && alert.total_up && alert.btcd_up)) {
    errors.push("btc_eth_long_inconsistent");
  }
  if (alert.regime === "ALT_WEAK_SHORT" && !(alert.total3_weak && alert.btcd_up)) {
    errors.push("alt_weak_short_inconsistent");
  }

  return errors;
}

async function isDuplicate(alert: AcceptedAlert, env: Env): Promise<boolean> {
  if (!env.TV_ALERT_DEDUPE) return false;

  const key = `tv-alert:${alert.signal_id}`;
  const existing = await env.TV_ALERT_DEDUPE.get(key);
  if (existing) return true;

  await env.TV_ALERT_DEDUPE.put(key, "1", { expirationTtl: 60 * 60 * 24 * 7 });
  return false;
}

function jsonResponse(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
    },
  });
}

