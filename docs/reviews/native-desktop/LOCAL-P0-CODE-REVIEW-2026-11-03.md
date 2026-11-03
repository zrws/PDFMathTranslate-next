# 本机 P0 修复独立初审（2026-11-03）

审核者：`independent_p0_review`，未参与实现。基线 `ab5d684df52aa1ec760eb25bc777932003b984b7`。主代理在审查期间按发现修改代码；本报告区分初始发现、审中静态修复与尚未绑定新证据，不把中途快照当最终验收。

方法：只读 diff、源码、本轮工件，独立重算哈希和矩阵数量；在 Windows PowerShell 5.1.26100.9711 与 PowerShell 7.6.5 分别调用 AST Parser，28 个当时已存在的 PS 脚本全部语法通过（此后新增 routing 脚本须补解析）。未执行被审入口、checker、后端、翻译、网络或下载；唯一写入为独立审核报告。

## 裁决

**部分修复成立，P0 整体仍 BLOCKED，P1 不放行。** B1 当前证据完整；B2/M4 原交接已有部分修复，本轮加强了路径与拒绝覆盖；M1/M2/M3/M5 有实质实现。仍需修复下述封存缺陷、完成审中修复后的新回归与复审。没有真实后端、依赖、模型、pytest、新性能基线或 WPF/安装证据，不能据局部桩测试宣称整体完成。

## 待关闭发现

### F-01（MAJOR）：seal 重封存把旧 INPUT_MANIFEST 及旧 INDEX 纳入哈希后又覆盖

位置：`p0_seal_round.ps1` 的 INPUT_MANIFEST 枚举/写入段与随后 INDEX 生成段。

枚举排除列表仅含 EVIDENCE_CHECK、reports、checker-output，没有排除 `INPUT_MANIFEST.json`。首遍文件不存在可写成；第二遍会将旧 manifest 的 SHA256 列入 entries，再重写该文件。checker 逐文件哈希核对必然失败。INDEX 又在输入清单之后写入：首遍漏记该输入，第二遍先登记旧内容后覆盖。M01/M02 两遍绑定和 COVERAGE 更新需要可重封存，不能靠删旧工件绕过。

最小关闭：显式排除 manifest 自身并登记自引用理由；先生成 INDEX，再枚举输入；用纯本地合成树连续封存两遍并独立重算每项哈希与 digest，保留两次外层退出。合成树仅证明封存机制，不得作为真实 P0 coverage。

### F-02（证据前置）：审中修复尚需当前版本新证据

以下初审发现已告知主代理，并在后续静态读取看见修复；尚未完成冻结后的工件绑定复审：

| 初审发现 | 审中静态修复 | 所需短验证 |
|---|---|---|
| baseline/perprocess 新增 PythonExe 参数未用；Invoke-AssetCheck 多调用点未转发实际解释器 | 改 Resolve-P0Python 并转发；移除 uv-python 目录为必需条件 | 显式解释器、无 uv-python 但有受控 fixture，确认实际子命令/缺依赖 fail-closed |
| checker 精确匹配漏 P02；I04 不核对 acceptance identity/实际 recorder | P01/P02 共用语义块；I04 使用 Get-P0MatrixRuns 且要求 observation | 缺匹配、错误 source、自测矩阵污染、缺实际 observation 变异必须非零并带准确 reason |
| checker 自测直接 powershell.exe，仍继承 PS7 module path | 改 Start-P0PowerShell，输出分别落盘 | 在 PS7 父进程调用自测，clean 为零、所有变异非零且 reason 匹配 |
| canonical 索引未含 p0_paths/p0_runs/新增 driver | 补索引 | 新 canonical + 相关运行时哈希与冻结源码一致 |

本轮诊断根保留中途失败、旧版本哈希和故意损坏的 checker 自测树。checker 当前递归校验全部工件，并且 Get-P0RecordedRuns 会因任一同类型 recorder 缺 result 而拒绝；故此根不能被当成最终绿灯根。后续应明确记录诊断根仍 BLOCKED；冻结代码后使用独立验收根、重跑受影响必要项，或设计明确 selected/superseded 规则并验证。保留旧工件，不删除、不回填旧 hash。

## 已核实的局部结果

- **B1**：`runs/recorder-recovery-final/entry-run/matrix.csv` 恰为 8 条且 8 PASS，包含 still_alive_same_identity、pid_reused、query_failed 和 cleanup；4 个 stub 日志均存在且非空；外层 entry-stderr 为 0 字节，observed 实际 exit 0、timeout=false、outer_exception 为空，记录父 PowerShell PID/启动身份/argument_vector。entry-run 的 recovery driver、recovery_funcs、paths 三项哈希独立重算均一致。旧原电脑工件不可用，无法解释旧缺失原因；本轮失败试验保留，未补造旧证据。
- **M5 行为**：`runs/asset-manifest-781f512c70824b0cbfaf896262c933c7/matrix.csv` 7/7 PASS，覆盖 valid、损坏元数据、空清单、缺类别、hash tool failure、缺文件、错误 hash。hash failure 输出实际 `exit=23`，独立检查保存的 stderr 文件 131077 字节（131072 个 x 加 UTF-8/换行封装），代码先异步排水双流再等待，属于真实 Python 失败子进程。该轮 helper hash 一致，但 paths/driver 已在其后变化，不能绑定当前最终实现；需新 run。
- **R3 自测**：`matrix-selftest-local-v1` 的 ST1/ST5 PASS 与 ST2/ST3/ST4 故意 FAIL 符合判定器证明目的；它是 selftest identity，不能被算 I04。多个依赖已变化，旧轮仅保留历史结论。
- **R1 回归机制**：两层严格规范数字地址规则仍在；guard_test 的前导零改为谓词断言，消除了两层同时失效时请求真实 87.0.0.1 的风险，loopback_vectors 为谓词/底层桩，不作为真实外联证明。
- **路径**：RepoRoot 按脚本目录推导，InstallRoot 默认当前仓库 `.local/runtime`，EvidenceRoot 独立轮次；矩阵向子驱动传 RepoRoot/InstallRoot/EvidenceRoot/PythonExe，env-only 特例只传支持参数。活动默认路径没有再指向原 `D:\paper`；seal_evidence 的旧路径字符串仍用于历史日志脱敏，不是写入目标。
- **PowerShell 互操作**：Start-P0PowerShell 只在创建子进程的短窗口替换进程级 PSModulePath，finally 恢复，等待在恢复后执行；不写 User/Machine 环境。ConvertTo-P0Argument 处理空格、引号及尾反斜杠；recorder 保存参数向量，仍需 routing 真实短运行证明。

## 本审快照身份

| 文件 | 审中读取的 SHA256 |
|---|---|
| p0_paths.ps1 | EE0E0CA950BBBA3AF70FAF6882DA369142DE93F2737C25B2E58CC7D9AEF8A2A2 |
| p0_runs.ps1 | 99EEAEDFDCBB1F8CD8D58B538337E004197A4C4A50B3B45A3EFFA261DE333789 |
| p0_evidence_check.ps1 | 94451FDF7FE4D06B31BF895756A070FB7D71E03F76EF7F5CD8D35C2692656783 |
| p0_seal_round.ps1 | 62006F7C8719C931A42A98A11EB2B2CAF74E1B6032B91A9816DDE8E84942E336 |

这些是审中快照，不是最终 commit 绑定。修复后必须再审，不自动继承本表或旧 22 项 checker 自测报告的通过。
