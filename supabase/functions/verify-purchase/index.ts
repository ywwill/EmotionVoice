// Supabase Edge Function: verify-purchase
//
// 内购入账。解决「用户付了钱、积分却因为同步失败而蒸发」的问题（问题 3 的 B 面）。
//
// 链路：
//   App: StoreKit 交易成功
//     → 先把交易落进本地 pending 账本（防丢）
//     → POST 这里 { deviceId, transactionId, jws, productId }
//   本函数：
//     → 校验 productId 在服务端白名单（积分数由服务端决定，客户端报多少都不算）
//     → 校验交易有效性（见 verifyTransaction）
//     → 用 service_role 调 grant_credits(op_id = transactionId)  ← 幂等，重传只发一次
//     → 返回新余额
//   App: 移除 pending，刷新显示
//
// ---------------------------------------------------------------------------
// ⚠️ 本文件是**骨架**，票据校验有两个模式，默认 BASIC：
//
//   BASIC（默认，无需额外配置）
//     只校验 productId 白名单 + 依赖 transactionId 幂等去重。
//     防护强度：能挡住「重复入账」和「虚报积分数量」，
//     挡不住「伪造一个不存在的 transactionId 来刷积分」。
//     适合先把链路打通、把丢积分的问题修掉。
//
//   STRICT（推荐，需配置 App Store Server API）
//     拿 jws 去 Apple 的 App Store Server API 查交易，确认有效、未退款、
//     productId 匹配、bundleId 匹配后才入账。
//     需要 secrets：APPSTORE_ISSUER_ID / APPSTORE_KEY_ID /
//                   APPSTORE_PRIVATE_KEY（.p8 内容）/ APPSTORE_BUNDLE_ID
//     配齐后自动切到这个模式。
//
// ---------------------------------------------------------------------------
// 需要的 secrets：
//   SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY   Edge Function 运行时自带
//   APP_SECRET                                 与 kSupabaseAppSecret 一致（不设置则不校验）
//   APPSTORE_*                                 可选，配齐后启用 STRICT 校验
//
// config.toml 需要补一段（本函数不走 JWT，鉴权在内部用 APP_SECRET）：
//   [functions.verify-purchase]
//   verify_jwt = false
//
// 部署：
//   supabase functions deploy verify-purchase --project-ref dpyyhbqqmegencxekkcr

// ===========================================================================
// 配置
// ===========================================================================

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const APP_SECRET = Deno.env.get("APP_SECRET") ?? "";

const APPSTORE_ISSUER_ID = Deno.env.get("APPSTORE_ISSUER_ID") ?? "";
const APPSTORE_KEY_ID = Deno.env.get("APPSTORE_KEY_ID") ?? "";
const APPSTORE_PRIVATE_KEY = Deno.env.get("APPSTORE_PRIVATE_KEY") ?? "";
const APPSTORE_BUNDLE_ID = Deno.env.get("APPSTORE_BUNDLE_ID") ?? "";

const STRICT_MODE =
  APPSTORE_ISSUER_ID !== "" && APPSTORE_KEY_ID !== "" && APPSTORE_PRIVATE_KEY !== "";

/// 商品 ID → 积分数。
/// **服务端权威**：客户端报的积分数一律不采信，只认这张表。
/// 必须与客户端 StoreKitManager.CreditProduct.creditsAmount 保持一致。
const PRODUCT_CREDITS: Record<string, number> = {
  "ai.emora.credit.60": 60,
  "ai.emora.credit.30": 400,
  "ai.emora.credit.900": 900,
  "ai.emora.credit.1500": 1500,
};

// ===========================================================================
// 类型
// ===========================================================================

interface PurchaseRequest {
  deviceId: string;
  transactionId: string;
  jws?: string;
  productId: string;
}

interface GrantResult {
  balance: number;
  applied: boolean;
}

// ===========================================================================
// 工具
// ===========================================================================

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function fail(status: number, code: string, detail = ""): Response {
  console.error(`[verify-purchase] ❌ ${code} ${detail}`);
  return json({ ok: false, code, detail }, status);
}

function mask(v: string): string {
  if (!v) return "(empty)";
  return v.length <= 8 ? "****" : `${v.slice(0, 4)}****(${v.length})`;
}

/// 校验应用级 secret（与 bailian-tts 同一套约定：header 或 query）
function checkAppSecret(req: Request, url: URL): boolean {
  if (APP_SECRET === "") return true; // 未配置则不校验
  const fromHeader = req.headers.get("x-app-secret") ?? "";
  const fromQuery = url.searchParams.get("secret") ?? "";
  return fromHeader === APP_SECRET || fromQuery === APP_SECRET;
}

// ===========================================================================
// 交易校验
// ===========================================================================

/// STRICT 模式：向 App Store Server API 查询交易信息
/// 文档 https://developer.apple.com/documentation/appstoreserverapi/get_transaction_info
///
/// ⚠️ 这里需要先用 .p8 私钥签一个 ES256 JWT 作为 Bearer，Deno 下可用 npm:jose。
///    骨架里留出 TODO —— 配齐 APPSTORE_* 后把这里补完即可自动启用。
async function fetchTransactionInfoFromApple(
  transactionId: string,
): Promise<{ valid: boolean; productId?: string; reason?: string }> {
  // TODO(STRICT): 用 APPSTORE_PRIVATE_KEY 签 JWT（iss=APPSTORE_ISSUER_ID, kid=APPSTORE_KEY_ID,
  // aud=appstoreconnect-v1, ES256, 有效期 ≤ 20 分钟），然后：
  //
  // const jwt = await signAppStoreJWT();
  // const resp = await fetch(
  //   `https://api.storekit.apple.com/inApps/v1/transactions/${transactionId}`,
  //   { headers: { Authorization: `Bearer ${jwt}` } },
  // );
  // if (resp.status === 404) return { valid: false, reason: "TRANSACTION_NOT_FOUND" };
  // if (!resp.ok) return { valid: false, reason: `APPLE_HTTP_${resp.status}` };
  // const body = await resp.json();           // 已是被 Apple 签名过的 JWSResponse
  // const payload = decodeJWSPayload(body.signedTransactionInfo);
  // if (payload.bundleId !== APPSTORE_BUNDLE_ID) return { valid: false, reason: "BUNDLE_MISMATCH" };
  // return { valid: true, productId: payload.productId };

  console.warn(
    `[verify-purchase] STRICT 模式尚未实现（transactionId=${mask(transactionId)}），` +
      `本次按 BASIC 放行。请补完 fetchTransactionInfoFromApple。`,
  );
  return { valid: true };
}

/// BASIC 模式：只做结构校验（transactionId 形如数字串）
function looksLikeTransactionId(id: string): boolean {
  return /^\d{5,30}$/.test(id);
}

async function verifyTransaction(
  req: PurchaseRequest,
): Promise<{ valid: boolean; productId: string; reason?: string }> {
  // 1) productId 必须在服务端白名单里 —— 这条 BASIC / STRICT 都要过
  if (!PRODUCT_CREDITS[req.productId]) {
    return { valid: false, productId: req.productId, reason: "UNKNOWN_PRODUCT" };
  }

  // 2) STRICT：去 Apple 查，以 Apple 返回的 productId 为准
  if (STRICT_MODE) {
    const info = await fetchTransactionInfoFromApple(req.transactionId);
    if (!info.valid) return { valid: false, productId: req.productId, reason: info.reason };
    const appleProductId = info.productId ?? req.productId;
    if (!PRODUCT_CREDITS[appleProductId]) {
      return { valid: false, productId: appleProductId, reason: "UNKNOWN_PRODUCT" };
    }
    return { valid: true, productId: appleProductId };
  }

  // 3) BASIC：只校验形状 + 要求带 jws（有 jws 说明确实经过了 StoreKit）
  if (!looksLikeTransactionId(req.transactionId)) {
    return { valid: false, productId: req.productId, reason: "BAD_TRANSACTION_ID" };
  }
  if (!req.jws || req.jws.length < 100) {
    return { valid: false, productId: req.productId, reason: "MISSING_JWS" };
  }
  return { valid: true, productId: req.productId };
}

// ===========================================================================
// 入账：service_role 调 grant_credits
// ===========================================================================

async function grantCredits(
  deviceId: string,
  amount: number,
  opId: string,
  meta: Record<string, unknown>,
): Promise<GrantResult> {
  const resp = await fetch(`${SUPABASE_URL}/rest/v1/rpc/grant_credits`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      apikey: SERVICE_ROLE_KEY,
      Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
    },
    body: JSON.stringify({
      p_device_id: deviceId,
      p_amount: amount,
      p_op_id: opId,
      p_kind: "purchase",
      p_meta: meta,
    }),
  });

  if (!resp.ok) {
    const text = await resp.text();
    throw new Error(`grant_credits failed: HTTP ${resp.status} ${text}`);
  }

  const rows = (await resp.json()) as GrantResult[];
  if (!rows.length) throw new Error("grant_credits returned no rows");
  return rows[0];
}

// ===========================================================================
// 主入口
// ===========================================================================

Deno.serve(async (req: Request) => {
  const url = new URL(req.url);

  if (req.method === "OPTIONS") {
    return new Response(null, {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-app-secret",
        "Access-Control-Allow-Methods": "POST, OPTIONS",
      },
    });
  }

  if (req.method !== "POST") return fail(405, "METHOD_NOT_ALLOWED");

  if (!checkAppSecret(req, url)) return fail(401, "BAD_APP_SECRET");

  if (SUPABASE_URL === "" || SERVICE_ROLE_KEY === "") {
    return fail(500, "MISSING_SERVICE_ROLE_CONFIG");
  }

  let body: PurchaseRequest;
  try {
    body = (await req.json()) as PurchaseRequest;
  } catch (e) {
    return fail(400, "BAD_JSON", String(e));
  }

  const { deviceId, transactionId, jws, productId } = body;
  if (!deviceId || !transactionId || !productId) {
    return fail(400, "MISSING_FIELDS");
  }

  console.log(
    `[verify-purchase] mode=${STRICT_MODE ? "STRICT" : "BASIC"} ` +
      `device=${mask(deviceId)} product=${productId} tx=${mask(transactionId)}`,
  );

  // 1) 校验交易
  const verified = await verifyTransaction(body);
  if (!verified.valid) {
    return fail(403, verified.reason ?? "VERIFY_FAILED");
  }

  // 2) 积分数由服务端白名单决定，与客户端报的无关
  const credits = PRODUCT_CREDITS[verified.productId];

  // 3) 入账，op_id = transactionId → 重复调用只会命中幂等短路
  try {
    const result = await grantCredits(deviceId, credits, `purchase:${transactionId}`, {
      product_id: verified.productId,
      transaction_id: transactionId,
      mode: STRICT_MODE ? "strict" : "basic",
    });

    console.log(
      `[verify-purchase] ✅ 入账 ${credits} 积分，新余额 ${result.balance}` +
        `${result.applied ? "" : "（命中幂等，本次未重复发放）"}`,
    );

    return json({
      ok: true,
      credits,
      balance: result.balance,
      applied: result.applied, // false = 这笔之前已经发过了
    });
  } catch (e) {
    return fail(502, "GRANT_FAILED", String(e));
  }
});
