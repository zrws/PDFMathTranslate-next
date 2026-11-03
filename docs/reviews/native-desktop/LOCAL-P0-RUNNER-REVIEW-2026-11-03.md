# 最终 P0 受控验收总驱动安全审核（2026-11-03）

审核者：`independent_p0_review`，未参与实现。只读新 runner、10de84f/bd7ff46/a6500c9 与审中修复 64bbf97 的差异、既有封装及计划根；哈希重算与 AST 解析。未执行总驱动、backend、pytest、翻译或下载。唯一写入为本报告。

## 结论

**允许执行 p0_acceptance.ps1 当前版本的完整受控 P0 验收。** 不代表本次验收已经通过，不放行 P1。此前已审核的 raw 测试安全设计不重做；本审针对新编排、参数、超时回收、证据轮次和两遍闭环。

计划根为 `docs/verification/native-desktop/p0-final-20261103-1825693180a9`。独立核实时最初不存在；主代理按审中条件修复 Driver 后已经启动。本审未将运行中的 guard 单项成功扩张为完整结果。任何失败停止总驱动并保留根，不准复用/补写成新运行；修复后应以影响范围和新的独占根继续。

## 核验事项

- 参数：InstallRoot/PythonExe 必传，RepoRoot 自动发现；EvidenceRoot 标准化并在存在时拒绝。公共参数传给支持这些参数的子驱动，env-only/checker/sealer 按其签名单独传参。Driver 与 Recorded 均逐项 Windows quoting，不借用自动 `$args`，观测实际 ExitCode，不以 expected/planned 代替。
- 编排：先本地 guard/entrygate/mutation/empty-host/loopback/isolation/asset/recovery/env，再 recorder 管理的 perprocess 健康/N04、attribution 健康/失败、baseline 短 smoke，之后隔离 pytest 与全量负矩阵。无真实翻译、安装、下载、发布或系统环境写入入口。
- Driver 原超时只 Kill 根进程的问题已在 **64bbf97** 修复：只对本次仍存活的 owned child PID 使用 taskkill /T /F，等待后记录 timeout/cleanup/实际状态，再抛失败；不按名称杀进程。Recorded 使用既有 recorder 的树回收与实际观察工件，缺入口目录/非期望退出即失败。
- 两遍：每次 Seal 用新的 `seal-N-derive`/`seal-N-bind` 日志名，不覆盖先前 stdout/stderr。先 derive、写 REQUIREMENTS、再 bind，使最终 digest 包括机器派生要求。首遍 M01/M02 仅明确 N/A；真实 checker 首遍成功之后才写 prior observation（PID/entry/command/实际 exit/报告 hash）。再次 Seal 后 Final 强制检查 prior、同根、当前 checker、哈希、身份与真实退出。Final 报告和 EVIDENCE_CHECK 属排除的输出，不造成输入自引用。
- canonical 已包含 `p0_acceptance.ps1`，最终 checker 可核总驱动源码哈希。CASE_MANIFEST 仅把 runId 改成本轮并保存 historical_specification_run_id；本审解析比较参考及已创建清单：24 个 cases、4 个 new_cases 的全字段与顺序完全相同。
- bd7ff46 把重复资源 cache、pytest home 放到本轮 owned 唯一 TEMP，保留小记录及 temp 引用，不读用户历史/home/cache，也不删除旧工件。.gitignore 仅对 evidence 子树放行 raw .log，未放行模型/cache/.local；最终仍须独立检查大文件和敏感数据。
- 10de84f 的环境锁/显式在线准备脚本与离线总驱动分离；总驱动不调用在线准备。该提交只动测试、构建辅助、锁和文档，截止 64bbf97，`source`/`launcher`/`start-webui.py` 相对交接基线无修改。

32 个当时已存在 PS 脚本在 Windows PowerShell 5.1.26100.9711 和 PowerShell 7.6.5 AST 解析均 0 语法错误；随后 64bbf97 的小段超时/元数据改动已静态逐行核对。超时分支本审未实际触发，不声称已有其运行证明。

## 审核快照

| 文件 | SHA256 |
|---|---|
| p0_acceptance.ps1 | 44FCE834857689CB242A4C4BDA0D886F8F20664D17C56F4FA094728A4B859A86 |
| p0_seal_round.ps1 | BF4B0FA900BA92C81B61EC77ED0DD50EEE27E224B8A2ACFCD4F2FDC90ECA30A6 |
| p0_evidence_check.ps1 | A5B73F70ED83A96F403923249965A20F458B96E089571D76812F6AAEEF582665 |

剩余验收责任：逐案当前证据、哈希/外层退出/清理、最终 checker 真实 0、最终输入 digest、独立终审。旧诊断矩阵/性能/pytest 的历史成功仅解释准备状态，不计入本次完整通过。
