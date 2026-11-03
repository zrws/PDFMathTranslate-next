# GLM 执行提示词：P0 r2 三个整包整改、受影响复测与最终证据闭环

你继续维护 `D:\paper\PDFMathTranslate-next`。本轮依据 Codex 2026-10-03 终审，完成 R1–R5 及直接同类问题，按三个完整工作包推进。不要只改点名的一行，也不要扩展成产品迁移；把实现、实际调用、负向测试、证据和独立审核在本轮闭环。

## 1. 先读依据与现场，不重启旧完成任务

全部相对路径以项目根为基准。先完整阅读：

1. 用户和目录适用的 AGENTS 指令。
2. `docs/reviews/native-desktop/P0-CODEX-r2-review-2026-10-03.md`：本轮直接整改清单，R1–R5。
3. `docs/reviews/native-desktop/P0-systematic-acceptance-prompt-2026-09-29.md`：原有完整范围与完成条件。
4. `docs/reviews/native-desktop/P0-systematic-acceptance-final-review-20260930-r2.md`：历史审核快照，375 项并非最新状态。
5. `docs/verification/native-desktop/systematic-acceptance-20260930-01/` 下的 REQUIREMENTS、CASE_MANIFEST、INDEX、script-hashes、LOG_COPY_INDEX、最终 checker 工件和本轮相关 run。
6. 当前 STATUS/HANDOFF、实施记录以及本轮涉及的实际入口/helper。

只读核验分支、HEAD、tracked/staged diff、全部未跟踪文件。参考分支 `codex/native-desktop-2026-09-28`，参考 HEAD `b504906769f15a3b048e2336755a2d563b0cb1ae`。现场不同就记录，不重置、不自动切分支。Git 使用单次 `-c safe.directory=D:/paper/PDFMathTranslate-next`，status 显式 `--short --untracked-files=all`。

旧矩阵和 mutation 的完成态已经验证，禁止把旧恢复条目当未完成任务重试。最新已经认可：23 项当前脚本哈希一致、208 份副本当前哈希一致、N04 当前脚本复跑、perprocess 去重及健康 attribution 重跑。保留这些事实，不把有限证据夸大为全部要求通过。

本轮先写 `CHANGE_IMPACT.json`：每条 R1–R5 → 代码位置 → 实际调用者 → 受影响 case → 必须新跑或可复用证据 → 判断理由。旧用例不删，旧结果不改；未受影响且版本绑定充分的成果可复用并注明范围，不要求无差别重跑所有历史测量。guard、共享环境或结果协议改变后，必须复测受影响的实际入口，不能只测 helper。

## 2. 授权范围、红线和分工

允许修复 `tests/performance/` 辅助脚本、测试专用 Python 模块/启动器、结果/证据格式，必要时修 `source/tests/conftest.py` 和相关测试辅助代码；允许在现有实现上小规模提取共用逻辑，补测试和报告。

禁止修改产品业务代码、start-webui.py、launcher/webui、安装更新逻辑、site-packages、真实安装缓存、用户配置/任务历史/导出文件。不实现 WPF/P1，不安装 SDK，不做真实翻译、资源下载、公网或外部 DNS 测试，不改系统/用户级代理、防火墙、环境或全局 Git。

只允许本次拥有的回环桩，以及独立安全门通过后的本次真实后端回环 API；不使用用户的 11178 代理进行防护测试。纯数字地址解析可以使用 AI_NUMERICHOST，但不能真正连接测试外部地址。

不 commit/push/PR/tag/merge/Release，不碰 latest.json。旧证据、旧失败 run、旧审核均保留；不再删除原始日志来避免 Git ignore。可以另存明确的可交付副本，不能覆盖原件或此前脱敏副本。日志不输出密钥，用户和系统数据不纳入无关扫描。

优先复用已有 helper、标准库和已安装依赖，不新造平行框架。本轮不是从零开发产品；若确需超出这个边界的大规模框架重构，先说明复用方案并请求用户决定。用户另行授权的境外调研按 AGENTS 走本地 11178 代理，与离线测试完全分离。

按三个包分工，文件所有权明确，可并行实现：

- A：安全解析、实际子进程隔离和环境恢复（R1/R2）。
- B：原因断言、不可覆盖运行、真实退出/回收证据（R3/R4）。
- C：来源绑定、校验器、封存和文档一致（R5）。

至少一个独立子代理不参与待审实现，负责安全门及最终复审。资源不足可串行；不能让主代理代写“独立审核”。范围内发现问题，内部完成修复→复测→复审，不每改一点就交回用户。只有权限、不可安全处理的冲突或需要用户决策才停。

## 3. A 包：解析与隔离必须覆盖实际调用链

### A1. 消除双层共同误放行

当前 guard/fallback 都按十进制 int 判断首段 127，但 Windows 将 `0127.0.0.1`、`00127.0.0.1` 解析为 `87.0.0.1`。两层会同时放行，这是已在本机用纯数字解析证明的缺口，不是可直接豁免的理论风险。

采用明确策略：优先严格拒绝非规范 IPv4 写法，包括前导零；或仅将经过标准解析和回环判定的规范化地址转交底层。不得“校验一种解释、执行另一种解释”。IPv6/localhost 允许范围也写清，不用字符串前缀推断回环。

回归至少包括：规范 `127.0.0.1`、`::1`、精确 localhost；前导零两例；缩写/整数/十六进制 IPv4；伪回环域名；空值、Unicode 数字、下划线和越界八位段。除明确允许项，其余可直接拒绝，不必为了支持罕见格式增加复杂实现。

测试分别证明 guard 与 fallback 的行为，并证明两者失效时不触及真实外部传输。使用底层桩记录是否被调用；允许路径用本次回环桩。拒绝场景要求准确 reason、来源和本次计数，不以 OS 拒绝或超时算成功。修复后重跑受影响的 guard 三模式、变异/门禁测试，保留默认 Windows 异步调用链。

### A2. 修正“后端环境能隔离早期元数据子进程”的错误假设

baseline/perprocess 调用 Invoke-AssetCheck 时，后面 backend 的 ProcessStartInfo 环境尚未作用于该元数据进程。现有日志明确指向 `C:\Users\admin\.cache\babeldoc`，不能继续宣称调用方已隔离它。

对 metadata、PNG 解码、样本生成、pytest、manifest 以及其他实际 Python 子进程逐个检查：在启动前注入本次 HOME/USERPROFILE/config/cache/CWD/TEMP/PYTHONPATH，处理会改变路径的继承变量；如果某项不适用，记录原因而非套用统一全绿。

优先使用独立子环境，不修改调用者环境。必须临时改父环境/CWD 时，用已有 existed/value helper 并确保整个修改区间有 try/finally。补齐 asset、PNG、pytest 的异常恢复，runner/conftest 明确处理 PDF2ZH_CONFIG_FILE。不要读取真实配置内容验证隔离。

测试采用第二个临时目录模拟外部配置和缓存，记录子进程实际生效路径；包括独立调用 helper 和通过 baseline/perprocess 调用两种场景。日志中出现真实用户目录时不能仍判隔离 PASS。

权威资产校验保留正确的 SHA3 核心，同时保证：元数据不可解析、缺必需类别、空清单、哈希工具失败、缺资源、资源损坏都非零且准确归因。不能 total=0 返回 true。缺失/损坏反例使用完整测试源副本只破坏一个必需项，真实缓存只读。

## 4. B 包：测试判定与运行证据必须来自观察值

### B1. 修泛型 Check，不再把期望文案写成实际原因

修改负向矩阵的通用验收接口，覆盖 case-1/2/3a/3b 和全部同类 case，而不是再加一个单案 if。

每案提供预期条件，runner 从结构化结果或明确机器标记取得实际阶段/原因/结果事实，逐项比较后才判 PASS。expected_reason 和 observed_reason 分开，不能复制前者填后者。

预期成功还要检查有效样本、就绪、必要结果和回收；预期失败要确认失败原因正确。缺结果、解析失败、无关异常即使 ExitCode 恰好匹配也不得通过。

新增同码错因负例：模拟缺前置资源但本案原本期望目标缓存损坏、模拟无关异常但期望 root404、删除实际 reason 字段。所有用本地桩或测试副本，验证通用裁决器拒绝它们。

### B2. 所有运行拒绝覆盖

negative_tests、attribution、guard wrapper、perprocess 与新 recorder 使用唯一 runDir；显式指定已存在 RunId/OutDir 必须在修改其中任何文件前拒绝。不要先删旧 JSONL、覆盖哈希，再报告冲突。

外层 recorder 与被测入口分别使用唯一目录或明确的父子目录：recorder 可以先建自身目录，但传给入口的运行子目录必须尚不存在，避免预建同一目录触发入口的拒绝覆盖规则。

验证拒绝前后旧目录的文件集合/大小/哈希不变。零匹配 `-Only`、空用例集不能返回整体成功。旧失败/中断目录保留并标注，不当作续跑目标。

### B3. 计划、观测、预期退出码三者分开

perprocess 和 attribution 自己写的 exit_code/planned_exit 只是计划值。建立真正的外层 recorder：启动子进程，等待其退出，记录实际 Process.ExitCode、超时/异常状态、stdout/stderr，以及被测 run_id、命令参数和运行时脚本/helper 哈希。

保留原有入口计划码，外层观测码在独立工件中。三者必须一致于用例语义；缺外层观测不能从计划码补成 actualExit。seal/coverage 不再用 planned_exit 当实际退出。

expected/planned/observed exit 均指同一个被测子进程；负向验收 wrapper 自身的退出码另记。例如被测程序预期失败并实际退出 1，而验收器确认失败原因正确后退出 0，这是两个进程的不同语义，不是不一致。

优先寻找已有可证明属于该运行的真实外层记录；没有就保留历史局限，修好 recorder 后只补必要的健康 perprocess、N04、健康 attribution 和相关失败路径。不要给历史 run 回填新的“当时退出码”。

### B4. 回收事实不得由端口或查询失败替代

attribution 保存本次 owned PID+创建时间、回收前集合、逐项回收后状态。perprocess 保留现有去重和身份记录。

状态至少区分：gone、still_alive_same_identity、pid_reused、query_failed/unknown。进程存在但 CIM 查询失败不能默认 gone；查询异常必须使回收验收失败。port_released 独立记录，不能替代进程检查。

用受控桩测试“进程仍活着但端口已关”“身份查询失败”“PID 身份不匹配”这些判定分支，不对用户进程制造故障。真实已知本次进程才能终止，不能扩大为按名称清理。

把 started_at/ended_at 绑定真实运行窗口；结果对象构建时间单独命名。前置失败、主流程异常、超时、清理失败都产出最小可用结果；证据写入失败外层必须非零并给出诊断。

## 5. C 包：证据必须能追溯来源，校验错误必须影响裁决

### C1. 诚实处理原件状态，不再由副本反推历史

当前 208 条 copy 哈希已被独立核实，但 original_sha256 被重新设置为 copy 哈希，并使用 `<preserved-temp-root>` 占位路径，不能当原件历史证明。

区分明确状态：original_present、original_removed_with_recorded_hash、original_unavailable、copy_only_historical。记录真实可定位路径或 null、当时确实观测到的哈希及来源记录、当前副本哈希、复制/脱敏方式和时点。

保留已有真实原件哈希；无法找回的历史原件不得造路径或哈希，也不要求为补历史重新生成日志。允许历史 copy-only 的有限结论，但不能把它用于必须证明原件关系的新证据。

新 run 的封存先记录实际原件哈希，再创建新副本并核验；不删除原件、不覆盖既有副本。封存与只读校验分开。

### C2. 修复 checker 的错误统计与来源校验

不再把占位文本送到 Test-Path。对原件不适用的情况显式记 N/A 及依据，对未知但必需的信息判失败。文件路径非法、读取错误、JSON/CSV 解析错误、Git 命令错误都必须进入结构化失败计数并导致非零，不能靠 ErrorActionPreference=Continue 吞掉。

正常 deprecation 等非失败诊断可以分类保留；不要机械规定所有 stderr 非空都失败，也不能通过抑制 stderr 隐藏校验异常。

canonical 哈希只证明当前源码身份。新增对每条被用于当前验收的 case 的完整核验：

`requirement → case → 选定 source run → 运行时依赖哈希 → 原始结果与外层实际退出 → 观察原因/结果事实 → coverage verdict`

REQUIREMENTS 不是仅检查文件存在。source 必须机器可解析并指向确实检查的 run；每个依赖缺哈希或不匹配必须拒绝/明确仅历史，不能靠选“mtime 最新的一份哈希表”覆盖全树。

历史 run 可以保留不同版本和失败状态，不一律要求匹配当前代码；但只有证明未受影响且依赖身份满足条件的证据才能进入当前验收集合。明确哪些是历史、哪些是 selected current，不能自动回退到旧成功 run 掩盖新失败。

对结果做语义校验而不只是类型检查：外层退出是否真实且匹配、预期原因是否被观察到、样本是否达标、回收是否确认、case 是否缺失、是否发生错误码或 run 引用矛盾。

### C3. 输入集合 digest 与校验器自测

显式定义最终只读验收输入集合，包含要求映射、case manifest、选定 run 的原始结果/实际退出/日志、依赖哈希或可恢复脚本快照、副本索引。按稳定顺序对路径和文件哈希生成 digest。

校验输出及其 stdout/stderr/exit 放独立输出目录，不作为自身输入，避免自引用。若沿用两遍协议，明确每遍输入集合和报告 hash、外层 exit，最终不能只验证一份自行宣称绿色的上一遍摘要。输出过程不得修改输入；最终被审输入变化就重新校验。

checker 自测必须绑定 checker 自身 SHA256、全部依赖、真实外层 exit，不再单凭 mtime 推定执行版本。

保留并复跑受 checker 改动影响的原 13 个变异，再补针对本轮缺口的变异：非法原件路径/状态、原件未知却宣称已核验、source run 缺失、source 运行时 hash 错配、planned 与 observed exit 不符、observed exit 缺失、同码错因、回收 unknown 被标 PASS、选定 run 缺必要工件。

所有变异作用于合成测试副本，不修改真实证据和工作区脚本。干净副本通过，坏副本准确 reason 非零。校验前后输入树哈希不变。明确哪些历史缺失是允许的 N/A，不能为得到零失败把当前 mandatory 缺失也登记成 N/A。

报告计数分别记录 expected、checked、failed、not_applicable、unverified，并给逐项结果；不要以减少分母或隐藏异常制造“384/384/0”。最终条数允许改变，重要的是覆盖全部实际要求。

## 6. 执行与复测顺序

1. 建立本轮 PLAN、CHANGE_IMPACT 和 R1–R5 关闭矩阵，列全部同类实际调用方。
2. 并行实现 A/B/C，先运行纯解析、独立桩、环境哨兵、判定器/校验器变异测试。
3. 独立安全审核 A，核验实际修改的网络路径与子进程隔离；有阻断先修复并复审，不能带风险运行真实后端。
4. 安全通过后执行受影响的 baseline/perprocess/attribution 短验证及必要负向矩阵；每个运行通过外层 recorder 保存实际退出和完整证据。旧完成矩阵不重启，新验证必须是新 run。
5. guard/环境/启动器改动影响 pytest 时，在隔离审核后重跑原测试套件一次；未受影响则保留明确的历史结果标签。不要为了凑“全部当前”重复无关基线。
6. 为原 24 项与 N01–N04 逐项列出本轮新验证或未受影响的有效复用证据。只有有完整绑定和依赖理由的复用可计入；无法证明的 mandatory 必须新跑，不能直接列保留项后通过。
7. 封存后执行当前 checker 自测与最终完整校验，记录真实外层 exit、input digest 和运行版本。
8. 独立最终审核检查完整关闭矩阵和当前依赖，不仅看汇总。范围内问题内部修复、复测、复审；审核后再修改相关代码或输入集合，需更新受影响证据和绑定。

不重跑真实翻译、长文档、GPU 或五分钟正式基线。不因验证层开销变化宣传性能收益。相同实现缺陷在多个入口出现，要一次统一修好，不留“未点名入口例外”。

## 7. 交付、闭环与停止条件

新证据根：`docs/verification/native-desktop/r2-integrated-<唯一轮次>/`。

至少交付：

- PLAN.md、CHANGE_IMPACT.json、REQUIREMENTS.json、CASE_MANIFEST.json。
- runs/<唯一ID>/：输入/命令/参数、依赖身份、result、外层退出记录、stdout/stderr、采样和回收事实。
- COVERAGE.json：每项绑定具体 source run 和原始工件，注明新跑/复用及理由。
- LOG_COPY_INDEX.json：实际原件状态、真实已知哈希及来源、副本身份。
- INPUT_MANIFEST.json：最终输入集合、稳定排序规则和 digest。
- checker 自测与最终校验的机器报告、独立 stdout/stderr/外层 exit。
- INDEX.md：唯一当前入口，历史与当前边界。

新增报告使用 `docs/reviews/native-desktop/P0-r2-integrated-` 前缀，分别写 implementation、safety-review、final-review，并带唯一轮次。独立报告由审核者写，旧报告不覆盖。

同步 STATUS/HANDOFF/REQUIREMENTS：当前数量、版本和结论从机器工件取得，375/360/384 只在相应历史块保留；时间戳是真实事件时间，不能写未来通过结论再倒推证据。对已经丢失的旧退出码/原件关系如实披露，不补造。

最终审核至少确认：

1. 两层都拒绝前导零解析歧义，坏路径不触及外部网络。
2. 小子进程实际路径隔离、环境/CWD 异常恢复、空资产清单非零。
3. 通用负例验收会拒绝同退出码错误原因，旧 RunId 在任何写入前被拒绝。
4. 当前必要运行有外层实际退出、进程身份回收和独立端口观测；unknown 不得通过。
5. checker 不再吞掉执行错误，核验 source/run/hash/result/observed-exit 的关联，最终输入 digest 可重算。
6. 日志原件状态诚实，copy-only 不冒充原件关系证明，旧证据未删除或覆盖。
7. 原 mandatory 和必要新增测试均有有效来源；未满足项没有被自行降级为“保留即可通过”。
8. 独立报告与最终实现、工件、交接文档一致；红线未越界。

最终聊天只汇报三个工作包和 R1–R5 状态、原用例新跑/复用/未验证统计、新增变异统计、独立审核结论、checker 实际 exit 与输入 digest、文件入口、Git HEAD 和红线核对。

范围内连续工作到完成或真实外部阻塞。做不到就明确未完成及阻塞，不伪造完成、不擅改验收标准。完成后停止，等待用户决定本地备份提交或 P1；本轮没有提交、发布和进入 P1 的授权。
