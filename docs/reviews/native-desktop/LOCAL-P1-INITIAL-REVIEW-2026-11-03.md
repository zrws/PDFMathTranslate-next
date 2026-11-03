# 本机 P1 独立初审（2026-11-03）

审核者未参与产品实现。本轮只读检查代码、契约与已产生的本机工件，并计算文件哈希；没有运行后端、测试入口、翻译、下载、UI 自动化或访问真实用户目录。仅新增本报告。

## 结论与范围

**初审存在交付阻断，允许继续实施和隔离验证，不作 P1 完成或发布许可。** 已批准的 P0 交付结论不因此改变。

审核期间实现者仍在修改未提交代码，HEAD 为 `080262216d6a405519097d30b90f09a1ffdb130a`。下列代码定位和哈希对应北京时间 21:12 左右的读取快照，不能把 HEAD 当作这些未跟踪产品文件的来源提交。实现者已确认会整改本报告的主要问题；整改后仍需按最终 diff 与新的定向证据复审。

范围为 `source/pdf2zh_next/desktop` 的控制服务、事件/持久化、Windows 工作进程与导出，以及 WPF 的后台监督、API 客户端和主要 ViewModel。不是安装/卸载、发布包体、性能、全部 UI 交互、DPI、更新兼容的最终审核。实际 WPF 进程内渲染截图不等于 OS 输入自动化，本报告未将其视为完整交互验收。

## 已读取的真实流水线证据

原 r4：`docs/verification/native-desktop/p1-api-0bd06fafdd/result.json` 为 `passed=false`、控制进程 `10704`、退出 `1`；13 项检查通过后在等待翻译终态时超时。该失败保留有效。其 `provider_calls` 实际有一条约在任务创建后 195.5 秒发生的本地提供方调用；owned home 下的 worker stack 文件也在后期出现。因此“始终没有进入 worker”只能描述早期观察，不能作为整个运行的最终事实。静态分析提示 pre-target/嵌套工作进程及标准流边界值得检查，但本审核没有证明具体操作系统死锁原因。

后续独立运行根 `docs/verification/native-desktop/p1-api-019eec0d79` 已只读核对：

- `result.json` 为 `passed=true`，23 个检查全部为 true，控制 PID `17780`，实际退出 `0`；模式明确为真实 BabelDOC 加 loopback LLM fixture，不是商业翻译质量验证。
- `task-final.json` 为真实完成任务 `f33889c46fc94f47`；`events.jsonl` 有 `task.final`、单调 revision 和最终产物身份。
- 镜像 `dual.pdf` 为 26,240 字节，SHA256 `17BC829737858DA806A212D88121275340B409BF37CA5B140307D24FC8026A0D`；`mono.pdf` 为 24,924 字节，SHA256 `C41AD8744CC1C89F1639A7D46955D677974B0B60B73EA227213E61FD0286B545`，均与任务记录中的产物身份一致。
- `result.json` SHA256 为 `862D06371B6741887FA614675C381D0D647F304355CA271B3F9A94A14DBDB5EE`。

这关闭了“从未证明真实 PDF 管线能完成”的早期事实缺口；不关闭下面的竞态和错误恢复问题。后续代码若再改变，需要明确哪些运行绑定哪份源码，不能以这一成功轮覆盖原失败轮，也不能将其直接冒充最终冻结版本的验收。

## 必须整改的发现

### B01 — 工作进程退出与 stdout 排水存在竞争；启动失败监督不完整

定位：`source/pdf2zh_next/desktop/engine.py:31`、`:34`、`:46`、`:58`。

当前 subprocess 版本的 collector 在另一线程读取 stdout，再向有界 `messages` 队列 `put`；主循环以“子进程存活或队列非空”为条件退出。子进程已退出、collector 尚未把管道中的最后一个 `finish/error` 放入队列时，父线程可观察到两条件均为假并提前结束，随后把本已成功的任务判失败，甚至关闭 collector 正在读取的 stdout。取消时 collector 也可能阻塞在满队列的 `put`，缺少明确完成/排水握手。这一竞争不会被单次 happy path PASS 排除。

另有 `store.start/get` 等启动操作位于 try 外，executor 返回的 Future 未保存或观察；持久化失败会使任务保持 queued 而没有可见终态。启动写入 stdin 尚无阶段期限；工作进程长期不发首事件时也没有明确的启动失败终态。

要求：通过 EOF 哨兵/完成事件把“工作进程退出”与“已完整排水”分开；等待并清理 collector。启动状态变更、启动/初始输入、错误收敛纳入监督，给首事件/准备阶段设合理期限且能取消、回收 owned 进程树。用可控事件排序验证“进程先退出，最后 finish 后入队”、大量输出后取消、首事件缺失、启动持久化失败和失败后的下一任务继续运行。

### B02 — WPF 丢失响应后的 retry/export 使用新键，破坏端到端幂等

定位：`desktop/PDFMathTranslate.Desktop/WorkbenchViewModel.cs:132`、`:138`。

`TaskAction("retry")` 每次调用产生新 Idempotency-Key，`ExportAsync` 每次点击产生新 export_id。服务端已提交操作、响应未到客户端时，用户按提示再次重试会创建第二个翻译任务或第二版本文件。现有后端测试重放同键不能覆盖真实客户端行为。create 路径已有 `submissionKeys`，retry/export 没有相应机制。

契约依据：`docs/DESKTOP_API_CONTRACT.md` §3 同键 retry 与 §7 “文件已保存 / 记录待同步”，要求同一 export_id 重试且有本地有界持久待办。

要求：按逻辑操作保留原键、不可变载荷与待同步状态；不确定结果时重用原键，只有明确发起新的导出才分配新键。导出待办跨应用重启仍可恢复。验证服务端提交后人为丢响应再重试/重启，任务和实际文件均不重复。

### B03 — “按原配置重试”仍从当前全局补配置，术语身份未冻结

定位：`source/pdf2zh_next/desktop/server.py:239`、`:259`、`:264`。

任务 options 保存了语言、页码、输出、资源档位和 service/base_url/model，但没有完整的非密钥有效引擎配置、术语指纹/内容身份等。retry 虽取原 options，`build_settings` 仍 clone 当前 `legacy._cli_settings()`，再只覆盖少数字段。全局 prompt、术语文件或其他有效参数改变后，重试实际配置会改变，载荷指纹也无法反映这类差异。WPF 文案却明确称“已按原配置重试”。

契约依据：§3 任务入队固化有效配置，包含术语指纹；中途修改全局配置只影响新任务。

要求：保存可重建的非密钥有效配置与内容指纹，术语文件采用稳定内容身份/owned 副本；执行时单独注入凭据，禁止密钥进入历史、事件或公开快照。验证全局设置及原术语文件变化后，旧任务 retry 仍使用原非密钥配置，或明确拒绝不可重建的旧快照并提示原因。

### B04 — 设置保存跨两个后端存储及两个 UI 请求，失败可能部分生效

定位：`source/pdf2zh_next/desktop/server.py:109`、`:110`；`desktop/PDFMathTranslate.Desktop/WorkbenchViewModel.cs:156`、`:157`。

PUT /settings 先 `legacy.apply_settings` 写配置，再 `store.prefs` 写资源档位/QPS。第二步失败时第一步不回滚。WPF 又在成功写 settings 后另发 PUT /prefs；若下载目录无效或磁盘写失败，UI 报“设置未保存”，而引擎设置、密钥等已经改变。已有“invalid settings rejected”检查针对预校验失败，不能证明第二阶段失败保持原值。

要求：在落盘前完成全部校验，并为多存储提交提供可恢复的事务/回滚；或者显式拆分独立操作与准确的部分成功反馈，不能整组宣称未保存。验证第二个存储写失败、目录无效和第二个 HTTP 响应丢失；重启读回也须与反馈一致。

### B05 — 导出磁盘 IO 持有全局任务锁，慢盘可冻结进度和取消

定位：`source/pdf2zh_next/desktop/exports.py:61` 至 `:113`；`storage.py` 的 update/read_events/cancel/prefs 共用该 RLock。

导出在整个复制、fsync、SHA256、目录扫描、磁盘空间检查和 receipt 期间持有 Store 全局锁。大 PDF 或慢/离线共享目录会让 SSE 读取、运行任务更新、取消、历史和设置都等待磁盘 IO；进度一致性的结构虽正确，交互仍会停顿。单文档翻译并发限制不能消除“导出旧结果同时运行下一任务”的场景。

要求：锁内只做操作意图/版本预留和短提交，复制/校验在锁外执行；同一导出操作另用细粒度锁，提交时复核内容身份。验证阻塞复制期间 SSE/取消可及时响应且最终版本不覆盖。

## 后续必须跟踪的缺项

- `exports.py:39` 对既有 pending_verification 回执直接返回旧记录，不重新核对恢复可用的最终文件。契约 §7 要求用户修复路径/外盘恢复后能用同一 export_id 再验证；应增加这一恢复路径与测试，同时继续保留暂存副本。
- `Assets.prepare/_download` 暂无资源准备取消接口；文件下载失败可重试，但完整工单要求的资源下载取消仍未验收。
- `BackendSupervisor.StartAsync` 在启动、握手、鉴权就绪异常时没有统一失败清理；job/子进程要等下一次 Start 或退出才会清理。应在异常边界立即释放 owned job/进程，并验证超时/非法 hello 后无孤儿进程。stderr 当前全部丢弃；后续建议保留有界且脱敏的故障诊断，禁止将凭据写入。
- Store 将全部终态历史和已清除任务常驻内存、每次持久化整个 JSON，UI history 翻页也持续加入集合；分页响应本身不证明长期 CPU/内存有界。完整资源占用验收仍需大量历史场景。
- API E2E 当前调用方在读取 hello 后未持续排水控制进程 stdout。应补有界排水与运行身份/源码哈希绑定，以免后续诊断日志造成测试专有的 stdout 阻塞；这不是已证明的 r4 根因。

## 暂未发现明显绕过的控制

只读范围中，服务绑定数字 loopback、所有 API 经 Bearer 中间件、Host 精确匹配、Origin 限制、一次性十秒 SSE ticket、无任意 CORS；WPF loopback HttpClient 禁用代理，token 通过 stdin 传递而非 argv/环境/URL。SSE 使用 instance_id/event_id、1024 有界重放、gap resync；Store 原子水位、revision 与终态保护以及客户端旧 revision 拒绝的基本结构相符。新 WPF/任务 job 使用 KILL_ON_JOB_CLOSE，任务输出路径和内容身份在提交前校验。这些是静态正面发现，Windows 强制取消/父进程消失、重连风暴和全部竞争条件仍须运行验收。

## 读取快照哈希（SHA256）

| 文件 | SHA256 |
| --- | --- |
| source/pdf2zh_next/desktop/engine.py | 9499E361FC04BBEADB29698FE87D1967C55F817C2E6FA98001201DFE8AC55140 |
| source/pdf2zh_next/desktop/worker.py | 5610F8EB9837ACEBF0CD8BA96763D7DB2225004CB2DA078E8921657D5F3AEC0E |
| source/pdf2zh_next/desktop/server.py | 98D1289E71327B49EC63799DC46EE341FC287CEDE6FE4211CF12C1B5485AEC64 |
| source/pdf2zh_next/desktop/storage.py | 573936B98CEAD01940AE8831BEAEC1407352177B9121C9E9A6E79BFE234129C8 |
| source/pdf2zh_next/desktop/exports.py | AD16C573BECF7C549846E484DF2B782438E3D22943C4C166DB48F93A9EE63997 |
| desktop/PDFMathTranslate.Desktop/BackendSupervisor.cs | 4BD07FC047FDD89611375BEF202ADE65C8B87216D7C8F4CAB8CDC7C88598EBBA |
| desktop/PDFMathTranslate.Desktop/BackendClient.cs | 06152CCB19914CE38BF52911AC037BAD7435949DF7BB81CA42B38226F3EFC8B7 |
| desktop/PDFMathTranslate.Desktop/WorkbenchViewModel.cs | AF2C6E8710990695FB59DAE0D9F09812D195CD7764AAD5B0DFE320FA562DC455 |
| tests/native/acceptance.py | D45C86343162F1638C8648738FE5753DAEFCE32A476F675C3BE50C0573103C95 |

最终复审入口：逐项关闭 B01–B05 及契约缺项，冻结最终产品提交，提供受影响短回归和实际 WPF/后端整体验收；历史失败完整保留，UI 输入/DPI 等未验证项如实列明。
