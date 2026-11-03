# 本机计划独立审核（2026-11-03）

审核者：独立子代理 `independent_p0_review`，未参与计划或实现。基线 HEAD `ab5d684df52aa1ec760eb25bc777932003b984b7`，分支 `codex/native-desktop-implementation-2026-11-03`。

仅静态读取本机计划、两份 REMOTE 文件、最新 integrated 安全门和 p0-reference 下 README、PLAN、CHANGE_IMPACT、CASE_MANIFEST，另只读 Git 状态。未执行被审入口、checker、后端、网络、下载或翻译。唯一写入为本报告。

## 裁决

**允许继续静态修复；新轮验收运行前须补齐一项文档前置条件。P0 仍 BLOCKED，P1 未放行。**

计划方向满足交接要求：明确保留 24+4 冻结语义，历史证据不可用且不得继承通过，B1 旧异常不猜因，独立新根和保留失败运行，记录缺依赖为 unverified，checker 非零时不放行 P1。用户本轮已授权功能分支提交与推送，优先于历史参考 PLAN 的禁止提交段；无须重复请求此授权。

## 前置缺项

**P-01：新轮 CASE_MANIFEST 与逐案影响/覆盖映射尚未建立。**

工单 §1 与 p0-reference/README 明确要求先建立并独立审核本电脑新轮计划和用例清单，再运行。当前新增文件仅本机计划；它引用历史清单并承诺保留，但尚无具有本轮 run ID 的实际清单，也没有当前环境中 28 项逐案的执行方式、依赖阻塞与证据位置映射。不能仅把计划中的“完整保留”视作已审核新清单。

最小关闭：在一个唯一新轮根创建本轮 CASE_MANIFEST，保持 `cases` 与 `new_cases_this_round` 的全部 id/description/expected_exit/expected_reason/requires_backend 原样，元数据注明参考源和哈希、本轮 ID、历史工件 unavailable；另建立本轮 CHANGE_IMPACT/覆盖计划，逐项说明本机可运行、前置安全审核后运行或 unverified（包括 I02/I03 虽 requires_backend=false，仍可能缺产品依赖）。新增路径/选择/资产桩测试使用独立编号，不代替冻结 28 项。交独立审核核对后再生成验收运行证据。静态修改可先继续。

## 建议与边界

1. Git 代理应用方式：计划写“单仓库代理”，而工单 §0.5 要求单次 Git/curl 调用配置。端口应使用用户最新指定的 7897；建议取消本轮新增的仓库 `http.proxy` 设置，后续统一 `git -c http.proxy=http://127.0.0.1:7897 …`。不改用户原有配置。
2. EvidenceRoot 应由总驱动显式创建一次并传递；入口的独立默认根可作手工调用后备，但不得导致一个总轮次被分散。缺 Root/无必需 recorder 匹配应失败关闭，不能靠空 foreach 通过。
3. B2/M4 的“已有部分修复”仅是代码现状；关闭需要本机干跑/拒绝覆盖证据及独立实现复审。本计划审核不认可任何代码项已关闭。
4. 无 SDK 情况下仍应完成工单要求的 UI 现状盘点、设计技能应用和本地安装建议；这些可在 P0 阻塞期间开展，但不能替代 WPF 构建、截图、安装包或性能实测。
5. 保留原件 unavailable 的诚实状态。不能解释旧 B1 工件缺失是本机能力边界，不能新造“旧原因”；报告写明旧证据链不可核实并重新建立本轮链即可。

## 冻结语义核对

参考清单包含 G01–G16、P01/P02、M01/M02、I01–I04（24）及 N01–N04（4）。本计划没有更改其期望；没有把新增桩测试冒充真实 backend 基线，也没有把 SDK/Python 依赖缺失降格成通过条件。完整通过仍须新证据、实际 checker exit 0 和独立审核。

## P-01 补件复审

已只读核对 `docs/verification/native-desktop/local-20261103-b1eb9f940d8a/` 的 CASE_MANIFEST、CHANGE_IMPACT、PLAN。对参考及本轮 JSON 解析后分别按 `cases` 与 `new_cases_this_round` 序列序列化作大小写敏感全字段比较：两数组均完全相同，数量 24 与 4。参考清单 SHA256 为 `BA9BF64119ECB3CFFE89139D337B4CD80C223AFDFB5146D4EC7D62FF15F43B31`。本轮只改 runId 并增加 historical_specification_run_id，未改变冻结语义。

CHANGE_IMPACT 覆盖 28 个唯一 id，全部初始 `unverified`、historical_evidence=`unavailable`；G08 单独注明 httpx 缺失，P01/P02/I01–I04/N04 注明锁定 Python/依赖/按需资产缺失，没有拿 requires_backend=false 为 I02/I03 豁免依赖。当前 evidence 根唯一且已明确。仓库 `git config --local --get http.proxy` 无值（exit 1），单次代理处理建议已落实；PLAN 中“单仓库代理”旧句待同步，不影响运行安全。

**P-01 关闭，允许开始计划内纯本地隔离验证。** 此结论仅解除计划清单前置条件；不放行真实后端入口或 P1，不确认任何实现已通过。M01/M02 仍需本轮真实完整证据链与最终 checker 运行，不能用干净合成树的 checker 自测替代。后续覆盖结果必须填写实际来源 run/artifact/hash/退出码；当前通用 verification 描述仅用于未运行计划。
