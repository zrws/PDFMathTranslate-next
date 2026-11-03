# P1 定点整改独立复审 R2（2026-11-03）

## 本轮结论

**B01–B05 的主要结构性整改已读到对应实现，允许继续隔离验证；本报告不授予整个 P1 通过。** 审核期间代码仍在变动，本报告属于中间定点复审，不能代替最终冻结提交、机器运行证据和交付审核。

独立审核者没有参与实现，只读源码、既有工件和本机文件哈希；没有启动被审入口、测试、翻译、下载或 UI 自动化，没有修改原证据，仅新增本报告。与初审相同，安装/卸载、Debug/Release 交付、性能/包体、旧入口与更新链兼容、OS 输入/DPI 等完整工单验收仍属后续范围。

主仓库 HEAD 仍为 `080262216d6a405519097d30b90f09a1ffdb130a`，产品代码大部分未提交。以下读取约在北京时间 21:43–21:59，哈希表记录其中 21:58 的读取快照，不代表这些文件均来自 HEAD，也不代表运行中证据全部绑定该快照。

## B01–B05 的整改核对

| 初审项 | 已读到的整改 | 当前裁决 |
| --- | --- | --- |
| B01 工作进程排水/启动监督 | stdout collector 用真实 EOF 设置 drained；父循环同时等待进程退出、排水完成和队列清空；协议 null 仅表示进度通道结束并收口 stdin；启动输入独立线程，取消/关闭事件与满队列 put 均可结束；Future 观察异常并通过 Store.fail 产生可见失败；120 秒准备、300 秒静默、30 秒结束边界 | 结构已整改；仍需最终版本运行和两项新增顺序回归的真实结果 |
| B02 retry/export 端到端幂等 | OperationOutbox 用 kind+endpoint+payload 指纹绑定持久 UUID；原子写入、128 项上限；发送成功且待办完成写盘后才移除；重启/手工恢复重用同键；明确新导出才生成新键 | 主要代码问题已整改；需新版 WPF 丢响应恢复成功轮 |
| B03 原配置快照 | 入队保存完整非密钥 SettingsModel、配置指纹；术语复制到 owned 内容寻址路径并记录 size/SHA256；retry 重建原快照，凭据单独从当前对应服务注入；公开 task 去除原始 settings_snapshot/credential_fields，独立 configuration 仍不含凭据 | 结构已整改；本轮发现的 DeepL 漏剥离已补，见下文 |
| B04 跨存储设置一致性 | 单个 WPF PUT 携带设置和保存目录；设置锁包围提交/任务快照；私有 prepared journal 写旧 TOML 字节和 prefs，失败回滚、启动恢复；prepared 未完成时阻止后续覆盖；committed 清理失败不再误报未保存 | 结构已整改；新增故障边界须随最终测试闭合 |
| B05 导出锁外 IO | 单独 Exports RLock 管理导出操作；Store 锁仅保护短意图提交/回滚；复制、fsync、文件 hash 和最终文件重验在 Store 大锁外 | 原全局锁问题已整改；已有可控慢复制回归，Windows/慢盘实际响应仍需最终验收 |

已新增的 Engine 两项回归是 `test_engine_drains_finish_even_when_child_exits_before_collector` 和 `test_engine_cancel_interrupts_blocked_boot_stdin_and_queue_continues`。前者让 fake child 先报告退出，再延后读取 finish；后者让 fake child 初始 stdin 阻塞，取消后验证下一任务继续。测试场景对应原风险，**但 fake child 验证不等于 Windows 实进程树回收验收**；本审核未执行这些测试。

## 复审中发现并即时反馈的附加问题

下列问题均已发给实现者。后续只读已看到对应修复，暂按“代码已整改、最终证据待核”记录；不把本轮更早的失败或更早的测试结果改写为这些新字节已通过。

1. **真实 DeepL 凭据漏剥离。** 原 SECRET 正则不匹配 `deepl_auth_key`，会将它写入私有任务配置与原 public/SSE。本轮已改为使用真实模型 `GUI_PASSWORD_FIELDS` 加敏感名称匹配；新增遍历全部真实密码字段、主/术语两个嵌套分区的剥离断言。该问题属于凭据边界阻断，最终必须核实际测试及历史/事件无 sentinel，不可仅以一个 OpenAI 假模型测试代替。
2. **迟到旧操作删除新待办。** 原 Outbox.Complete 仅按 Identity 删除；并发恢复旧 A、显式新导出 B 可共享 Identity 而 Key 不同。现在 Complete 同时核当前 Key，新 C# 用例验证迟到旧完成不能删除新代操作；另提供带明确后果确认的待办清理，避免永久无效请求耗尽 128 格。
3. **清历史破坏导出恢复。** 锁外复制期间 clear 会删除任务，导致 receipt/save 无法继续；最初 TTL 内 retained 修复仍无法处理 24 小时后清理。现在 exports/receipts 各自保留无凭据的产物/任务摘要，Store.retained/saved 不再仅依赖 create/retry 的 24 小时去重；clear 同步各摘要的完整 saved_paths/revision。测试已改为 key 过期后清理/重启重放。最终需覆盖两次版本导出后重放第一 ID 仍保留全部已知路径，以及复制中 clear 的竞争。
4. **设置恢复失败覆盖旧 journal。** 现在 prepared journal 未恢复时，新的 commit 明确拒绝；测试注入回滚写失败并核 journal 原字节不变。PUT /prefs 也已纳入 settings_lock，避免与设置事务回滚覆盖已成功目录变更；committed journal 清理失败保留已提交事实。
5. **SSE 快照留下陈旧 SelectedTask。** 原 snapshot 清空/重建行对象，但 ViewModel 继续引用旧行。现在同实例按 ID 复用 TaskRow，snapshot 后 SelectedTask 按 ID 回绑，实例更换则使用新对象，消失任务置空；C# 增加同实例重连快照保留行引用的断言。最终还需核实例重启、gap 重连及任务被清理时按钮/详情同步。

额外正面改动：pending_verification 回执可用同 export_id 重验，最终文件再次损坏时回退待验证且保留暂存；资源准备已有取消接口；BackendSupervisor 用启动 semaphore 和 catch/Dispose 收敛失败 job/进程。旧的初审“缺少这些入口”的描述不能继续当成当前代码事实，但这些入口的运行边界仍须验收。

## 实际证据状态与限制

- `p1-pytest-fe442131da/runs/pytest-20261103-214925/pytest-child.stdout.txt` 实际记录 **122 passed、74 warnings**；外层 `.local/p0-temp/p1-pytest-r3.stdout.txt` 记录 exit 0、guard zero outbound、owned sentinel 未变。它发生在本轮最后一批修复之前，不能直接证明所有后加 Engine/Outbox/clear 边界已运行通过。
- `p1-api-ui-99397639cb/result.json` 为 **passed=false**：31 项中 API 的 30 项通过，WPF 集成项 actual_exit 1；其 UI 子根 `p1-ui-flow-1a5f4982fb/ui-result.json` 如实记录导入失败。不可宣称该整轮 API+UI 全通过。
- `p1-api-ui-f1b1581a02/result.json` 为 **passed=false**：第 14 项真实 BabelDOC 产物检查失败，最后阶段“加载翻译与排版模块”，约 60 秒后产生真实 failed 终态，控制进程退出 0。后续已将准备边界改为 120 秒；这只是新代码，不能将原失败变为成功。
- 21:59 前指针已转向新根 `p1-api-9d3db488ff`，仍在运行；本报告未拿未完成运行作结论。原初审已核的 `p1-api-019eec0d79` 历史 23 项成功仅保留其原有意义。
- WPF 进程内真实 Visual Tree 渲染与 ViewModel 调用仍须明确标注，不冒称鼠标/键盘、原生对话框、OS 拖放和跨屏 DPI 已自动化验证。

当前没有完成“最终冻结字节 → 定向回归 → 真实 API+WPF 整轮 → 独立终审”的闭环。允许继续整改与受控验证；**不批准 P1 整体完成，不批准合并 main、tag 或 Release**。

## 21:58 读取快照 SHA256

| 文件 | SHA256 |
| --- | --- |
| source/pdf2zh_next/desktop/engine.py | 63836DAD302DDAEB8916B8DDE48D530B5BD83D0E580EF82990B1FB74159E1C88 |
| source/pdf2zh_next/desktop/snapshots.py | A6896E5E1E6FABFFCFA17174D691F9BA737D031A523D4898894B10DD09AB7D3C |
| source/pdf2zh_next/desktop/settings_transaction.py | 4FA68DD745873B1C42159DBFB2A956CE4B02C94995D6C9B9C0A4F321197098E4 |
| source/pdf2zh_next/desktop/exports.py | E6356F3BAD4E54FC77712F02AB60E76713F1DFE54AE03CA560F603FED8B409AC |
| source/pdf2zh_next/desktop/storage.py | 1519099B4EE3598DB7560892410EF002ACC1BA64672A3834D8CB0DA3AE0645EA |
| source/pdf2zh_next/desktop/server.py | 6D0008035330975A14B0105FDA046113EE6EDADF65DD48C12422D6F9F4210F0F |
| desktop/PDFMathTranslate.Desktop/OperationOutbox.cs | AC242B932B267B8D321AEE7FEAF106DF8406448CE59826BE22645B6B310C79A9 |
| desktop/PDFMathTranslate.Desktop/Models.cs | 39B5F1654BB98F7B67002CAD5EC3A338B37D24F9A349F71981CD9CCC56B7194D |
| desktop/PDFMathTranslate.Desktop/WorkbenchViewModel.cs | 0F5DF698E20A2990328A26BCBE04D434A91B6A72A0580265252C4710BB466327 |
| desktop/PDFMathTranslate.Desktop/BackendSupervisor.cs | 5F5F75A4ED2860BFF1C0861731A8A47AEE975B77E9B3FC0F28CE8D18F50DB964 |
| source/tests/test_desktop_native.py | 372FE24F947263B5152E6387807E0791941947F0DBE58DB3199EF11CA5D08B0D |
| desktop/PDFMathTranslate.Tests/Program.cs | FF7EA121CA5C08519EA4ED5AD08BBE3211219D537CD48648B77492B27BDB604A |

以上只绑定读取快照，不继承后续改变文件的通过结论。最终复审时需要重新核对当前字节与实际运行绑定。
