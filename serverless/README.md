# 共享翻译 Key 的零成本方案

目标：**用户开箱即用、你的 API Key 不下发到客户端、不买服务器**。

核心思路：客户端只拿到一个「访问令牌」，真实厂商 Key 留在云端；客户端把 `API Base URL` 指向代理即可（应用已支持 OpenAI 兼容引擎，**无需改翻译核心代码**）。

```
桌面端 ── base_url=代理地址, api_key=访问令牌 ──▶ 代理（持有真实 Key）──▶ OpenAI / SiliconFlow / DeepSeek / 智谱…
```

两种零成本路线，按需选一种：

| 路线 | 是否需要写代码 | Key 存放 | 免费额度 | 适合 |
|---|---|---|---|---|
| **A. Cloudflare AI Gateway** | ❌ 不用（纯控制台配置） | Cloudflare 托管 | 有免费额度 | 只有自己/小圈子用，最省事 |
| **B. 自建 Worker 代理**（本目录） | ✅ 已写好 `worker.js` | Worker 环境变量（加密） | 10 万请求/天 | 需要自定义限流、多上游、吊销 |

---

## 路线 A：Cloudflare AI Gateway（推荐，零代码）

1. 注册 Cloudflare（免费）→ 控制台左侧 **AI → AI Gateway** → **Create Gateway**，起个名字（如 `pdf2zh`）
2. 进入该 Gateway → **Provider Keys / Add Provider**，选择你的厂商（OpenAI / SiliconFlow / 自定义 OpenAI 兼容），填入**真实 Key**（存在 Cloudflare，不下发）
3. 复制 Gateway 的端点地址，形如：
   ```
   https://gateway.ai.cloudflare.com/v1/<account_id>/<gateway_name>/openai
   ```
4. 在 Gateway 设置里开启 **Authenticated Gateway**，生成一个令牌（这就是给客户端用的「访问令牌」）
5. 可选：开启 **Rate limiting**（限流）、**Caching**（缓存，重复内容省钱）

> 兼容非内置厂商：选 “Custom Provider / OpenAI Compatible”，填你的上游 Base URL。

## 路线 B：自建 Worker 代理（本目录）

### 控制台方式（不需要 Node/wrangler）

1. Cloudflare 控制台 → **Workers & Pages → Create → Worker**，命名如 `pdf2zh-key-proxy`
2. 把 [`cloudflare-worker/worker.js`](cloudflare-worker/worker.js) 全文粘贴进编辑器 → **Deploy**
3. **Settings → Variables and Secrets** 添加（Secret 类型）：
   | 变量 | 说明 | 示例 |
   |---|---|---|
   | `UPSTREAM_BASE_URL` | 上游地址根（可含 `/v1`） | `https://api.siliconflow.cn` |
   | `UPSTREAM_API_KEY` | 真实厂商 Key | `sk-xxxx` |
   | `ACCESS_TOKEN` | 客户端用的访问令牌（自己定一个长随机串） | `p2z_9f3a…` |
   | `DAILY_LIMIT` | 可选，每日上限（需绑定 KV） | `2000` |
4. 记下 Worker 地址：`https://pdf2zh-key-proxy.<你的子域>.workers.dev`

### 命令行方式（有 Node 环境时）

```bash
cd serverless/cloudflare-worker
npm i -g wrangler
wrangler login
wrangler secret put UPSTREAM_API_KEY     # 粘贴真实 Key
wrangler secret put ACCESS_TOKEN         # 粘贴自定访问令牌
wrangler deploy
```

> `.dev.vars`（本地调试用）已在 `.gitignore` 中排除，切勿提交任何真实 Key。

## 客户端配置（两种路线通用）

应用 → **设置**：

| 字段 | 填写 |
|---|---|
| 翻译服务 | `OpenAICompatible` |
| API Base URL | 路线 A 的 Gateway 端点，或路线 B 的 Worker 地址（**不要**再加 `/v1`，Worker 会透传） |
| 模型 | 上游模型名，如 `Qwen/Qwen2.5-7B-Instruct`、`glm-4-flash`、`gpt-4o-mini` |
| API Key | 访问令牌（路线 A 的 Gateway Token / 路线 B 的 `ACCESS_TOKEN`） |

其余（QPS、并发线程、提示词等）按需调整。

## 验证

```bash
# 健康检查（路线 B）
curl https://<worker>.workers.dev/healthz

# 模拟一次对话请求
curl https://<worker>.workers.dev/v1/chat/completions \
  -H "Authorization: Bearer <ACCESS_TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{"model":"<模型>","messages":[{"role":"user","content":"hi"}]}'
```

## 安全与成本

- 真实 Key **只存在云端**（Cloudflare 加密变量），仓库里只有代理代码，公开无风险
- 访问令牌泄露时可随时更换（改一个变量重新部署即可）
- 免费额度：Worker 10 万请求/天；一篇文章翻译通常几百次请求 → 日常自用绰绰有余
- 建议开启每日限额 + 缓存，避免被刷量或重复内容浪费额度
- 若上游本身有免费模型（如 `glm-4-flash`、Qwen 免费额度、SiliconFlow 免费模型），整体成本为 0

## 备选：完全不做代理

项目已内置 **SiliconFlowFree**（免费翻译服务），设置里选它即可，零配置零成本——只是共享池速度/稳定性受上游影响。若你只是想「自己用、不配 Key」，这条路最省事。
