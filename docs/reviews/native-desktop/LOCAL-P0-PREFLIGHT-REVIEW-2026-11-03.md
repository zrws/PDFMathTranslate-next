# 本机真实入口短验证前定点安全审核（2026-11-03）

审核者：`independent_p0_review`，未参与实现。只读源码、diff、预检工件、哈希，并分别调用 PS 5.1/7 AST Parser；未启动后端、pytest、翻译或下载。唯一写入为本报告。

本审是允许执行受控短验证的安全审核，**不是 P0 整体通过，也不放行 P1**。环境准备由用户另行明确授权；本审不把依赖安装/资源下载记录当作离线测试结果。

## 裁决

**允许当前版本进行 baseline（短 smoke、仅上传自造 PDF/预览）、perprocess、attribution 与隔离 pytest 的受控本地验证。** 条件沿用工单：仅本机回环、无真实翻译/下载、安装运行时只读借用、所有写入在本轮独占根及临时 home、外层 recorder 记录实际退出/身份/参数/双流、结束复核本次拥有的进程。每次新 run 独占目录，不复用失败 run。

初审发现的新生成器缺启动门、pytest 启动前隔离缺口已在审中修复；修复后的专用纯本地负例有效。本轮预检根 `acceptance-local-20261103-39591afa93a3` 包含失败和中途版本工件，仍是诊断根；完整验收须创建新根并重绑当前版本。

## 新变更与审中整改

1. `Invoke-P0PythonFile` 现在通过现有 entry_wrapper 启动，传入当前 sitecustomize SHA256、唯一 run ID、PID 握手，先过 entry_gate 再执行目标脚本。child 的 HOME/USERPROFILE/APPDATA/LOCALAPPDATA/TEMP/TMP/XDG_CACHE_HOME/PDF2ZH_HOME/config/CWD 全在指定隔离根，去除继承 proxy/PDF2ZH/BABELDOC 覆盖，设置 PYTHONNOUSERSITE=1。双流异步排水、有限超时及实际 ExitCode 工件均存在。
2. wrapper 支持 JSON 字符串数组参数，保留旧空格分隔参数的兼容分支；按 utf-8-sig 读取自造脚本，修复 WinPS UTF8 BOM/中文路径问题。baseline 的样本生成现也走上述 helper，不再使用无 guard 的独立启动块。
3. pytest 现在生成 owned bootstrap，由同一 helper 在 Python/site/pytest 导入前隔离；关闭外部插件自动加载，conftest 再提供会话级隔离。只读取 run 内 protected sentinel，结果字段与输出明确不声称真实用户 home 快照；当前代码不扫描用户缓存/历史。
4. `p0_python_child_negtest.ps1` 的有效参数测试与吞 guard 导入错误负例已生成：2/2 PASS，有效 child actual_exit=0，失败 child actual_exit=1，stderr 明确记录受控 sitecustomize 异常与 ENTRY_GATE 拒绝；目标 must-not-exist sentinel 未产生。本审独立重算该 run 的 paths/driver/wrapper/gate/guard **5 项哈希全一致**。参数、HOME/CWD 与禁用户 site 的检查由落盘 payload 工件支撑。

## 既有真实入口封装

baseline 主 backend、perprocess、attribution 保持现有 entry_wrapper→SHA/PID gate→产品导入顺序；HTTP 客户端禁用代理且只请求 127.0.0.1，后端工作/CWD/home/config 独立，继承代理及覆盖被清理。baseline/perprocess 在启动前把本轮准备的资源复制入隔离 home 并做权威 SHA3 与复制一致性预检；缺失/损坏拒绝运行，不触发静默下载。回收针对本次拥有的 PID 树和身份，不按名称终止用户进程。本审未见本次变更引入新的外网或用户目录路径。

`guard-test-current` 的 normal/no_guard/partial 三模式均 passed；mode exit 分别 0/1/1，normal fallback hits=0。entrygate 为 5/5、mutations 为 clean+4/4、empty-host probe exit=1，符合冻结拒绝语义。核心 guard/fallback/test/gate 哈希本审重算仍一致；wrapper/paths/checker 后续有改动，故这些工件不能冒称“全部依赖绑定当前”。最终根需重跑/绑定相关短项，外层实际退出证据必须持久化。

isolation 首轮 PNG/中文路径失败完整保留；r2 矩阵 13/13 PASS。它证明资产清单和 PNG 小子进程隔离的具体行为；新的 helper gate 又有上述专用负例。未将首轮失败覆盖成通过。

## M01/M02 两遍闭环

首遍仅对尚不存在的 M01/M02 coverage 行明确记 N/A，不豁免其他冻结项；sealer 只有取得真实 prior report PASS、observed actual exit 0 和 report hash 才派生 M01/M02。Final 强制要求该 prior report 与外层观测、报告哈希、当前 checker 版本、同一 checked_root、PID/entry/command/无 timeout。缺 prior 的第 25 个变异已产生非零并 reason 匹配的报告。

预检根中的 checker selftest 报告为 clean=true、25/25 变异拒绝且 reason 匹配；但在本审建议增加“同一根/进程身份”核对后 checker 哈希又变化，**该报告不再绑定最终 checker**。本项不阻止安全短跑；最终验收前必须以冻结后的 checker 新跑自测和真实两遍闭环，不能沿用这份中途报告。

## 身份与范围

本审快照：

| 文件 | SHA256 |
|---|---|
| p0_paths.ps1 | 755ED7648F87C50C6F2798C30B42CB1A3B7DBA96B2BFEF7FBB5AB99FA81EFB21 |
| entry_wrapper.py | E93B996F5710ECB386AC1D317652F9396FAB657C754EE84C6E26FA249B9BA691 |
| p0_baseline.ps1 | 417FF986E1DA0B3BE702D28BF2540CF05819B136F5F38ABDEF5428D3936BF2A1 |
| p0_pytest_isolated.ps1 | EB1FA82005FCE89E6EDBB7A74390B963EAC4291CA9D364512ED33DFBFD1A51A1 |
| p0_evidence_check.ps1 | A5B73F70ED83A96F403923249965A20F458B96E089571D76812F6AAEEF582665 |
| p0_seal_round.ps1 | 2A2AEA8CE914F0A9D9F41E25F415BC4DF5B0CF031A232E1902C5744BEB0ABEB2 |

Windows PowerShell 5.1.26100.9711 与 PowerShell 7.6.5 均解析当前 31 个 PS 脚本：0 语法错误。尚无本审认可的真实后端结果、完整 pytest、最终 checker exit 0、完整冻结 24+4 coverage、WPF 或安装/性能结果。真实入口发生新失败时保留原件并按影响修复/重跑，不能以本安全放行替代后续验收。

非阻断文档项：pytest runner 文件头仍保留旧“real-home protection/real dirs”历史注释，建议同步为 owned sentinel；当前机器字段与用户可见运行输出已经纠正。
