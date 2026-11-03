# 原生桌面迁移实施状态（进度文件）

> **当前状态快照（2026-11-03，优先于下方历史记录）**：最新 Codex 审核 `docs/reviews/native-desktop/P0-CODEX-r2-review-2026-10-03.md` 判定 P0 部分通过、暂不放行 P1；后续独立安全门 `docs/reviews/native-desktop/P0-r2-integrated-safety-review-20261003-01.md` 仍为 **BLOCKED**。不要把旧记录中的 384/384 或“P0 完成”当作当前放行结论。该安全门列出 B1、B2、M1–M5，详见报告 §2–4。
>
> GitHub 交接分支包含审核、计划、契约和 P0 测试代码；`docs/verification/native-desktop/**` 的本机运行证据与隔离缓存未纳入该分支。另一台电脑不得声称已复核这些历史证据，应在隔离环境中为需要的项目生成新证据。当前分支不含 WPF 产品实现。

> 本文件是上下文恢复入口。每次工作包结束、阻塞、暂停或交接前更新。
> 权威实施方案：`docs/NATIVE_DESKTOP_OPTIMIZATION_PLAN_2026-09-28.md`
> 主交接报告：`docs/NATIVE_DESKTOP_REVIEW_HANDOFF.md`

## 最后更新

- 2026-10-03（P0 系统性验收轮 **systematic-acceptance-20260930-01 完成（含 D8 修复闭环），待 Codex 终审**：上轮 S1–S6 六项阻断全部关闭（S1 启动门 sys.modules 哈希绑定+G04/G05/G15 负向套件+attribution 每载荷接入；S2 三模式 3/3+伪回环+4 变异副本全拒+谓词 ASCII 严格化；S3 existed/value+PYTHONPATH+G16 九用例；S4 身份复查绑定/唯一 result/catch/跨源去重/not_deployed+N04；S5 校验器 v3 真实执行+13 变异自测+LOG_COPY_INDEX；S6 24 冻结+4 新增全证据）。安全门 A 首轮 BLOCKED→修复→复审 PASS。独立终审确认工程实质成立但列 4 MAJOR（F1 自测绑旧版/F2 跨源去重/F3 虚构路径/F6 attribution 绑中途版本）+8 MINOR——**全部修复并复跑**，r2 复审（P0-systematic-acceptance-final-review-20260930-r2.md）4 MAJOR 全部验证关闭、r1 MINOR 大部关闭，最终裁决：**推荐交 Codex 终审**；r2 新增 3 MINOR（N1 std 记录引用/N4 绑旧版/INDEX 追加标注）亦已修复+复验；最终绑定（N04 当前版本旧版替换）仍 **384/384、0 失败、exit 0**。报告链：P0-systematic-acceptance-implementation-20260930.md（§6 修复表）/P0-systematic-acceptance-safety-review-20260930-01(-r2).md/P0-systematic-acceptance-final-review-20260930(-r2).md。**无提交**——HEAD b504906，待用户授权备份提交或 Codex 终审）

## 当前 Git 状态

- 分支：`codex/native-desktop-2026-09-28`（自 main@b504906769f15a3b048e2336755a2d563b0cb1ae 创建）
- 基线提交（迁移前）：`b504906769f15a3b048e2336755a2d563b0cb1ae`
- 远程备份分支：`origin/codex/baseline-before-native-2026-09-28`（同一基线，只读保护，不修改）
- main 不直接改动；不自动合并；未获授权不 push / 不建 PR / 不打 tag / 不动 Release

## 当前阶段与工作包

- 当前阶段：**P0 整改轮**（依据 docs/reviews/native-desktop/P0-CODEX-review-2026-09-28.md，暂不放行 P1）
- 本轮约束：只整改 P0；不启动 WPF 迁移；不改产品业务代码；不清空真实 tasks.json；不调用真实翻译；不改安装环境/更新链；未获新授权不 commit/push/tag/Release
- 单一写入方：主代理（本 AI）。Codex 审核 11:19 定稿后无其他写入

## R1–R6 整改表（2026-09-28 制定）

| # | 问题（摘要） | 证据 | 修改文件 | 验证方法 | 完成条件 |
|---|---|---|---|---|---|
| R1 | 测量写入真实安装目录且清理无恢复证明；harness 复用固定临时目录并递归删除、无 try/finally、注销全部事件订阅、端口归属未验证、翻译任务默认开启、失败仍 DONE | CODEX 审核 R1（p0_baseline.ps1:189-193,40-43,169-180,208-226,303-339）；基线报告 §4.5 | tests/performance/p0_baseline.ps1、p0_probe_perprocess.ps1、p0_probe_attribution.ps1 | 静态安全审核（独立子代理）+ 安全用例演练（端口冲突/异常退出/缺资源路径）；隔离审核通过前不重跑测量 | 三个入口全部满足：唯一临时根+所有权标记、CWD/配置/缓存/上传输出/任务历史全部在本次根内、安装目录只读借用、try/finally 回收本次进程、按 PID 树回收不按名杀、翻译默认关且独立开关、失败/跳过非零退出码、临时目录不自动递归删除 |
| R2 | 基线对象是安装版 v2.9.0 而非当前仓库 source（http_api.py/__init__.py/high_level.py/config/model.py SHA256 均不同；安装版每任务新建线程 vs 仓库受限执行器），报告未区分 | CODEX 审核 R2 哈希表 | docs/verification/native-desktop/P0-baseline-report.md（重分类）、新增仓库后端离线基线（run-*） | 哈希 manifest + 重跑仓库后端离线基线（不翻译） | 报告区分"安装版后端探索样本/当前仓库后端基线/旧完整桌面基线（延期）"三类口径；仓库离线基线有 manifest 与原始样本 |
| R3 | ①"stdout 与 API 探测等价"结论错误（ready 打印早于 uvicorn startup；采集器发现时间非事件时间；根路径接受 4xx）；②漏查 `pdf2zh_next/__init__.py:27-30` 包导入即拉起 high_level→BabelDOC | CODEX 审核 R3；start-webui.py:104-105；__init__.py:27-30 | P0-baseline-report.md、DESKTOP_API_CONTRACT.md（如涉及）、STATUS | 重新核对 __init__.py 与 start-webui.py 代码；attribution 复测时记录导入完成握手 | 报告撤销等价结论，区分 stdout 观测/API 可用/窗口可交互（窗口延期）；导入链事实补入 §1；契约按需补"就绪三态" |
| R4 | 导出回执契约要求"文件名/大小与暂存产物一致"会拒绝合法另存为改名；清理条件未验证最终内容 | CODEX 审核 R4；MainForm.cs:130 UniqueFilePath | docs/DESKTOP_API_CONTRACT.md §7 | 对照 MainForm 另存为行为与契约条目复核（独立子代理） | 身份=稳定 output 身份/revision+size+SHA256，允许改名与冲突后缀；同一 export_id 异载荷 409；验证前不删唯一暂存副本；外置盘离线=待验证 |
| R5 | 契约缺 retry 幂等、SSE wire 细节（id:/游标/水位/重放/溢出恢复）、鉴权传递与旧入口兼容（img.src/下载链接）、路径解析表述含混、档位归属未标 P1/P2 | CODEX 审核 R5 | docs/DESKTOP_API_CONTRACT.md | 独立子代理对照现有调用方（webui/app.js、launcher、http_api.py）复核 | R5 五个子项全部成文且标注 P1/P2 实现归属 |
| R6 | 统计可纠正错误（线程 44-51 应为 42-51、CSV 样本数、private 峰值表述、预览中位数 20.3）；归因数字缺原始记录（后已补 probe-attribution.jsonl 但隔离不合规）；pytest 隔离未证明（PDF2ZH_HOME 不经过 start-webui，const.py/cache.py 直用用户 home）；"100 passed"缺原始输出 | CODEX 审核 R6；idle-5min.csv；const.py:8-15、translator/cache.py:103-104 | P0-baseline-report.md（统计修正）、tests/performance/（pytest 隔离 bootstrap）、新增隔离重跑证据 | 重算原始 CSV/JSON 并在报告标注统计方法与样本量；pytest 用隔离 bootstrap 运行前后核对真实数据目录哈希/mtime | 全部数字可从落盘证据复算；撤销"5 分钟证明非泄漏""12 次=UI P95"表述；pytest 证据含完整输出/退出码/warnings/隔离核对 |

## 当前目标（P0 整改轮）

按依赖顺序执行 WP1→（安全审核通过）→WP2 ∥ WP3→WP4，完成后停止等待用户交 Codex 再审。

## 整改轮进展（2026-09-28 完成态）

- ✅ WP1：三个测量入口 v2 重写 + `source/tests/conftest.py` 隔离；独立安全审核通过（`P0-harness-safety-review.md` 阻断 0/一般 3/建议 7，"允许试运行"；G1/G2/G3 已修复后运行；另修复 PS5.1 `ByteArrayContent::new(, $bytes)` 解析错误）
- ✅ WP2：口径 A 仓库后端离线基线（正式 run-v2-20260928-120431：apiReady 4.24/3.57/3.56s、空闲 303.2s CPU 0.45s 归一化 0.0074%、private 末值 1488.5MB、预览 median 20ms p95 35ms；试运行 run-v2-20260928-115520 为独立数据点）+ manifest（babeldoc 0.6.2/pymupdf 1.25.2/onnxruntime 1.27.0/仓库与安装版文件哈希）；归因 v2（导入握手+全隔离：http_api 导入 1416.7MB，`__init__.py:27-30` 导入链实锤）；隔离 pytest **100 passed 且真实用户目录前后快照零变更**（run-v2-20260928-122042-pytest）；统计修正（58 样本/private 最大 1490.2=首值/线程 42–51/预览中位 20.3ms）与 v1 三项错误结论撤销全部落入基线报告 v2
- ✅ WP3：契约 v1.1（R4 导出内容身份/允许改名/异载荷 409/暂存清理前置；R5 retry 幂等、SSE wire 格式/水位/重放/溢出/竞态清单、鉴权传递格式含旧入口、目录单写者与环境变量边界、P1/P2 归属）
- ✅ WP4：补丁双向核验 + 洁净下载哈希核验通过（patch-verify-20260928-114134.txt）；基线报告 v2 / HANDOFF §9 / STATUS 重写一致；v1 三个失败 run 已删除如实登记
- ✅ 整改轮独立复审：完成（`docs/reviews/native-desktop/P0-remediation-review.md`）。注意：该复审的"R1–R6 全部通过"随后被 CODEX 终审部分推翻（`P0-CODEX-remediation-final-review-2026-09-28.md`，F1–F7），以终审为准进入收尾轮（见"最终收尾轮进展"节）；4 项非阻断文字更正当时已落实
- 本轮红线遵守：无 commit/push/tag；无真实翻译调用；无产品源码修改；site-packages 未动；真实 tasks.json 未清空；安装环境只读借用
- **下一步：本轮到此停止，等待用户交 Codex 终审**；是否创建本地提交、是否进入 P1（需 .NET 10 SDK 安装方式确认）均待用户明确授权

## 最终收尾轮进展（F1–F7，2026-09-28）

依据：`docs/reviews/native-desktop/P0-CODEX-remediation-final-review-2026-09-28.md` + `P0-final-closure-prompt-2026-09-28.md`

| 工作包 | 内容 | 状态 |
|---|---|---|
| WP-A (F1/F5) | 契约 v1.2：§7 清理校验对象改为 saved_path 最终文件（可读+size+SHA256 对稳定产物身份）、不可变载荷五元组、5 个验收案例；§3 清历史与 TTL 去重解耦（tombstone）、retry 键作用域；§4 冻结唯一事件信封 `id:<instance_id>:<event_id>` + 初连/同实例重放/游标过期/实例重启四流程 + ticket 用后重新取票 | ✅ 完成（规范，未实现产品） |
- ✅ WP-B（F2/F3/F4）：六脚本修订（失败统一累计+单一退出点、stdout 仅观测、root200 必需、PNG 全签名+IHDR+CRC32+预期宽度、进程身份记录+身份复查、缓存逐文件 SHA256 校验、sitecustomize socket 防护、PDF2ZH_CONFIG_FILE 隔离+env 白名单+PYTHONPATH/Git env 保存恢复、-FailInject 钩子）；语法全过
- ✅ WP-C：独立安全审核（`P0-final-safety-review.md`：阻断 1+一般 5，修复后审核通过）→ 10+1 项负向用例驱动实际入口：**11/11 PASS**（独立复审方向逐案复核与期望一致；perprocess v3 未执行——无 per-process 证据文件，F3 perprocess 尺度保留）+ pytest 复跑（**100 passed**、真实目录零变更、快照落盘含读取失败=0、runner/conftest 哈希绑定；空文件落盘缺陷修复后复验通过 run-v3-20260929-002035-pytest）
- ✅ WP-D（F6/F7）：样本 PDF 封存（哈希与终审一致）+ 7 份脱敏日志（原始+脱敏双哈希索引）；基线报告 F3 离线口径更正+F7 误引撤销；HANDOFF 唯一当前基线入口+§5.3 标历史+已删失败 run 如实登记；独立复审报告待写

## 历史过程记录（整改轮中期，保留供追溯）

- ✅ R6（部分）：归因探针证据已归档并复测（`probe-attribution-v2-*.jsonl` 待安全审核后生成；旧 v1 证据标注隔离不合规）
- ✅ R6：真实 home 污染已查明并处理——我方 pytest 在真实 `~/.config/pdf2zh` 触发 `gui.py:2386` 写入 49 字节 `config.fake.pdf`（已删除）；`~/.cache/pdf2zh_next` WAL/SHM 被我方探针触碰（用户缓存 db 本体未动、如实记录）；翻译产物污染安装目录已在第一轮清理（CODEX 审核复核确认，但"无清理前快照"的教训已吸收：本轮起所有运行带前后快照对照）
- ✅ 测试隔离辅助：`source/tests/conftest.py`（HOME/USERPROFILE/CWD 会话级隔离）
- ✅ R1：三个测量入口 v2 重写（唯一临时根+owner.json、子进程 env 全隔离、端口预检+归属验证、try/finally 树回收、离线强制、退出码 1/2/3/4、Stopwatch、PNG 魔数校验、根路径仅 200、stdout 仅观测）
- ✅ WP4（部分）：BabelDOC 补丁核验通过——反向应用=官方 wheel 文件（SHA 208B394D…）、正向重放=安装文件（SHA 3261EFFF…）、numstat 14/0、py_compile 通过、洁净下载 wheel 哈希核验（FA7252AA…）通过；证据 `docs/verification/native-desktop/patch-verify-20260928-114134.txt`
- ✅ R4/R5：契约修订为 v1.1（导出内容身份校验/允许改名、retry 幂等、SSE wire 细节、鉴权传递格式、目录所有权/环境变量边界澄清、P1/P2 归属标注）
- ⏳ R3：基线报告修订待 WP2 一起做（撤销等价结论、__init__.py 导入链补查、统计修正）
- ⏳ R2：仓库后端离线基线待安全审核通过后运行（WP2）
- ⏳ WP1 安全审核：✅ 完成（`docs/reviews/native-desktop/P0-harness-safety-review.md`，阻断 0/一般 3/建议 7，结论"允许试运行"）；3 项一般问题（G1 归因探针失败路径不回收、G2 翻译 skip 恒致 exit 2、G3 perprocess 探针遗留复查缺失+finally 内 exit 掩盖异常）均已修复；PS5.1 解析错误（ByteArrayContent `::new(, $bytes)` 非法语法）修复后重跑中
- ✅ R6（旧数据统计复算，来自原始证据）：idle CSV 实际 **58 个数据样本**（此前报告误写 60）；private **最大 1490.2 MiB**（=首样本，末值 1489）；线程范围 **42–51**；预览 n=12 排序 19.0–20.9ms + 尾部 57.6ms，**中位 20.3ms**（偶数取两中位均值）、nearest-rank p95=57.6ms（n 小导致 p95=max）

## P0 工作包清单（第一轮执行记录，已被 CODEX 审核 R1–R6 部分推翻，见整改表）

> 注：P0-3/P0-5 的"完成"仅代表执行动作完成；CODEX 审核认定测量对象/隔离/统计/契约存在问题，P0 未放行。历史记录保留原状，不回改。

| # | 工作包 | 状态 |
|---|---|---|
| P0-1 | 建立开发分支与进度/交接文件骨架 | ✅ 完成 |
| P0-2 | 现状核查（功能/依赖/数据目录/更新机制/测试条件） | ✅ 完成（含 BabelDOC 补丁归档、测试套件 100 passed 实测） |
| P0-3 | 启动/空闲/预览/翻译测量基线 | ✅ 完成（2026-09-28 10:48 采集完毕，证据 run-20260928-104200） |
| P0-4 | 任务状态/事件/资源参数/目录/导出回执契约 | ✅ 完成（docs/DESKTOP_API_CONTRACT.md，含审核整改） |
| P0-5 | 独立审核 + 修复 + 更新报告 | ✅ 完成（0 阻断/2 一般/8 建议；一般项已整改，详见 HANDOFF §9） |

## 当前目标（P0）

1. 确认当前功能、依赖、数据目录、自动更新机制及测试条件。
2. 建立启动、空闲、翻译、预览的测量基线；不能测的明确标记待测。
3. 确定任务状态、事件、有效资源参数、目录和导出回执契约。
4. 引用现有实施方案，不重写大方案。

## P0 预计修改的文件

- 新增：`docs/NATIVE_DESKTOP_IMPLEMENTATION_STATUS.md`（本文件）
- 新增：`docs/NATIVE_DESKTOP_REVIEW_HANDOFF.md`
- 新增：`docs/DESKTOP_API_CONTRACT.md`
- 新增：`docs/reviews/native-desktop/P0-review.md`
- 新增：`docs/verification/native-desktop/`（基线测量证据，脱敏）
- 新增：`tests/performance/p0_baseline.ps1`（测量 harness）
- 新增：`build/patches/babeldoc/0001-assets-upstream-env.patch`（BabelDOC 本地手改的可复现归档）
- 不修改任何源码（P0 只读核查 + 测量）

## 验收方式（P0 放行条件）

- 现状核查：对方案 §1 中每条"修改前必须核实"的现状给出核实结论（确认/已变化/待测）。
- 基线：启动/空闲/预览有实测数据与命令、退出码、证据文件；翻译基线不可测时明确标记待测及原因。
- 契约：状态机、SSE 事件、资源参数、目录、导出回执五项契约成文，且与现有 API 语义标注差异。
- 独立审核：审核代理实际读取代码与证据，产出 `P0-review.md`，阻断项修复后放行。

## 已完成并验证

- 开发分支 `codex/native-desktop-2026-09-28`（自 main@b504906）。
- 现状核查：方案 §1 现状表逐条核实完毕（见 docs/verification/native-desktop/P0-baseline-report.md §1）。
- BabelDOC 0.6.2 本地补丁：RECORD+官方 wheel 双重校验，唯一手改文件 assets.py 已归档为可复现补丁。
- 测试条件：隔离 venv 建立并实测 source/tests **100 passed**（产品 site-packages 未动）。
- 契约初稿：docs/DESKTOP_API_CONTRACT.md（状态机/SSE/资源档位/目录/导出回执/安全）。

## 已实现但未验证

- 无（P0 全部产出已验证；翻译引擎标识与 WPF 窗口指标等待 P1+ 验证，见 HANDOFF §2）

## 阻塞及风险

- **P1 前必须解决：.NET 10 SDK 未安装**（本机仅 8.0.414，位于 `D:\paper\.dotnet-sdk`）。需用户确认安装方式（winget/官方安装包/自定义目录）后再进入 P1 实施。
- 无 AGENTS 指令文件：全库 `**/AGENTS.md` 无匹配，已按用户提示词与实施方案执行。
- 本机全局 git 配置 `status.showUntrackedFiles=no`（用户既有配置，未改动）：查看未跟踪文件必须用 `git status -u`。
- 开发机系统 Python（miniconda）无 pdf2zh_next；可用运行时位于已安装产品目录 `D:\paper\pdf2zh-install-test\`。

## 下一项具体任务

1. ✅ P0 系统性验收轮（systematic-acceptance-20260930-01）实施完成：S1–S6 全部关闭、24 冻结项+4 新增项全证据、最终绑定校验 360/360 exit 0；独立安全门 A 复审 PASS；独立最终复审报告由独立审核者撰写于 docs/reviews/native-desktop/P0-systematic-acceptance-final-review-20260930.md。
2. 本轮到此停止，交用户/Codex 终审；是否创建本地提交（备份）、是否进入 P1（需 .NET 10 SDK 安装方式确认）均待用户明确授权。

## 定点收尾轮（C1–C4，2026-09-29，进行中→完成）

| C 项 | 内容 | 实现完成 | 自测完成 | 独立审核完成 | 待终审 |
|---|---|---|---|---|---|
| C1-① | p0_asset_check.ps1 权威 SHA3-256 资产预检 | ✅ | ✅（case 3a/3b/11/12 全 4/4） | ✅ | 待 Codex |
| C1-② | sitecustomize.py v2 异步防护 + B2 GUARD_ACTIVE 校验 | ✅ | ✅（guard 7/7 + 三入口 B2） | ✅ B1/B2 修复后 | 待 Codex |
| C2 | perprocess Add-Type + 短采样/回收验证 | ✅ | ✅（2026-09-29 01:18 实跑，exit 0，182 项 PASS） | ✅（首轮阻断→修复后实跑） | 待 Codex |
| C3 | png_check.ps1 v4 PIL 真实解码验证 | ✅ | ✅（case 9+13 PASS） | ✅ | 待 Codex |
| C4 | 矩阵 v4 独立 run+reason 断言+HANDOFF 口径区分 | ✅ | ✅（14/14 全量+局部 4/4） | ✅（首轮 3 阻断→已修复实跑） | 待 Codex |

安全门 A：`P0-targeted-closure-safety-review-2026-09-29.md`——首轮 2 阻断（B1 httpx 假阳性/B2 GUARD_ACTIVE 缺失），修复后复审通过（允许全量矩阵）。

- 复审报告：`docs/reviews/native-desktop/P0-final-closure-review.md`（独立复审代理写入）
- F1（契约 §7 导出清理校验最终文件+五元组+验收案例）：**通过**
- F2（失败判定+单一退出+进程身份）：**通过**，2 项保留（R1 matrix.csv 行缺失→已修复重跑有行；R2 case-6 注入未执行→已加 StartInfo 赋值并复跑 PASS）
- F3（离线+缓存校验+socket 防护）：**通过**（perprocess v3 未执行——保留为待测，不影响 F3 核心判定）
- F4（CONFIG_FILE 隔离+env 白名单）：**通过**，1 项修复不完整（R4 attribution 缺 *_PROXY→已加并复验）
- F5（SSE 唯一信封+四条生命周期+tombstone）：**通过**
- F6（证据封存+补录 manifest+脱敏日志）：**通过**，1 项工件缺陷（R3 pytest 空文件→已加 guard 并复验落盘）
- F7（HANDOFF 唯一入口+历史标注+误引撤销）：**通过**
- 总体结论：**建议交 Codex 终审**；4 保留项已全部修复并局部重跑验证（非阻断级）

## 证据与报告路径

- 基线报告：`docs/verification/native-desktop/P0-baseline-report.md`
- 测量证据：`docs/verification/native-desktop/run-v2-20260928-120431/`（口径 A 正式基线，含 manifest）；历史 `run-20260928-104200/`（安装版探索样本）；收尾轮 `final-closure-20260928-215802/`（样本+脱敏日志+负向矩阵+pytest 复跑）
- 测量 harness：`tests/performance/p0_baseline.ps1`、`p0_probe_perprocess.ps1`、`p0_probe_attribution.ps1`
- BabelDOC 补丁：`build/patches/babeldoc/0001-assets-upstream-env.patch`
- 审核报告：`docs/reviews/native-desktop/P0-review.md`

