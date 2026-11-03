# P0 r2 最新快照 Codex 终审（2026-10-03）

## 裁决

**部分通过，暂不认可 P0 系统性整体验收完成，不放行 P1。** 本轮查验覆盖 r2 报告之后的增量，确认当前确实是 **384 条报告内 PASS、退出记录 0、23 项 canonical 哈希一致、208 份日志副本哈希一致**。但报告的零失败并不等于全部授权条件已满足：存在可证明的双层网络误放行、未隔离的小子进程、负例只比较退出码、外层实际退出证据缺失，以及校验器错误未纳入失败。

这些不是要求产品重构或追加完整桌面测试，均属于已经授权的安全底座、全入口隔离、失败判定、证据绑定范围。无需重做已关闭的契约/PNG/历史基线，也不应把已完成的矩阵当中断任务重试。

本次由主审与两个未参与实现的独立子代理 `r2_runtime_safety_audit`、`r2_coverage_integrity_audit` 交叉核验。只读文件/Git/哈希/证据；另做纯数字地址解析（AI_NUMERICHOST，不调用 DNS、不建立连接）。未执行被审脚本、checker、矩阵、后端、pytest、翻译或下载。唯一新增文件为本报告。未修改实现、真实用户数据或 Git 状态。

初始现场：分支 `codex/native-desktop-2026-09-28`，HEAD `b504906769f15a3b048e2336755a2d563b0cb1ae`，1125 个未跟踪条目，tracked/staged diff 均空。新增本报告后数量增加。

## 一、已确认的 r2 及后续修复

| 检查 | 本次独立核验 |
|---|---|
| 当前版本绑定 | 根 `script-hashes.json` 的 23 项逐项重算全部一致；当前 sealer 为 `F0360EAE…`，不是 r2 审核的 `91F6FDAE…`。本审已阅读新增 newest-first 派生逻辑。 |
| 最终报告 | EVIDENCE_CHECK 生成于 2026-10-03 00:15:40，384 条结果均为 PASS，expected/checked=384、failed/skipped=0；外层 final-exit.txt=0。 |
| 两遍检查 | 最新 pass1（00:14:38）与 final（00:15:40）均为 384；检查名称集合无差异。 |
| 日志交付 | 208 份 `.log.txt` 均存在且与 copy_sha256 一致；证据根 568 个文件经只读 Git 检查，无被忽略项。不能将此扩张为原件历史哈希已独立复验，见 R5。 |
| perprocess 去重 | 健康 run `perprocess-20261002-233440-70232` 与 N04 `perprocess-20261003-000311-99168` 均绑定当前 `F9AFF26F…`；各 3 个唯一 PID+创建时间，回收明细均 gone；N04 注入异常后结构化 FAIL/计划退出 1，样本 2。原 r2 的“最新 N04 未重跑”已解决。 |
| 健康 attribution | `attribution-20261002-233528-70552` 绑定当前 `4B260505…`；4 个载荷有同 PID 的 GUARD_ACTIVE→ENTRY_GATE_OK→APP_ENTERED 链；http_api 导入 private 1416.4 MiB。 |
| checker 自测 | 自测报告记录 clean 成功、13 个变异均拒绝且 reason 匹配；mtime 晚于当前 checker 修改，当前 checker canonical 哈希一致。报告本身未嵌自哈希，故这属于现场时间线/哈希交叉支持，不把 mtime 当不可变执行证明。 |
| 旧成果 | entry_gate 已实际接入三主入口；伪回环域名、guard 三模式、环境 helper 的 existed/value、PNG 真实解码、case-6 原因断言已有有效进展，不撤销这些具体成果。 |

## 二、仍需处理的实质问题

### R1 [P1] guard 与 fallback 共同把非回环数字地址放行

位置：`tests/performance/p0_guard/sitecustomize.py:51-64`、`p0_guard/guard_fallback.py:44-57`。

两者用 ASCII 检查后执行十进制 `int(p)`，以首段 127 判断回环，但把原字符串交给底层解析。主审与安全子审分别在安装的 Windows Python 上执行**纯数字解析**：

```text
输入             防护十进制首段   Windows AI_NUMERICHOST 返回
127.0.0.1        127              127.0.0.1
0127.0.0.1       127              87.0.0.1
00127.0.0.1      127              87.0.0.1
```

`socket.getaddrinfo(..., AI_NUMERICHOST)` 不执行 DNS，也不连接目标。该结果证明本机确实存在解析差异，不能继续把它归为纯理论边缘。guard 和 fallback 的相同逻辑会同时放行；不声称本轮已经向这些地址发过请求。

最小关闭：严格拒绝带前导零的 IPv4 八位段，或仅把校验后规范化的地址转交底层；两层与各自回归一起覆盖。测试使用独立桩/纯解析，不向目标发请求。修复后只重跑受影响 guard/门禁用例及相关短验证，不重测产品性能。

### R2 [P1/P2] 全入口隔离与环境恢复并未完成，实施记录的调用方隔离说法不符

`p0_asset_check.ps1:32-48` 启动元数据 Python 只设置 PYTHONPATH，继承调用 PowerShell 的 HOME/USERPROFILE/CWD。baseline `:148`、perprocess `:72` 调用它时，后面为 backend 创建的 ProcessStartInfo 环境尚未使用，也不会追溯影响这个早期子进程。

当前矩阵 case-10 的可交付日志第 5 行直接记录：

```text
[asset-meta] babeldoc 0.6.2, cache_folder=C:\Users\admin\.cache\babeldoc
```

同类日志亦见 case-2/3a/3b/6/8/11/12。BabelDOC const `:42-43` 导入会 mkdir 该 home 的 tiktoken 目录。这足以证明隔离位置错误；不能由此断言本次新增了用户文件或破坏了内容。implementation §1/§4 的“调用方已隔离，因此本轮无写真实 home 路径”结论不成立。

同一 helper `:56-60,85-86` 对缺类别直接 continue，空 file_list 会 total=0 且返回 true；权威清单正常时的 182 项成功日志不能覆盖这种失败路径。

同类恢复尚未接入：asset helper 的 PYTHONPATH 恢复无 finally；PNG helper `:54-68,83-85` 的 finally 只删文件；pytest runner `:75-90` 的 PYTHONPATH/guard/CWD 恢复无统一 finally，runner/conftest 未处理继承 PDF2ZH_CONFIG_FILE。G16 的 helper 9/9 不能替未使用它的调用路径背书。

最小关闭：在这些实际子进程入口隔离环境/CWD，保存和恢复全部修改项，失败路径同样保障；清单解析错误、空清单、必需类别缺失非零。用测试临时根/哨兵证明，不读取真实密钥。此为原“全入口”要求，非扩大产品改动范围。

### R3 [P2] 负向矩阵仍可因错误原因通过，旧 RunId 仍可覆盖

`p0_negative_tests.ps1:55-63` 的泛型 Check 仍仅比较 rc==expected，传入的 reason 字符串被直接写入 CSV，不是 observed reason。case-1/2/3a/3b `:68-92` 只返回进程 ExitCode。于是错误前置条件或无关异常只要退出码相同也可 PASS。

checker `:166-185` 仅对匹配 frozen ID 的行校验固定 reason；这些 legacy 行 frozenId 为空，并不填补语义断言。case-6 的单案修复不能代替泛型执行器。

另外，negative_tests `:24-27` 用 New-Item -Force 接受旧 RunId，后续覆盖哈希、日志和 matrix；attribution `:35,57` 也接受已有 OutDir 并删除旧 JSONL。不能宣称全入口不可覆盖。

最小关闭：每个必需负例机器核对实际阶段/稳定 reason/结果内容和退出码；无关同码失败不得 PASS。RunId 复用要在写任何 run 工件前拒绝。用测试副本/桩做原因错配和目录复用负例，不需要现在重试用户已完成的矩阵。

### R4 [P2] 最新成功与 N04 结果只有计划退出，缺外层退出/部分回收原始证据

最新两个 perprocess run 各只有 backend/guard/样本/result 共 5 件；最新健康 attribution 只有 guard/probe/result/script-hashes 共 4 件。未在证据树找到与这些 run 绑定的外层 stdout/stderr/实际 ExitCode 工件。

perprocess 源码和 result notes 明确 exit_code 是 planned；attribution result 也只记录 planned_exit。`p0_seal_round.ps1:191,205` 却把这些 planned 值直接派生为 coverage 的 actualExit。人工 case_map 的 exit 字段不是独立观测。此项不否认运行、采样、回收代码已执行，只限制“外层实际退出已封存”的宣称。

健康 attribution 的结果还未保存 owned 身份集合/逐项回收；Stop-Tree 只作内存核验。perprocess 身份查询也有边界：`:148-153` 已发现 PID 存在但 CIM 查询失败时，默认状态仍可能为 gone；attribution 同类实现同样把无法确认当成功。应记录 unknown 并使回收验收失败，不能混同于确认退出。

最小关闭：优先寻找仍可核实的外层原始运行工件；不存在则修外层 recorder 后只补必要短运行，明确绑定 PID/run/hash 和实际 ExitCode，不回填历史；保存 attribution 回收身份和结果。计划码、观测码、预期码分别定义。

### R5 [P1，验收可信度] 384/384/0 没有反映 416 次校验错误，也未绑定全部运行来源

最新 `runs/checker-final-std/final-stderr.txt` 长度 **199,056 字节**，含 **416 次** `Test-Path : Illegal characters in path.`。来源均是将 `<preserved-temp-root>/...` 占位串当 Windows 文件路径处理。

`p0_evidence_check.ps1:28` 使用 Continue；`:294,298` 的非终止异常未加失败计数。208 条 copy 哈希检查确实执行且本审也重算通过，但原件相关检查没有正常执行，报告仍 skipped=0/failed=0。不能把“退出 0”描述成无执行错误的完整校验。

此外 checker `:103-108` 只取最新 canonical 哈希表，不逐个绑定被引用 run 的运行时版本；`:231-253` 对 result 主要检查可解析，`:255-272` 主要检查字段类型；REQUIREMENTS 只检查存在、不验证 source 映射和 actualExit 来源，也无要求的最终输入集合 digest。因此 384 是当前代码实际执行的检查数量，不是全部完成条件数。

封存器 `p0_seal_round.ps1:56-69` 对无原件的副本，用当前 copy 哈希再填 original_sha256，并以无法定位的 `<preserved-temp-root>/<basename>` 充当原件位置。当前 208 条均如此。**副本当前完整性已实证；历史原件到副本的双向身份未由此算法证明。** 不应覆盖过去真正采集的原件哈希，缺失时应如实 unknown/removed/disclosed，而不是反推。

最小关闭：明确原件位置/状态模型，占位字段不送文件 API；不适用检查显式登记、文件访问/解析错误计入失败。验证 case→source run→运行时 hash→原始结果/实际退出→coverage 的关联，canonical 只证明当前源码，不替旧 run 背书。生成真实输入集合 digest 和覆盖计数。修封存时保留既有来源事实，禁止把 copy 值推定成独立原件观测。校验器变更后做其本地变异自测与最终只读复验，无需重新跑全部测量。

## 三、非阻断文档与时间线修正

- r2 报告核验的是 375 项、旧 sealer 哈希；当前已变为 384 和 `F0360EAE…`。本报告覆盖该增量，不自动继承 r2 宣告。
- REQUIREMENTS.final_binding.counts 仍为 375；实施记录正文 360/375/21 项混存；HANDOFF 当前入口仍有 360，而最新机器报告为 384/23 项。需统一当前摘要，历史数字保留历史标签。
- INDEX 部分历史 entrygate 目录未标 superseded；不单独作为阻断，不为修这个标签重跑测试。
- perprocess started_at/ended_at 仍是结果对象构建时间而非测量窗口。不能用这两个字段推导启动/采样性能；此次不据此否定样本。
- 自测报告没有自身执行版本哈希，当前由 canonical+mtime 支持；后续增强运行绑定时一并记录，不另开整改项目。

## 四、建议处理方式与边界

将剩余问题合并成三个完整包，不再拆成逐行来回整改：

1. **安全与隔离包（R1/R2）**：严格 IP 解析、实际小子进程隔离和恢复、空清单失败。
2. **运行与判定包（R3/R4）**：错误原因断言、拒绝覆盖、真实外层退出及回收证据。
3. **证据绑定包（R5）**：checker 错误处理、来源/版本/实际结果绑定、原件状态诚实登记、最终文档一致。

不扩大到 WPF/P1，不重做已通过契约、PNG 核心、历史 PDF 或旧正式性能基线。保留已有 run 的有限结论；不把历史未记录信息补写为当时事实。任何下一步实现、本地备份提交或 SDK/P1 操作均等待用户指示，本次审核不包含这些授权。

## 五、关键当前快照

| 文件（tests/performance/ 下） | SHA256 |
|---|---|
| p0_evidence_check.ps1 | `9EA15267F121246AEDDBCD4F004EE0B09894474861D1095C0AD0E04F3F926F14` |
| p0_seal_round.ps1 | `F0360EAE9FCD9CB0EEB4247E4D79455DAFD6974F664C22F60CE32F8663284AE0` |
| p0_probe_perprocess.ps1 | `F9AFF26F6066A6A45FE5C8DF0DF3067EB6AC25DDF1986F2E4A3C9944EF460896` |
| p0_probe_attribution.ps1 | `4B2605058FDFB46664C6DB2EDBFDCC211310EA809767F00B737F9F455A4F724D` |
| p0_negative_tests.ps1 | `3F9E1D48E3DE646195FE1499FB26C5F2CCD9415AED1C5B7EA7F6F3D36A160350` |
| p0_guard/sitecustomize.py | `452F709651D69315E3511C043F2F1DE0BAFDF0E89AD10796F0984A3D3F88BA1D` |
| p0_guard/guard_fallback.py | `FAFF385543FD87832B6290AF3031ACD2C546BD70AC87217C61EF87B643FDE3E6` |

以上针对本次读取快照。当前文件未改动；后续修复须绑定受影响新证据，旧通过结论不自动迁移。
