# P0 r2-integrated 轮独立安全复审（gate）— r2-integrated-20261003-01

- 复审人角色：独立安全门（gate），未参与任何实现。
- 依据：`docs/reviews/native-desktop/P0-CODEX-r2-review-2026-10-03.md`（R1–R5 权威清单）、`docs/verification/native-desktop/r2-integrated-20261003-01/PLAN.md`、`CHANGE_IMPACT.json`。
- 本审唯一写动作：本报告文件。未修改实现、证据或 Git 状态。

## 0) 范围与方法

- **方法**：纯静态审计 + 证据工件核验。逐行审读 R1–R5 涉及的全部代码文件；对 `runs/` 下本轮纯本地证据做内容核验（矩阵行数与行名、退出码工件、机器工件字段、`script-hashes.json` 与当前文件 SHA256 重算对照、工件内部一致性）。**未执行**任何被审脚本、checker、矩阵、后端、pytest、翻译或下载；未发起任何网络连接（未重复 r2 审的数字解析探测，采信其 87.0.0.1 实测事实并核对本轮 `os-numeric-parse.txt` 工件）。
- **基线核验**：HEAD = `b504906769f15a3b048e2336755a2d563b0cb1ae`（分支 `codex/native-desktop-2026-09-28`，无新提交）；`git diff --stat HEAD` 为空 → **零 tracked 修改**；本轮全部新增为 untracked 测试与证据文件。
- **哈希重算**：loopback-vectors 4/4、guard-test-r1 8/8（guard 相关项；其中 `p0_evidence_check.ps1` 记录为旧 checker 哈希属预期时间线，checker v5 在其后改写）、isolation-sentinel（最新一次）4/4、matrix-selftest-2（negative_tests 驱动）绑定、checker-selftest（checker + 3 依赖）4/4 —— 均与当前文件一致。发现的不一致项单独列入 Findings。

## 1) R1–R5 逐项结论表

| # | 审计项 | 结论 | 关键证据指针 |
|---|---|---|---|
| R1-a | `p0_guard/sitecustomize.py` `_is_loopback` / `guard_fallback.py` `_is_loopback_strict` 严格解析 | **PASS** | 两层谓词逐字对称：空/None/异常一律 False（fail-closed）；仅 `::1`、精确 `localhost`（lower/strip 后）、**4 段 ASCII 数字**八位组（`any(ch not in "0123456789")` 封闭 PEP-515/Unicode 数字洞）、`len(p)>1 and startswith("0")` 拒绝 `01/001/0127`、≤255、首段 127 才放行。被放行的 dotted-quad 全部为无前导零的规范十进制形式——该形式在十进制与"0 前缀八进制"两种 OS 解析下取值相同，且放行后传给 OS 的就是被验证的原字符串 → **不存在 validate-decimal-but-pass-original 洞**；其余一切形式（`127.1`、整数、hex、5 段、`::ffff:127.0.0.1` 等）均被拒。 |
| R1-b | `loopback_vectors.py` + `p0_loopback_negtest.ps1` + 证据 | **PASS** | 20 向量覆盖两层谓词（含 `0127/00127`、`LOCALHOST`、Unicode `０`、`0_0`、越界段）；bottom stub 包装 fallback 捕获的真原函数（guard 层保存的 original 即 fallback 包装，再下一层才是 OS 入口），`bottom_stub_calls=0` 为硬断言。证据 `runs/loopback-vectors-20261003-094828-63396/`：`vectors-result.json` 20/20、failed=0、`vectors-exit.txt`=0、`os-numeric-parse.txt` 实测 `0127.0.0.1 -> 87.0.0.1`（仅 AI_NUMERICHOST，无 DNS/连接，探测子进程 PYTHONPATH 指向 site-packages 故 guard 未加载，记录的是 OS 真行为）、script-hashes 4/4 绑定当前。OutDir 非空拒绝覆盖。 |
| R1-c | `guard_test.py` leading_zero 子测 + `p0_c1_guard_test.ps1` 必查子项 + 证据 | **PASS** | `leading_zero_octet_blocked` / `leading_zero_long_blocked` 为 normal 模式 required-subitems（缺项即模式失败）；每个子测断言 rejected + `source=guard` + 新增匹配 BLOCKED 日志 + fallback 命中 0。证据 `runs/guard-test-r1/`：summary 3/3 模式 PASS（normal exit=0 blocked=9 fbHits=0；no_guard exit=1 三项全 fallback；partial exit=1 sync=guard/async=fallback），`normal/testResults.json` 含两个 leading_zero 子测 `passed:true, source:guard, new_fallback_hits:0`。 |
| R2-a | `p0_asset_check.ps1` 隔离 + 失败路径 | **PASS** | `-IsolatedHome` Mandatory；不存在即拒（isolation_required）。`New-AssetChild` 每子进程 `ProcessStartInfo` 独立环境块：HOME/USERPROFILE/PDF2ZH_HOME→isoRoot、APPDATA/LOCALAPPDATA/TEMP/TMP/XDG_CACHE_HOME/PDF2ZH_CONFIG_FILE（iso 内新空配置）/CWD（isoWork）/PYTHONPATH；strip 继承的 `PDF2ZH_*`/`BABELDOC_*`/`*_PROXY`（白名单外）。元数据子进程 stdout/stderr 均 `ReadToEndAsync()` 先于 `WaitForExit`（管道死锁规避），180s 超时 Kill→`metadata_timeout`。失败路径全部 `return $false` 且带精确 reason：`metadata_failed`/`metadata_unparseable`/`isolation_violation`（cache_folder 或 HOME 越出 isoRoot、或命中真实 USERPROFILE 前缀）/`missing_category`/`empty_manifest`（totalListed=0）/`asset_missing`/`asset_corrupt`/`hash_tool_failed`（超时/退出码/输出不可解析/error 字段）。`assetcheck-meta.json` 机器工件（cache_folder/effective_home/isolated_root）。 |
| R2-b | `p0_guard/png_check.ps1` 子进程隔离 | **PASS** | `Set-PngPythonExe` 无 `-IsolatedHome` 直接 throw；`Test-PngStrict` 未配置即 `$false`（fail-closed）。临时 PNG/py 全在 isoRoot/pngcheck-tmp；每子进程环境块（HOME/USERPROFILE/APPDATA/LOCALAPPDATA/TEMP/TMP/XDG_CACHE_HOME）；stdout 异步读先于 WaitForExit；finally 删临时文件；**无任何父进程 env 变更**。 |
| R2-c | `p0_baseline.ps1` 样本子进程 / Invoke-AssetCheck / Set-PngPythonExe 调用点 | **PASS（调用点）**但该文件存在独立缺陷 → **FINDING B2** | 样本生成子进程为 per-child `ProcessStartInfo` 环境块（HOME…PDF2ZH_CONFIG_FILE/PYTHONPATH/CWD=workDir，无父 env 变更，未重定向即无死锁面）；`:148` `Invoke-AssetCheck … -IsolatedHome $home0`；`:241` `Set-PngPythonExe … -IsolatedHome $home0`。但 `:39` 的 `-OutDir` 参数被 `:108` 的 `$outDir = Join-Path …systematic-acceptance-20260930-01\runs\baseline` 无条件覆盖（PowerShell 变量名不区分大小写，同一变量）→ 参数死亡，见 B2。 |
| R2-d | `p0_probe_perprocess.ps1` / `source/tests/conftest.py` / `p0_pytest_isolated.ps1` / `p0_manifest.ps1` | **PASS** | perprocess `:75` `Invoke-AssetCheck … -IsolatedHome $home0`；backend 子进程 per-child 环境块 + strip。conftest：`PDF2ZH_HOME`/HOME/USERPROFILE/APPDATA/LOCALAPPDATA/XDG_CACHE_HOME/TEMP/TMP 全部重定向、`PDF2ZH_CONFIG_FILE` 强制指向隔离内新空配置、chdir 隔离 work、`pytest_configure` 自检打印（泄漏时打 `[FAIL]` 行）。产品侧优先级核实：`start-webui.py:57` `PDF2ZH_CONFIG_FILE` 环境变量优先于 home 派生路径、`:34` `PDF2ZH_HOME` 覆盖 `_resolve_home`；`const.py:8` `~/.config/pdf2zh`（expanduser 走 USERPROFILE/HOME）、`translator/cache.py:103` `Path.home()`——conftest/runner 双重防护下**真实 home 路径无法胜出**；runner 还在启动前 `Remove-Item Env:PDF2ZH_CONFIG_FILE` 清除继承值。`p0_pytest_isolated.ps1`：全部受管 env（含 PDF2ZH_CONFIG_FILE 的 existed/value）统一 try/finally 恢复；快照 read-error 记录且 exit 6；real-home 变化 exit 5。`p0_manifest.ps1`：Git env（GIT_CONFIG_COUNT/KEY_0/VALUE_0）+ PYTHONPATH 在 finally 恢复。 |
| R2-e | isolation-sentinel 证据矩阵 | **PASS** | `runs/isolation-sentinel-20261003-100530-30468/`（最新，script-hashes 4/4 绑定当前）：matrix.csv **9/9 PASS**——standalone 通过（total=182 verified=182）、**machine artifact** `iso-home/assetcheck-tmp/assetcheck-meta.json` 的 cache_folder 与 effective_home 均在 isoRoot 内、子输出无真实 USERPROFILE、空缓存→`asset_missing`、损坏→`asset_corrupt`（SHA3-256 MISMATCH）、不存在 IsolatedHome→拒、PNG 经隔离子进程解码、iso 内临时工件存在、existed/value 恢复。 |
| R2-f | 承诺的资产清单失败负例集 | **GAP → FINDING M5** | CHANGE_IMPACT R2 must_rerun 承诺的 `p0_asset_manifest_negtest.ps1`（garbled metadata / empty file_list / missing category / hash tool fail）**不存在**；上述四路径仅为静态代码核验，无机器证据。 |
| R3-a | `p0_negative_tests.ps1` 判定引擎 | **PASS** | `Invoke-Case` 以 expectedExit + expectedReason 机器 token 断言：observed reason 从用例自身工件提取，`reason_not_observed` / 工件缺失或空（`<reason-artifact-missing>`/`<reason-artifact-empty>`）→ FAIL；同码错因（ST2）、缺工件（ST3）、码不符（ST4）均 FAIL。运行后全依赖哈希漂移检查（drift→exit 1）。 |
| R3-b | RunId/目录复用拒绝 | **PASS** | 驱动：`matrix-<RunId>` 非空即 exit 2，先于任何写（script-hashes 也在其后）；`-Only` 零匹配 exit 1。perprocess：`result.json` 预存在 exit 2。ST5 以子进程真实复跑证明拒绝 + sentinel 前后计数/哈希不变（`matrix-selftest-2/selftest-stubs/reuse-run.err` 记录拒绝行）。 |
| R3-c | `p0_probe_attribution.ps1` OutDir 复用 | **FAIL → FINDING M4** | `:35` `New-Item -Force` 仍接受既有 OutDir；`:57` `Remove-Item $outFile` 仍删除既有 `probe-attribution.jsonl`；script-hashes/recovery/result 同样被覆盖。r2 清单 R3 明列 "attribution OutDir handling"，未实现拒绝语义（受制裁调用路径恒为新目录，实际风险为操作员显式复用）。 |
| R3-d | 判定器自测证据 | **PASS** | `runs/matrix-selftest-2/cases/matrix.csv`（绑定当前驱动哈希）：ST1 PASS、ST5 PASS、ST2/ST3/ST4 FAIL——精确匹配引擎期望模式；`matrix-selftest-1` 为旧版驱动的历史运行（已被 -2 取代）。 |
| R4-a | `p0_run_recorder.ps1` | **PASS** | 只创建自己的 RecorderDir（非空拒 exit 2）；entry-run 预存在拒 exit 2（recorder 从不代 entry 建目录，entry 的拒覆盖语义保持完整）；记录 `Process.ExitCode`（observed，非 entry 自报）；超时仅按 `ParentProcessId = childPid` 枚举 + taskkill /T + Kill($p)——**父子 PID 关系，无按名杀**（childPid 尚存活时枚举其子，PID 复用误伤面极小）；stdout/stderr 文件重定向无管道死锁面；observed.json 绑定 entry + 共享依赖运行时哈希。 |
| R4-b | perprocess 窗口时间 + 回收语义 | **PASS** | `started_at`=真实窗口起点、`ended_at`=finally 回收后、`result_built_at` 单列；回收状态机 gone / still_alive_same_identity（失败验收）/ pid_reused（记录不失败）/ **query_failed（CIM 查询失败→失败验收，绝不静默当 gone）**；owned 集跨源去重（pid+created）；`fallback_hits='not_deployed'` 如实标注而非伪 0。 |
| R4-c | attribution 回收持久化 | **PASS** | `recovery.json` 持久化 owned identities + 每身份 post_status（含 query_failed→`hadFailure=1`）；写失败也计失败。 |
| R4-d | `p0_recovery_funcs.ps1` + `p0_recovery_negtest.ps1`（代码） | **PASS** | 共享单源（含 test-only seam `-CimLookup`）；语义与真实入口一致；桩仅 taskkill 自己创建的测试 python PID（先记录、杀后复核清理，`cleanup` 行断言零残留）；无用户进程触碰、无按名杀。 |
| R4-e | recovery-stubs 证据 | **FAIL → FINDING B1** | `runs/recovery-stubs-20261003-095743-99304/matrix.csv` 与其自身 `script-hashes.json` 绑定的当前脚本**内部不一致**（详见 B1）。 |
| R5-a | `p0_seal_round.ps1` v2 诚实原件状态 | **PASS** | 四状态模型：`original_present`（真路径+哈希）/ `original_present_at_temp_root`（由 run result.json 的 temp_root 解析，Test-Path 实证后记真哈希）/ `original_unavailable`（tempRoot 知道但原件不在 → `original=$null`、`original_sha256=$null`，注释明示"NEVER re-stamp the copy hash"）/ `copy_only_historical`；**占位字符串不再进入任何文件 API**；原件不删、副本不覆盖；INPUT_MANIFEST 稳定序 + 逐文件 sha256 + digest，checker 输出（EVIDENCE_CHECK.json/reports/checker-output）以理由排除；canonical 哈希索引含 conftest.py。 |
| R5-b | seal COVERAGE 派生布局 | **FAIL → FINDING M1/M2** | observed exit 确实只取 recorder `observed.json`（无绑定时记 `unverified` → 下游 FAIL，绝不用 planned 冒充）✓；但 §2d/2e/2f 的目录扫描与 recorder 实际布局互斥（M1），§2g 会被自测目录劫持（M2）。 |
| R5-c | `p0_evidence_check.ps1` v5 守卫包装 / 语义 / 计数 | **PASS** | 全部文件 API 经守卫包装：`path_illegal`/`read_error`/`parse_error`/`hash-read read_error`/`git_check_error`（git 命令错误≠不忽略）全部计入 failed 且退出非零——r2 的 416 次吞噬类问题在机制上关闭；逐 run script-hashes 全条目解析+比对（unresolved/drift FAIL，无 skip）；COVERAGE 溯源（缺案 FAIL、`unverified` 既计数又 FAIL、recorder actual_exit 与行值一致性、reason 与清单相等）；LOG_COPY honest 状态强制（`original_state_lie`/`unknown_original_claimed_verified`/未知状态 FAIL；声明 unsanitized 但哈希不等 FAIL）；INDEX 反引号链接死链 FAIL；result.json 空文件 FAIL、run_id 重复 FAIL；perprocess 语义（`query_failed` 行存在即 FAIL、fallback 伪 0 拒绝）；`-Only` 零匹配 FAIL；计数拆分 expected/checked/failed/not_applicable/unverified；`-Final` 要求 EVIDENCE_CHECK.json 交付物。 |
| R5-d | checker 自测证据 | **PASS** | `runs/checker-selftest-report.json`：clean_pass=true、**mutation_count=22、all_mutations_rejected=true、22/22 reason_matched=true**（13 承接 + 9 新增，含 path_illegal / unknown_original_claimed_verified / missing_source_run / hash_drift / planned_observed_mismatch / unverified_observation / wrong_reason / recovery_query_failed / missing_mandatory_case）；`checker_sha256=362E…` 与当前 checker 重算一致，依赖哈希（p0_env/p0_seal_round/p0_run_recorder）亦逐一重算一致——解决了 r2 指出的"自测报告未绑定自身执行版本"。 |

另注：本轮证据根当前仅 `PLAN.md` + `CHANGE_IMPACT.json` + `runs/`（CASE_MANIFEST/COVERAGE/LOG_COPY_INDEX/INPUT_MANIFEST/INDEX/REQUIREMENTS 尚未生成，属封存步骤 7 的产物）——与计划时序一致，无伪造交付物。

## 2) Findings

### BLOCKER

**B1 — recovery-stubs 证据工件与哈希绑定的脚本内部不一致（R4 证据无效）**
- 位置：`docs/verification/native-desktop/r2-integrated-20261003-01/runs/recovery-stubs-20261003-095743-99304/`（`matrix.csv`、`script-hashes.json`）对照 `tests/performance/p0_recovery_negtest.ps1`。
- 事实：该 run 的 `script-hashes.json` 记录的 `p0_recovery_negtest.ps1`/`p0_recovery_funcs.ps1` 哈希**与当前文件逐字节一致**（脚本 mtime 09:54:56 早于 run 09:57:43，时序自洽），当前脚本含 **8** 个 `Check`（L60/61/65/83/84/98/99 + cleanup），但证据 matrix.csv 仅有 **5** 行；缺失的三行恰好是三个**状态分类断言**——L61 `still_alive_same_identity`、L83 `pid_reused`、L98 `query_failed`（即 R4 回收语义的核心证明），留下的 5 行只覆盖 all_gone 极性与清理。同时 `New-StubPython` 经 `Start-Process -RedirectStandardOutput` 必然落盘的 4 个 `stub-*.txt` 文件**全部不存在**。无论成因（运行后工件被改/部分删除，或执行路径与所记哈希不符），该工件都无法证明当前脚本的行为。
- 为什么阻断：本 gate 的职责之一是认可本轮纯本地证据；一个与其绑定哈希自相矛盾的证据工件不可采信，且其缺失的正是"query_failed 失败验收 / pid_reused 记录"的机器证明。R4 代码本身静态正确（R4-d PASS），但**证据必须重跑补齐**（纯本地、秒级成本）并说明该工件成因。
- 最小关闭：以当前脚本重跑 `p0_recovery_negtest.ps1` 至新目录，产出完整 8 行 matrix + 4 个 stub 日志；保留旧目录不删（如实留档）；如无法解释不一致，视为证据链缺陷升级处理。

**B2 — `p0_baseline.ps1` 的 `-OutDir` 参数死亡（PowerShell 变量大小写不敏感覆盖），将使放行后的真实入口 baseline 复跑证据错位且浪费**
- 位置：`tests/performance/p0_baseline.ps1:39`（param `[string]$OutDir = ''`）与 `:108`（`$outDir = Join-Path $RepoRoot "docs\…\systematic-acceptance-20260930-01\runs\baseline"`）。
- 事实：`$OutDir` 与 `$outDir` 为同一变量（PS 变量名不区分大小写），`:108` 无条件覆盖命令行传入值（对比：perprocess/attribution/pytest/isolation/recovery/loopback 均为 `if (-not $OutDir)` 条件默认）。recorder 以 `-EntryOutDirArgName OutDir` 传入 `<RecorderDir>\entry-run` 时，baseline 将**静默忽略**它：证据物理落入**上轮历史证据根**（违反 PLAN 红线"上轮证据根保持历史，不复用、不改写；本轮证据根为唯一当前入口"）、`entry-run` 永不创建（observed.json 将如实记 `entry_run_dir_exists=false`）、seal §2f（~L253，扫 `runs\baseline\run-v3-*` 于**本轮根**）派生不到 I01 → checker `missing_coverage_case` FAIL。CHANGE_IMPACT R4 明列 "baseline short smoke via recorder (NEW run)" 为必须复跑项；按现代码放行即**浪费一次真实入口运行**且污染历史根。
- 最小关闭：将 `:108` 改为 `if (-not $OutDir) { … }` 模式（与其它驱动一致），并把默认根改指本轮证据根；修复后只需纯本地核验参数生效（无需真实运行即可静态+一次干跑确认 runDir 落点）。

### MAJOR

**M1 — seal §2d/2e/2f 与 checker 语义块的目录布局假设同 recorder 实际布局互斥：P01/P02/N04/I02/I03/I01 无法按现代码完成覆盖绑定**
- 位置：`p0_seal_round.ps1:216/237/253-256/262`；`p0_evidence_check.ps1:318/336/352/377/392`（语义块同样只扫 `runs\perprocess-*`/`attribution-*`/`baseline`）。
- 事实：recorder 把入口证据写入 `runs\recorder-*\entry-run\`，且 `observed.json` 的 `entry_run_dir` 即该路径；而 seal/checker 扫描 `runs\perprocess-*`、`runs\attribution-*`、`runs\baseline\run-v3-*` 并以**同一路径**为键查询 observed 映射。不存在任何调用配置能同时满足"result.json 位于被扫目录"与"该目录恰为 recorder 键"（entry-run 目录名固定，永不为 `perprocess-*`）。后果：recorder 驱动的复跑要么在 COVERAGE 缺行（checker FAIL），要么永远 `unverified`。checker 语义块在无匹配目录时**静默不产生任何 Check 行**（foreach 空转），这是又一处"检查消失"面。
- 为什么重要：这是 R4/R5 复跑-封存链路的结构性断点；好在派生可重算，**不浪费真实运行**，但必须在封存前修复（建议 seal/checker 直接扫描 `runs\recorder-*\entry-run`，或让 recorder 把 entry-run 落在被扫命名下）。
- 备注：`p0_baseline.ps1` 修好 B2 后，`<RecorderDir>\entry-run\run-v3-*` 仍不匹配 §2f 的 `runs\baseline\run-v3-*` —— B2 修复必须与 M1 一并设计落点。

**M2 — seal §2g "最新 matrix" 选择被自测目录劫持：`matrix-selftest-2` 按序必排最后，I04 将绑定到含故意 FAIL 行的自测矩阵**
- 位置：`p0_seal_round.ps1:262-270`（`-Filter 'matrix-*'` + `Sort-Object Name` + `Select-Object -Last 1`）。
- 事实：`matrix-<时间戳>-<pid>` 与 `matrix-selftest-2` 比较，第 8 个字符 `'2' < 's'`（序数），故任何时间戳目录都排在 selftest 之前，`Select-Object -Last 1` 恒取 **matrix-selftest-2**；其 ST2/ST3/ST4 为引擎证明用的故意 FAIL 行 → `$mxFail>0` → I04 恒 FAIL。复跑真实全量矩阵也无法纠正选择。
- 最小关闭：`-Exclude 'matrix-selftest-*'`（并排除 reuse-probe），或要求行数 ≥ 真实用例数（`$mxRows.Count -ge 19` 已有但选择在先）。

**M3 — 四个子驱动 + attribution 默认输出仍指向上轮历史根；post-gate 全量矩阵复跑会把子证据写进历史根并使 G04/G05/G14/G15/G16/N02/G12 无法从本轮根派生**
- 位置：`p0_entry_gate_negtest.ps1:41`、`p0_env_negtest.ps1:21`、`p0_guard_mutations.ps1:26`、`p0_empty_host_case.ps1:23`（默认均 `systematic-acceptance-20260930-01\runs\…`）；`p0_probe_attribution.ps1:21-23`（默认旧根，矩阵 case-1 不带 -OutDir 调用即触发）；另 `p0_c1_guard_test.ps1`、`p0_pytest_isolated.ps1` 默认亦为旧根（有显式 -OutDir 时不触发）。
- 事实：CHANGE_IMPACT 明列 post-gate 需重跑 "guard mutations (rerun)"、"entrygate negatives (rerun)"；负矩阵 case-15a-d/16 不带参数调用这些子驱动 → 证据落历史根；seal §2b/2c/2b-3/2b-2 只扫**本轮根**的 `entrygate-*`/`env-restore-*`/`mutations-*`/`empty-host-*` → 对应冻结用例在 COVERAGE 缺行。矩阵自身的 cases/matrix.csv 可满足 checker 的 mandatory coverage（frozenId 列），但 COVERAGE 派生仍会缺。旧根污染不可逆（文件一旦落入历史根，要么污染留档要么事后搬移=证据洗牌）。
- 最小关闭：把这 4 个默认路径改指本轮根（或统一 `-EvidenceRoot` 注入），与 R1/R2/R4 三个新驱动的做法对齐；改完是纯本地重跑，代价小。

**M4 — `p0_probe_attribution.ps1` 仍未实现 OutDir 复用拒绝（r2 R3 明列项）**
- 位置：`p0_probe_attribution.ps1:35`（`New-Item -Force` 接受既有 OutDir）、`:57`（`Remove-Item $outFile` 删除既有 JSONL）。
- 事实：r2 审 R3 原文指出 attribution `:35,57` 接受既有 OutDir 并删除旧 JSONL，最小关闭为"RunId 复用要在写任何 run 工件前拒绝"；当前代码未加任何拒绝（perprocess 加了 result.json 预存在检查，attribution 没有）。受制裁路径（recorder entry-run 恒新、默认目录时间戳+PID）不触发，实际暴露面为操作员显式复用已存在目录——但该关闭项被明确授权且未交付。
- 最小关闭：与 perprocess 对齐——写任何工件前 `result.json`/`probe-attribution.jsonl` 预存在即 exit 2。

**M5 — 承诺的资产清单失败负例集（`p0_asset_manifest_negtest.ps1`）未交付，四个失败路径无机器证据**
- 位置：CHANGE_IMPACT R2 must_rerun（"garbled metadata / empty file_list / missing category / hash tool fail … all non-zero, precise reason"）；对照 `tests/performance/`（该文件不存在）与 `p0_isolation_negtest.ps1`（仅覆盖 empty→asset_missing、corrupt→asset_corrupt）。
- 事实：`metadata_unparseable`/`empty_manifest`/`missing_category`/`hash_tool_failed` 的提前返回 `$false` 分支已静态核验存在且语义正确，但本轮无任何机器证据驱动它们。严格口径下"代码正确"与"已被证明拒绝"必须区分。
- 最小关闭：补一个纯本地负例驱动（伪造 manifest 不可行时可用 seam/子进程桩注入），或如实把该项从本轮完成条件中降级并记录为未验证路径。

### MINOR

- **m1** — `p0_guard/guard_test.py:369-379`：leading-zero 探测目标 `0127.0.0.1` 在**两层同时失效**的残余情形下会把 connect 交给 OS 解析为 `87.0.0.1:9`（真实 RIPE 地址，非 RFC5737 文档段；对比其余探测用 192.0.2.1）。本轮证据中 guard 均在第一层拒绝（source=guard、BLOCKED 匹配），未发生任何外联；建议后续改用可映射到文档段的等价向量或仅谓词级断言。
- **m2** — `p0_loopback_negtest.ps1:44-56`：`PDF2ZH_VECTORS_PATH` 设置于 try 内但不在 `Set-ChildEnvBlock` 保存清单中，驱动进程内泄漏至退出（独立子进程运行时无外溢）。
- **m3** — `p0_asset_check.ps1` hash 子进程与 `png_check.ps1` 解码子进程仅异步读 stdout，stderr 重定向未排水：>4KB stderr 会撑满管道直至 60s 超时 Kill（fail-closed 为 `hash_tool_failed`/'decode check timed out'，无安全影响，但与元数据子进程的双流异步不一致）。
- **m4** — `p0_negative_tests.ps1` matrix.csv 字段未加引号，observed reason 若含逗号会使后续按 `,` 拆列错位（当前 reason 提取白名单基本无逗号，seal/checker 拆列受影响面小）。
- **m5** — `p0_asset_check.ps1`：`assetcheck-meta.json` 写失败仅 warn 不置败（下游哨兵/检查器依赖该工件存在，缺失会在下游暴露；建议置败或至少计入 reason）。
- **m6** — `p0_probe_perprocess.ps1` 复用拒绝仅检查 `result.json`：无 result.json 的旧目录会向既有 `probe-pp.jsonl` 追加（比 M4 轻，因拒绝语义已存在大半）。
- **m7** — `p0_baseline.ps1` 末尾父 env 恢复块为死代码（本版未在父进程改这两项）；无害但易误读。
- **m8** — `p0_run_recorder.ps1` `Start-Process -ArgumentList` 拼接不处理含空格参数（当前实参均无空格）；`actual_exit` 超时态为字符串 `'timeout'` 与整数混用（语义已可判别）。

## 3) 红线核查

| 红线 | 结果 |
|---|---|
| `git status --short --untracked-files=all` 零 tracked 修改 | **PASS** —— `[MADRC]` 前缀条目计数 = 0；`git diff --stat HEAD` 为空。全部条目为 `??` untracked（tests/performance、docs/verification、source/tests/conftest.py）。`build/patches/babeldoc/0001-assets-upstream-env.patch` 为 2026-09-28 历史文件（mtime 证实非本轮新增）。 |
| `git log -n 1` HEAD = `b504906769f15a3b048e2336755a2d563b0cb1ae`，无新提交 | **PASS** —— log 前三为 `b504906`/`8d23931`/`99013fe`，与授权基线一致。 |
| 产品/start-webui.py/launcher/webui/site-packages/安装树/用户数据零改动 | **PASS** —— 零 tracked 修改下不可能有产品改动；untracked 新增仅测试与证据（conftest.py 为 PLAN 授权的 R2 文件、只影响 pytest 会话不影响产品运行）；对安装树 `D:\paper\pdf2zh-install-test` 全部为只读借用（robocopy 源、python/site-packages 只读执行）；本轮驱动写入面 = repo 证据目录 + %TEMP% 隔离根。 |
| 代码路径无网络（仅回环 + 受控拒绝） | **PASS** —— 全量扫描 `tests/performance`：HTTP 仅 `127.0.0.1:$Port`；受控拒绝目标为 `192.0.2.1:9`（RFC5737 文档段）与 `0127/00127`（双层拒绝，见 m1 残余注记）、伪域名（guard 谓词先拒）；os 探测仅 AI_NUMERICHOST（无 DNS/连接）；guard_test 的 `loopback_allowed` 为本机真实监听器回环。 |
| 无真实翻译 | **PASS** —— baseline 仅上传自造 PDF + preview 渲染（render-only），从不调用翻译入口；perprocess/attribution/pytest/负矩阵均无翻译提交。 |
| 不改系统/用户环境 | **PASS** —— 全部 env 操作为进程级（`Set-Item Env:` / `[Environment]::…'Process'` / per-child ProcessStartInfo），无 Machine/User 作用域写入。 |
| 历史证据根不被复用/改写 | **PASS（截至今日本轮未写入）** —— 旧根最新 baseline run 为 20261002（早于本轮起点）；本轮证据全部落在新根 `runs/`。**但按现代码放行复跑即会破坏此红线**（B2/M3 正是其前置条件）。 |

## 4) 裁决

### **BLOCKED —— 不放行真实入口复跑（gate 未通过）**

R1 与 R2 的**安全语义本身（网络封闭、子进程隔离、失败路径置败）代码正确且证据充分**，红线状态干净；阻断项全部集中在**证据完整性与复跑机械的路由/布局**，均为小改动、纯本地可验证，不需要重做任何安全设计。

**放行前置条件（按序）：**

1. **[B2]** 修复 `p0_baseline.ps1:108` 的 `-OutDir` 死参数（改条件默认 + 默认根改指本轮根），静态核验 runDir 落点 —— 否则 recorder 驱动的 baseline 复跑必然错位并浪费一次真实运行。
2. **[B1]** 以当前脚本重跑 `p0_recovery_negtest.ps1`（纯本地）产出完整 8 行矩阵 + 4 个 stub 日志至新目录，并说明 `recovery-stubs-20261003-095743-99304` 工件 5/8 行、缺 stub 文件、哈希却绑定当前脚本的成因（旧目录保留不删）。
3. **[M1/M2]** 修正 seal §2d/2e/2f/2g（及 checker 对应语义块）与 recorder `entry-run` 布局的绑定，排除 `matrix-selftest-*` 对 I04 选择的劫持 —— 封存前必须完成（可复算，不浪费真实运行，但需在封存步骤前落地）。
4. **[M3]** 将 entrygate/env/mutations/empty-host 四个驱动的默认输出根改为本轮根（矩阵 case-15a-d/16 将随之归位），否则 post-gate 矩阵复跑污染历史根。
5. **[M4/M5]** attribution 复用拒绝补齐；资产清单失败负例集补齐或如实降级登记为未验证路径。

完成 1、2（安全门最小集）并给出 3、4 的修复提交后，可仅针对上述差异做快速复审（无需重审 R1/R2 已通过项）即可放行真实入口复跑；5 可与复跑并行关闭。m1–m8 不阻断，建议随上述修复顺手处理 m1/m3/m5。

---

*审计快照：2026-10-03，HEAD `b504906`，零 tracked 修改。本报告为本审唯一写动作。*
