/**
 * PDFMathTranslate 共享翻译 Key 代理（Cloudflare Worker，免费额度 10 万请求/天）
 *
 * 作用：把「真实厂商 API Key」留在服务端，客户端只拿到一个访问令牌。
 *
 *   客户端  ── base_url = https://<worker>，api_key = ACCESS_TOKEN ──▶  本 Worker
 *   本 Worker ── 注入真实 UPSTREAM_API_KEY ──▶  上游 OpenAI 兼容服务
 *
 * 环境变量（在 Cloudflare 控制台或 `wrangler secret put` 设置，勿写入代码）：
 *   UPSTREAM_BASE_URL  上游地址根（如 https://api.siliconflow.cn，可含 /v1）
 *   UPSTREAM_API_KEY   真实厂商 key
 *   ACCESS_TOKEN       客户端使用的访问令牌（留空则不校验，仅建议本地测试时）
 *   DAILY_LIMIT        可选，每日请求上限（需绑定 KV：RATE_LIMIT）
 *
 * 部署见同目录 README.md。
 */

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    // 0) 健康检查
    if (url.pathname === "/healthz") {
      return json({ ok: true, upstream: Boolean(env.UPSTREAM_BASE_URL) }, 200);
    }

    // 1) 访问令牌校验（客户端 Authorization: Bearer <ACCESS_TOKEN>）
    if (env.ACCESS_TOKEN) {
      const provided = (request.headers.get("Authorization") || "")
        .replace(/^Bearer\s+/i, "")
        .trim();
      if (provided !== env.ACCESS_TOKEN) {
        return json(
          { error: { message: "invalid access token", type: "invalid_request_error" } },
          401,
        );
      }
    }

    // 2) 可选：每日限额（绑定 KV 后生效）
    if (env.RATE_LIMIT && env.DAILY_LIMIT) {
      const day = new Date().toISOString().slice(0, 10);
      const key = `usage:${day}`;
      const used = Number.parseInt((await env.RATE_LIMIT.get(key)) || "0", 10);
      const limit = Number.parseInt(env.DAILY_LIMIT, 10);
      if (Number.isFinite(limit) && used >= limit) {
        return json(
          { error: { message: "daily quota exceeded", type: "rate_limit_error" } },
          429,
        );
      }
      await env.RATE_LIMIT.put(key, String(used + 1), { expirationTtl: 172800 });
    }

    // 3) 转发到上游（OpenAI 兼容，路径原样透传）
    const upstream = (env.UPSTREAM_BASE_URL || "").trim().replace(/\/+$/, "");
    if (!upstream) {
      return json({ error: { message: "UPSTREAM_BASE_URL not configured" } }, 500);
    }

    let path = url.pathname + url.search;
    // 上游已带 /v1 时避免出现 /v1/v1
    if (/\/v1$/.test(upstream) && path.startsWith("/v1/")) {
      path = path.slice(3);
    }

    const headers = new Headers(request.headers);
    headers.set("Authorization", `Bearer ${env.UPSTREAM_API_KEY || ""}`);
    headers.delete("Host");
    headers.delete("CF-Connecting-IP");
    headers.delete("CF-IPCountry");
    headers.delete("Content-Length");

    const hasBody = !["GET", "HEAD"].includes(request.method);
    const upstreamResponse = await fetch(upstream + path, {
      method: request.method,
      headers,
      body: hasBody ? request.body : undefined,
      redirect: "follow",
    });

    // 4) 原样返回（含流式响应）
    const outHeaders = new Headers(upstreamResponse.headers);
    outHeaders.delete("Content-Length");
    outHeaders.delete("Content-Encoding"); // 交由运行时重新处理压缩
    outHeaders.set("X-Proxy", "pdf2zh-key-proxy");
    return new Response(upstreamResponse.body, {
      status: upstreamResponse.status,
      headers: outHeaders,
    });
  },
};

function json(body, status) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8" },
  });
}
