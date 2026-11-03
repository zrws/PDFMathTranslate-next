# 本机 P0 局部整改独立复审 R2（2026-11-03）

审核者：`independent_p0_review`，未参与实现。复审基线仍为交接提交 `ab5d684df52aa1ec760eb25bc777932003b984b7` 加当前冻结 diff。

证据根：`docs/verification/native-desktop/local-20261103-185155-62b09e4302734fcb96a99f734ef6003b/`。此根的身份是 **LOCAL REMEDIATION PROOF**，不是完整 P0 acceptance；旧诊断根保留，未继承任何历史通过结论。

## 裁决

**初审 F-01 关闭；F-02 的静态修复和局部回归绑定已完成。本次局部整改范围未发现新的阻断。P0 整体仍 BLOCKED，P1 未放行。**

允许继续环境准备和下一阶段受控验证，不得把此结论替代 24+4 冻结用例验收。锁定运行时、依赖和离线资产准备好后，应先补当前 guard 三模式、entrygate/mutation/隔离等尚缺用例；安全审核确认相关条件后，才能在全新 acceptance 根运行真实后端短 smoke/perprocess/attribution/pytest。最终 checker 实际 exit 0 及独立终审仍是 P1 前置条件。

## 独立核验方法

只读冻结源码、diff、本轮工件；独立重算所有本轮 `script-hashes.json` 条目、checker dependency_hashes 和 LOCAL_RESULTS 所列脚本身份，共 **132 项绑定，0 失配**。checker 自身 SHA256 另核一致。对最终合成封存树逐文件重算 12 项哈希与 digest，0 漂移。

分别在 Windows PowerShell **5.1.26100.9711** 与 PowerShell **7.6.5** 调用 AST Parser，当前 **30 个 PS 脚本语法全部通过**。没有执行被审驱动、checker、后端、翻译、网络或下载；唯一写入为本复审报告。运行结果由主代理执行，本审独立核实工件和绑定，不冒称本审重新执行过这些入口。

## F-01：重封存自引用与 INDEX 顺序

已确认 sealer 先生成 INDEX，再枚举输入；`INPUT_MANIFEST.json` 按自引用理由显式排除，不删除旧原件。`seal-fixtures/results.json` 两遍均 recorded exit 0，no_drift/digest_matches/index_included/self_excluded 均 true；两份 stdout/stderr 由外层保留。

本审对第二遍完成后的合成树独立复算：manifest 12 项、0 失配，digest 一致，INDEX 恰有 1 项，manifest 自身 0 项。第一遍的即时哈希结果采信受当前源码哈希约束的驱动落盘记录；没有把第二遍工件描述为第一遍不可变原件。F-01 关闭。

## F-02：路径、布局、判定与新证据

| 范围 | 本次复审结论 |
|---|---|
| Python 路径传播 | baseline/perprocess 使用 Resolve-P0Python，不再强制存在 uv-python；asset/isolation/矩阵合成 case 调用点转发实际 PythonExe，后端依赖树仍独立预检并失败关闭。产品依赖真实导入尚未验证。 |
| B2/M4 与含空格路径 | routing 8/8：三种 recorder 布局、缺 result 拒绝、矩阵排除 selftest/reuse/partial、baseline recorder 空格路径、attribution/perprocess 已有空目录拒绝且零写入。PathOnly 明确不是 baseline 成功。 |
| M1 精确语义 | checker 按覆盖行 source 精确匹配 recorder→entry-run→result；P01/P02 共用有样本/回收字段的语义块，N04/I01/I02/I03 缺匹配不静默略过。新增 p02-without-recorded-run 实际被拒，reason=missing_semantic_run。 |
| M2/I04 | selector 要求 acceptance identity、无 Only、实际 matrix 文件，并排除 selftest/reuse；checker 对 I04 要求精确 source、实际 recorder 与完整 PASS 矩阵。新增污染变异被拒，reason=missing_semantic_run。routing 另覆盖名称/identity/partial 的排除。 |
| PS7→WinPS5.1 | 子启动仅在创建窗口调整进程级 PSModulePath，finally 恢复后再等待；固定 Windows PowerShell 可执行路径，并在短子进程退出前保留 Handle 以取得实际 ExitCode。LOCAL_RESULTS 的八个成功退出与故意失败退出均非 null，不用 planned 替代 actual。 |
| checker | clean_pass=true；24 个变异的实际退出均非零，rejected/reason_matched 全 true；含原 22 项及本轮 P02/I04 两项。checker 自测子进程采用共享启动器，stdout/stderr 分别保留。 |

LOCAL_RESULTS 共 **9/9** 结果符合预期：8 个 observed exit 0，`incomplete-gate-rejected` observed exit **1**；9 项 stderr_empty 均 true，启动参数、PID/启动时间、脚本哈希与清理说明均存在。完整 P0 checker 在此不完整树上的报告为 **FAIL**，记录 failed=18；该失败是“缺证据应拒绝”的验证，绝不是 P0 通过。

## B1/M5/R1 局部证据

- `runs/recovery-proof/matrix.csv`：**8/8 PASS**，包括 still_alive_same_identity、pid_reused、query_failed 和 cleanup；4 个 stub 日志非空且 tag 与文件逐一匹配。entry driver/恢复 helper/路径 helper 哈希都在本审重算范围内。旧原电脑 B1 缺失工件仍不可用，没有推断其成因。
- `runs/asset-manifest-5d26bd8c537e44378ed3503fed21720d/`：**7/7 PASS**，valid=0，其余六项拒绝=4且 reason 匹配；hash 失败真实 Python 子进程输出 exit=23，stderr 约 128 KiB 工件存在，双流异步排水已核源码。这里使用合成清单/标准库哈希，不代表真实 BabelDOC 资产已通过。
- loopback 仅标准库数值解析/谓词桩，旧严格地址校验仍在。env 恢复与矩阵判定器 selftest 有当前绑定证据。它们不替代缺 httpx 时尚未执行的完整 guard 三模式/真实 backend 链。

## 冻结身份与后续边界

| 文件 | SHA256 |
|---|---|
| p0_paths.ps1 | B0A85D870FF04AAA92705E56CD876165BECB966BB11C73AD4CEB777778FF94C0 |
| p0_runs.ps1 | 99EEAEDFDCBB1F8CD8D58B538337E004197A4C4A50B3B45A3EFFA261DE333789 |
| p0_evidence_check.ps1 | 94451FDF7FE4D06B31BF895756A070FB7D71E03F76EF7F5CD8D35C2692656783 |
| p0_seal_round.ps1 | 66A40318F7F4D66CE476BDB6350BEDD3A0C21824A6EF35C58EDDBE2891F27D0A |
| p0_local_smoke.ps1 | 以本轮根 script-hashes.json 的当前匹配项为准（已计入 132 项独立绑定） |

本轮未审或未验证：锁定 Python/BabelDOC 实际运行、资产真实完整性、受影响完整 pytest、24+4 完整覆盖、性能/体积、WPF Debug/Release/截图、安装卸载与更新链实测。用户后续授权创建本机运行环境不改变这些事实；新准备工作和新代码/依赖应使用新证据与必要复审，不覆盖本轮局部工件。
