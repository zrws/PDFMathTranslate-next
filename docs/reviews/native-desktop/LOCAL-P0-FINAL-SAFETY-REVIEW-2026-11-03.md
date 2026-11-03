# 本机 P0 安全门独立终审（2026-11-03）

审核者：`independent_p0_review`，未参与实现。执行方负责运行，本审只读源码、原始工件、Git/哈希与语法；没有重跑被审入口、checker、后端、pytest、翻译或下载。唯一写入为本报告。

## 裁决

**本机 P0 安全门通过，允许进入 P1 实施。** 本结论基于本轮真实测试、PowerShell 7 补充封存的最终 checker 实际退出 0，以及本审独立逐文件和逐案核验。

严格区分两个事实：原 `p0_acceptance.ps1` 自动总驱动因混合 PowerShell UTF-8 解码问题，在 seal-1-derive **退出 1**；这个失败及 stderr 完整保留。随后 `p0_finalize.ps1` 在明确的 PowerShell 7.6.5 环境，以同版本 sealer/checker 和真实独立子进程完成全套两遍封存，**补充封存外层实际 0、最终 checker 实际 0**。不得把结论写成“原自动总驱动全程退出 0”。

这是本机可访问的完整安全证据结论；约 600 MB 真实字体测试夹具仍只保留本地，不得整根提交 Git。可推送的小体积证据轮另行以冻结代码和新根生成，不把本轮身份冒充新哈希。P1 与该轮并行时须使用独立冻结 checkout/worktree，避免代码、端口、配置和资源互相干扰；性能测量串行。

## 证据与版本

唯一当前本机安全证据根：`docs/verification/native-desktop/p0-final-r2-20261103-31098db1916f/`。

- 原始测试冻结提交：`5ca85cb96c8eed44aeef6812df217181abd25e86`；CASE_MANIFEST 的 24 个 cases 与 4 个 new_cases，独立解析后按全字段及顺序与参考清单比较完全相同，仅本轮 runId/历史 runId 元数据改变。
- 补充封存：`4419c8f` 新增 finalize 驱动。源码原字节副本位于该根 `runs/finalize-be4d463347a94909bb30d02c9363c0d8/source.ps1`；本审核 live source、副本、FINALIZATION 记录 SHA256 三者一致。新增 FINALIZATION 和源码副本在输入摘要生成前写入，没有更改原始 case 观测。
- checker：`762AFE5CD518D19147B1EE40BBF804A47FFC4AEFEF6E1C535AEA0FA77EEB13C1`。
- 最终 `EVIDENCE_CHECK.json` SHA256：`97293818BC77191B61191DF7C9728CEA1DA7D0010662774AA428766A0905B6F3`；与 `reports/checker-final.json` 字节一致。
- prior report SHA256：`A0F8BB611F7808DB2CA9532C5F345D0A015AAECF26032DC2544837586233EE60`，与外层实际退出记录绑定一致。
- INPUT_MANIFEST 文件 SHA256：`94D66A1A1E086E004DCD8E79395DF75C7D92DFFC471CE7633DA8C64DC538BD20`；内容 digest：`CCB396F17DF3C83AA7960DE82A84C555620EAE9A7D92E4EE1BC4AEA535FA01B6`。

## 独立复算

1. INPUT_MANIFEST **1412 项全部逐文件重算 SHA256/大小，0 缺失、0 越根、0 失配**，按声明序列独立重算 digest 相同；这包括本机可访问的全部大体积测试夹具。
2. 全部 root/run script-hashes 表 **202 项绑定重算，0 漂移**。没有靠最新 canonical 表替代逐 run 运行版本。
3. COVERAGE **28/28**：每个冻结 id 恰有一行，verdict PASS、observed exit 与冻结期望逐案一致、reason 一致。未用旧电脑缺失证据补通过。
4. **158 份日志副本**当前哈希一致；**119 份可访问原件**重算一致（114 original_present、5 original_present_at_temp_root）。37 copy-only 与 2 original_unavailable 保持有限结论，不反推原件哈希、不把未知原件说成核过。
5. checker selftest clean 和 Git ! 例外 clean 均通过，**26/26 变异实际非零拒绝且 reason 匹配**，自测 checker/依赖版本与冻结代码一致。当前根 pyc 数量 **0**。
6. 最终 checker 独立 pwsh 子进程 PID **15132**，启动 `20:11:20.667 +08:00`，actual_exit **0**、timeout=false、process_exited=true；FINALIZATION 外层记录 actual_exit **0**，完成 `20:11:29.569 +08:00`。prior 同样实际 0，报告 hash/同根/当前版本/调用身份均绑定。

机器计数原样为 expected=945、checked=706、failed=0、unverified=0、not_applicable=37、skipped=0。差额 202 是手动哈希分支增加 expected/结果但未增加 checked 的计数口径；本审已独立重算这 202 项，没有未执行的哈希或缺案。不得缩写成“945/945 PASS”。

## 关键真实结果

- 完整负矩阵 **23/23 PASS**，23 个实际退出均符合各自预期，recorder 实际 0、无超时、外层 stderr 0。case8 本轮为 DONE failures=0、sentinelUnchanged=True；旧轮该案失败与定向回归保留，未覆盖。
- perprocess 健康/N04 的 recorder 实际退出分别 **0/1**，各 2 个真实样本，guard active、blocked=0、端口释放、三个 owned 身份逐项 gone；N04 明确为注入异常，原因和实际非零一致。
- attribution 健康实际 **0**：四 payload、四份原始 batch 与聚合一致，共 12 行身份/all_gone。import-fail 实际 **1**：按源码是三个 import payload，三 batch、捕获时 0 身份行；不将这一有限记录描述成健康模式的四 payload/12 身份证明。
- baseline 短 smoke 实际 **0**：自造 PDF 上传、API/root 200、12 个有效预览样本、空闲短采样和 owned 树回收；明确从未提交翻译。
- 隔离 pytest **100 passed、74 warnings、实际 0**；protected owned sentinel 无变化、读取错误 0、网络 guard 零 outbound。没有声称对真实用户目录做了快照。
- guard 三模式、入口门、变异、严格数字地址/loopback、环境恢复、恢复分类与清理、资产 metadata/缺失/损坏/hash 子进程失败均有当前绑定本地证据。

## 非阻断限制与后续要求

- 原自动总驱动跨宿主解码未通过；本机安全结论限于已验证的 PS7 补充封存。后续交付轮应固定顶层宿主或统一显式 UTF-8 读取，再独立验收。
- 原矩阵第 17 行包含逗号而未正确 CSV 引用，frozenId 列会错位；N01 由 guard/vector 的直接证据独立证明，最终 coverage 不是依赖该错列补造。后续修正规范 CSV 写入及读取，不改本轮 raw CSV。
- perprocess 内层 started_at 在结束后创建、ended_at 被 writer 覆盖，约 36 ms 的内层差值不是运行窗口；本轮生命周期由外层 recorder 真实时间/身份与原始样本支撑，不用这些错误内层字段推导性能。后续修复并重跑受影响条目。
- 计数口径、夹具外置与便携证据是交付轮事项。原件、失败根和本轮输入摘要均保留；不得回填旧哈希或宣称旧证据随新提交发生变化。
- 本次没有验收 WPF 产品、资源占用改善、安装包/安装卸载/更新流程或真实翻译质量。P1 必须继续完成工单全部要求、构建/实际 UI 截图/测试/资源对比/安装验证及独立终审，不能把本安全门当成最终产品交付通过。
