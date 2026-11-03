# 桌面端 API 与数据契约（v1.2，P0 定义，P1 实现最小子集）

日期：2026-09-28。权威背景：`docs/NATIVE_DESKTOP_OPTIMIZATION_PLAN_2026-09-28.md`（下称"方案"）。
本文只定义**必须遵守的接口与数据契约**，不重复方案论述。标注【新增】的为现有后端没有的能力，标注【保留】的为现有语义不变。

修订记录：
- v1（2026-09-28 上午）：初稿。
- v1.1（2026-09-28，P0 整改轮）：按 `docs/reviews/native-desktop/P0-CODEX-review-2026-09-28.md` R3/R4/R5 修订——就绪三态拆分与 stdout 降级定位（§1）；create+retry 幂等语义完整化（§3）；SSE wire 格式/水位/重放/溢出/竞态测试清单（§4）；资源档位与目录所有权的 P1/P2 实现归属（§5/§6）；环境变量边界澄清（§6）；导出回执改为内容身份校验、允许合法改名（§7）；鉴权传递格式与旧入口兼容（§8）。
- v1.2（2026-09-28，P0 收尾轮）：按 `docs/reviews/native-desktop/P0-CODEX-remediation-final-review-2026-09-28.md` F1/F5 修订——§7 清理校验对象改为 saved_path 最终文件（可读+size+SHA256 对稳定产物身份）、暂存保留条件、不可变载荷五元组、5 个验收案例；§3 清历史与 TTL 去重解耦（tombstone）、retry 键作用域与原任务身份；§4 冻结唯一事件信封（id: `<instance_id>:<event_id>`）与初连/同实例重放/游标过期/实例重启四条唯一流程；EventSource ticket 用后重新取票。

## 1. 应用就绪状态机【新增】

```
window_ready ──> control_api_starting ──> api_ready ──> config_loaded ──> assets_checking ──> ready
                        │                                            │
                        └── control_failed（可重试）                  └── assets_missing / downloading / verifying / failed_retryable
```

- **就绪是三个独立信号，不得合并或声称等价**（P0 审核教训 R3）：
  1. `window_ready`：主窗口可交互（WPF 计时，含首帧渲染完成）；
  2. `api_ready`：`GET /api/health` 返回 200（唯一的 API 就绪判定；仅接受 200）；
  3. `assets_ready`：资源校验/下载完成（见 `/api/assets/status`）。
- 后端 stdout 的 `WebUI ready:` 打印早于 uvicorn `Application startup complete`，且日志轮询测得的是**采集器观测时间**而非事件发生时间——stdout 标记只允许作为降级观测记录，不得作为就绪判定或与其他信号"等价"。
- 资源下载不阻塞窗口、历史与设置；启动超时按阶段计算（方案 §5.1）。

### GET /api/health【新增，不导入重模块】

```json
{
  "api_version": "1.0",
  "instance_id": "<每次控制进程启动生成的高熵随机串>",
  "app_version": "<pdf2zh_next.__version__>",
  "control_ready": true,
  "warmup": {"state": "ready|verifying|downloading|skipped|failed", "message": ""},
  "data_dirs": {"home": "...", "config": "...", "work": "...", "cache": "...", "logs": "..."}
}
```

- 健康检查必须验证应用实例（token，见 §8）；`data_dirs` 返回**实际生效目录**，UI 不做自己的 fallback 推断。

## 2. 任务状态机

- wire 状态（`status` 字段）【保留，P1 不改枚举】：`queued | running | done | failed | cancelled`。
- 细化阶段【新增】：可选字段 `phase: preparing|running|finalizing`（run 阶段的子状态），与 `stage`（人类可读）并存。
  - 兼容规则：旧客户端（webui/app.js）忽略未知 `phase`，不得把未知状态当完成（现状已满足：未知 status 显示原文且按非终态处理）。
- 状态转移【保留现有原子保护】：`start()` 仅允许 `queued→running` 且未被取消；`cancel()` 对 `queued` 立即置 `cancelled`，对 `running` 置 `cancel_requested` 由运行循环协作取消（现状语义不变，方案已列为必须保留行为）。
- 任务重启恢复【保留】：进程重启后 `queued/running` 一律置 `failed`（任务被中断），不得伪报完成。
- 有效配置快照【新增】：任务入队时固化 `options`（语言、页码、输出种类、引擎标识、术语指纹、资源档位），重试默认沿用原快照；中途改全局设置只影响新任务。

## 3. HTTP 接口

【保留】现有业务语义：`POST/GET /api/files`、`POST /api/tasks`、`GET /api/tasks[/{id}]`、`cancel`、`retry`、`download`、`{file_id}/preview`、`{task_id}/preview`、`/api/settings`（GET/PUT，先副本校验后落盘）、`/api/glossary`、`/api/prefs`、`/api/reveal`。

【新增】

| 接口 | 契约 |
|---|---|
| `GET /api/health` | §1 |
| `GET /api/capabilities` | 引擎列表、输出能力、有效资源策略（§5）。允许缓存，不为检测能力加载模型 |
| `GET /api/assets/status` | 资源缺失/下载中/校验中/失败；含阶段、已下载/总字节、失败原因（P2 落地） |
| `GET /api/events` | SSE，见 §4 |
| `POST /api/export-receipts` | 导出回执，见 §7 |
| 分页历史 | `GET /api/history?cursor=&limit=`：活动任务单独返回且不受终态分页/50 条上限影响；终态按游标分页 |

幂等与重试【新增，P1 实现】：
- `POST /api/tasks` 与 `POST /api/tasks/{id}/retry` 均支持 `Idempotency-Key` 头（客户端生成 UUID）。
- 语义：服务器把 (键, 载荷指纹) 持久化到任务记录；同键同载荷（指纹一致）重复提交返回**既有任务**（200），不创建第二个翻译；同键并发请求只允许创建一个任务（以注册表锁保证原子去重，后来者读回既有任务）；同键**异载荷**（指纹不一致）返回 409，不得静默替换。
- 载荷指纹 = 规范化后的提交字段（file 内容哈希 + 语言/页码/输出选项/引擎快照指纹）。
- 键保留期限 24h；任务记录持久化跨重启后幂等映射仍然有效（映射随任务持久化，不做内存态）。
- **清历史与去重解耦（F5）**：`DELETE /api/tasks` 清除的是**用户可见任务列表**，不得删除 TTL 内的幂等去重记录（tombstone：键→原任务 id+载荷指纹+终态摘要，独立于任务表持久化）。TTL 内同键重放：create 返回原任务记录（含其终态），retry 返回原 retry 产物映射；**不得清历史后相同请求又创建新翻译**。TTL 过期后 tombstone 淘汰，同键视为新请求。
- retry 的键作用域与 create 独立（retry 使用自己的 Idempotency-Key；其"载荷指纹"含被 retry 的原任务 id 与原任务配置快照指纹），retry 成功创建的新任务记录其 parent_task_id=原任务 id；原任务不可见（被清历史）时，TTL 内 tombstone 仍保证 retry 重放返回**稳定的既有响应**（原 retry 结果），不静默重建。
- `cancel`、导出回执为幂等操作；重复调用结果一致。
- `DELETE /api/tasks`【行为修正，P1 实现】：仅清终态任务；不得清掉 `queued/running`（现状会整表清空，方案 §11.3 已列为需修正项，含回归测试）；清历史不删 TTL 内 tombstone（见上）。

## 4. SSE 事件契约【新增】

端点 `GET /api/events`（需 token）。**唯一事件信封（F5 冻结：JSON 定义与 SSE wire 一一对应，实现只允许照此一份规范落地）**：

JSON 信封（`data` 内）与 SSE 帧的对应关系——**唯一规范**：

```text
id: <instance_id>:<event_id>          ← SSE id 行 = 实例化游标（可校验归属）
event: task.updated                   ← 信封 type
data: {"instance_id":"i-9f3","event_id":1001,"ts":1695859200.5,
       "type":"task.updated","task_id":"b0efbb","data":{...任务载荷...}}
```

- `id:` 行必须是 `<instance_id>:<event_id>` 复合游标；客户端**不得**把它当裸整数。信封 JSON 与 `id:` 行信息一致（同一 event_id/instance_id），两种表示由同一服务器代码生成。
- `task_id` 在信封顶层（任务类事件必填，非任务事件为 null）；任务完整载荷在 `data` 内。
- `event_id`：本实例内单调递增整数；`instance_id` 随控制进程重启变化。

**连接生命周期（F5 四条唯一流程，服务器行为逐条定义）**：

1. **初连（无 Last-Event-ID）**：服务器原子完成"注册订阅 → 读取快照 → 记录水位 W"，先发 `id:<i>:W` 的 `snapshot`（含 `last_event_id=W` 与全量数据），此后仅发送 event_id > W 的事件——快照读取期间发生的事件不会丢失（订阅先于读快照或等价原子方案）。
2. **同实例可重放**：Last-Event-ID 的 instance_id == 当前实例 → 在有界缓冲（1024 条）内重放 (W, current] 的缺口事件（含期间可能已发的 snapshot 水位对齐），重放完成后接实时流。
3. **游标过期**：instance_id == 当前但 event_id 已被缓冲淘汰（W_min > 请求游标）→ 发 `event: resync`（data.reason="gap"）→ 客户端丢弃本地增量、重走初连流程拿新 snapshot。**不允许**跳过缺口继续推实时流。
4. **实例重启**：Last-Event-ID 的 instance_id != 当前实例 → 一律走初连流程（发新 snapshot），客户端据此重新对账（旧实例任务视为已中断，不误认仍在运行）。

- 溢出：慢订阅者缓冲满 → 主动断开；客户端按流程 2/3 重连，服务器不无限堆事件。
- 终态与 revision 竞态（P1 测试清单）：①终态后到达的旧 revision 进度事件必须被服务器丢弃或客户端忽略，二者取其一并在契约测试固化；②`task.final` 不被节流合并；③流程 1 的原子水位用并发订阅+并发写事件的测试验证不漏事件；④重连风暴下 instance_id 变更检测。
- 节流：进度类事件合并至每任务每秒 2–4 次；`task.final`（done/failed/cancelled）与错误**立即发送**，不被节流丢弃。
- `task.revision`：每任务单调递增；客户端拒绝旧 revision 的晚到事件；终态不可被晚到进度覆盖。
- 事件类型：`snapshot`、`task.created`、`task.updated`（status/progress/stage/phase/revision）、`task.final`、`settings.updated`、`assets.updated`（P2）。
- 仅一个订阅连接更新 TaskStore；所有页面绑定同一来源。保留现有轮询作为开发期/故障降级：前台活动 1–2s、后台 ~5s、空闲停止；不与 SSE 同时常开。
- **EventSource ticket 生命周期**：ticket 单次使用，连接建立即消耗；客户端自动重连时**必须重新取票**（POST /api/auth/ticket → 新 ticket → 新连接 URL），不得复用已消耗的 URL（避免重连永远 401/403 或 URL 复用漏洞）。旧连接由客户端显式关闭；服务器对同 ticket 二次使用返回 401 并记录（不含 ticket 值）。

## 5. 资源档位与并发契约【新增】

三参数分离命名（方案 §6.1，初值）：

| 参数 | 节能 | 均衡（默认） | 性能 |
|---|---:|---:|---:|
| `document_concurrency` | 1 | 1 | 1（实测内存充足可 2） |
| `local_compute_threads` | min(2, L) | max(1, min(4, L-2)) | max(1, min(8, L-2)) |
| `api_inflight_limit` | 4 | 8 | 16 |
| `api_qps_cap` | 2 | 4 | 8 |
| 预览渲染并发 | 1 | 1 | 1 |
| 邻页预取 | 关 | 空闲时 1 页/方向 | 同均衡 |

生效规则（必须真实到底层，方案 §6.2；**实现归属：P1 = 档位参数与 QPS 收敛、document_concurrency；P2 = 底层线程注入、预览并发/缓存、邻页预取**）：
- **最终 QPS = min(用户设置, 服务配额/建议, 档位上限)**。SiliconFlowFree 等服务的强制/建议值（现状：`config/model.py` 强制 qps=20；`translator/utils.py` 用 recommended 值覆盖用户值）不得绕过档位上限；需回报"请求值 / 服务限制 / 最终值"。
- `document_concurrency` 生效为同时运行的文档 worker 数；现状 `PDF2ZH_TASK_WORKERS`（默认 2）被档位收敛：`effective = min(env, tier.document_concurrency)`，环境变量语义保留但不再允许超过档位。
- `local_compute_threads` 在 **worker 子进程内**生效：导入重库前设置 `OMP_NUM_THREADS`/`MKL_NUM_THREADS`/`OPENBLAS_NUM_THREADS`；OpenCV `cv2.setNumThreads()`；ORT SessionOptions `intra_op`/`inter_op`；BabelDOC layout 线程池 `os.cpu_count()` 改为显式参数（可复现补丁，见 `build/patches/babeldoc/`）。
- UI 不全局污染环境变量；控制进程不为探测能力加载模型。

## 6. 目录与数据所有权契约

- 唯一解析器【新增，P1 实现】：启动方（launcher/Supervisor）确定 home 并通过 `PDF2ZH_HOME` 传递；后端不再依赖 CWD（现状 `WORK_DIR = Path("pdf2zh_files").resolve()` 随 CWD 漂移，必须改为从 home 派生）。禁止 C# 与 Python 各一套 fallback。
- **环境变量边界（P0 审核 R5 澄清）**：不得为目录解析而设置或修改**用户级/系统级**的 HOME、USERPROFILE、APPDATA 等环境配置；进程级/子进程级环境覆盖仅限本应用自己的子进程，由启动方发起并在诊断日志记录实际生效路径。现状 start-webui.py 在后端进程内重定向 USERPROFILE/HOME/APPDATA 属于"本应用子进程级覆盖"，迁移时收敛为启动方注入、仅作用于子进程。
- 安装模式：`%LOCALAPPDATA%\PDFMathTranslate\{config,work,cache,logs}`；便携模式：`home\` 显式标记，不凭"可写"猜测（现状探测式回退保留为兼容，目标行为见方案 §11.1）。
- 所有权与单写者【P1 实现】：Python 独占写配置/任务/历史/资源状态；WPF 只写纯 UI 偏好（窗口位置等），共用的默认导出目录走 `/api/prefs`。控制进程对数据目录持有独占写锁；第二入口（含旧版启动器）激活已有实例或明确提示，不产生第二个写入者。
- 迁移【P1 实现】：检测旧目录 → 备份 → 校验 → 原子切换 → 写迁移版本标记；幂等可重入，可回退；历史中的绝对路径做存在性对账。

## 7. 导出与回执契约【新增，P1 实现】

- 后端产物暂存于 work 目录（不覆盖：`PDF名_日期/PDF名_双语.pdf`，同日冲突加序号）；"翻译完成"≠"已保存到用户目录"。
- **输出身份（output identity）**：每个暂存产物有稳定标识 `(task_id, kind, output_revision)` 与内容指纹 `(size_bytes, sha256)`。身份由**内容**决定，不由目标文件名/路径决定——用户"另存为"改名、目标目录冲突后缀（`(2)`）均为合法保存，回执不得因此被拒。
- 用户导出（保存/另存为）成功后，WPF 以稳定 `export_id`（UUID）提交回执：

```json
POST /api/export-receipts
{"export_id":"...","task_id":"...","kind":"dual|mono|glossary","output_revision":1,
 "saved_path":"<用户任意合法路径，允许改名>","size_bytes":123,"sha256":"...","saved_at":"..."}
```

- 服务器校验：task 存在、kind 有效、`output_revision` 与该任务暂存产物的当前修订一致、`size_bytes/sha256` 与暂存产物内容一致。**文件名/路径不参与内容身份校验**（允许合法改名），但 `saved_path` 必须回执留存用于定位最终文件。
- **不可变载荷（F1）**：同一 `export_id` 的完整载荷为五元组 `(task_id, kind, output_revision, saved_path, 内容指纹[size_bytes+sha256])`——任一字段不同即视为不同请求。
- 幂等：同一 `export_id` + **完全相同的不可变载荷**重放 → 200 返回同一记录；同一 `export_id` + 任一字段不同（含换目标路径、换修订、换内容指纹）→ **409**，不得静默覆盖或创建第二条记录。
- 回执失败：UI 区分"文件已保存 / 记录待同步"，本地有界持久待办用**同一 export_id** 重试；不得重新复制产生 `(2)` 文件。
- **暂存清理前置条件（F1 修正：核验对象是 saved_path 指向的最终文件，不是暂存文件）**——全部满足才可清理暂存副本：
  1. 后端已取得持久回执记录；
  2. 已按保留策略确认无保留需求；
  3. **对 `saved_path` 最终文件做内容验证**：可打开读取、`size_bytes` 一致、SHA256 与稳定产物身份一致（即与暂存产物同源同内容——内容相同才互为副本，暂存才可删）；
  4. 验证与清理之间文件变化边界：验证通过后以**独占打开句柄/等价原子方式**执行删除暂存前最后一次确认；若两步之间发现最终文件被改动（哈希不再匹配），中止清理并回执转回"待验证"。
- **最终文件异常时的暂存保留（F1）**：`saved_path` 缺失、盘离线、不可读、size/SHA256 不符——任何一种情况都必须**保留唯一有效暂存副本**，回执维持"待验证"状态；绝不允许因目标路径存在同名文件而删除暂存。后续用户修复/重存后，可重新验证并走同一 export_id 流程。
- **验收案例（F1，作为未来实现的验收标准；P0 未实现、未运行）**：

| 案例 | 输入 | 预期结果 |
|---|---|---|
| 合法改名 | 用户另存为 `论文_终稿.pdf`（内容与产物一致） | 回执 201/200 接受；后续清理校验该最终文件通过 → 暂存可删 |
| 在线损坏 | 目标盘在线但最终文件被截断/改写（SHA256 不符） | 回执转"待验证"；暂存保留；不清理 |
| 目标缺失 | saved_path 文件被用户移动/删除 | 同上——暂存保留，UI 提示重新导出 |
| 盘离线 | 外置盘暂离线、saved_path 不可达 | 同上——不得把离线当"已可清理" |
| 同键换目标 | 同一 export_id 重放但 saved_path 不同 | 409；原记录不变，不产生第二条 |

- 不覆盖规则【保留】：同名输出永不覆盖，用独占创建/预留原子处理并发命名；`.partial` 流式写 + 校验后原子提交。
- 不覆盖且不修改：`launcher/MainForm.cs` 现有 UniqueFilePath 逻辑与"更新文件关闭后再哈希"修复在迁移期保持行为不变。

## 8. 安全契约【新增】

- 仅绑定 127.0.0.1；每次启动生成高熵 token，经受限管道传递给 UI；所有 API（含健康检查、SSE、预览、文件输出）校验 token；不写普通日志、SSE 或命令行参数。
- **鉴权传递格式（P1 实现须覆盖所有调用方，不得以关鉴权解兼容）**：
  - WPF 原生客户端（fetch/HttpClient/SSE 客户端）：`Authorization: Bearer <token>` 头。
  - 旧 WinForms/WebView2 入口（迁移期兼容）：launcher 用 WebView2 `WebResourceRequested` 拦截本实例 `127.0.0.1:<port>/api/*` 与静态页请求**注入 Authorization 头**；`<img src>`、下载链接等子资源请求同样经该拦截器注入——WebView2 拦截覆盖子资源，无需 token 入 URL。
  - 浏览器 EventSource 类调用（不能自定义请求头）：先 `POST /api/auth/ticket`（Bearer 保护）换**一次性短时效 ticket（≤10 秒、单次使用）**，SSE 连接 URL 携带 `?ticket=`；ticket 不写日志、用后即焚。不得把长期 token 放 URL。
  - 明确禁止：关闭鉴权、把 token 写普通日志、在 URL 中携带长期 token。
- 限制 Host/Origin，不开放任意 CORS；本机 API 请求绕过外网代理（现状 NO_PROXY 保留）。
- 文件接口路径规范化与许可范围校验（现状 `_resolve_uploaded_file`、`/api/reveal` 白名单语义保留并延续到新接口）。
- 凭据不进日志/事件/历史；历史任务配置快照不含 API Key。

## 9. 兼容与迁移规则

- P1 期间旧入口（launcher + webui）保留可用；新 WPF 与旧入口共享 `Global\PDFMathTranslateNextSingleInstance` 互斥与数据写锁。
- 未知字段/状态容忍：旧客户端忽略新字段（phase、revision 等）；新客户端容忍缺失新字段。
- 状态枚举扩展（如引入 preparing/finalizing 为顶层）必须升 `api_version` 并同步所有 UI/持久化/测试。
- 本契约未覆盖处，以方案为准；冲突时先修订本契约并经审核，不得实现间擅自分叉。
