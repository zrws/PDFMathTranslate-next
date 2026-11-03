# Worker 启动超时独立单轮诊断（2026-11-03）

## 结论

**独立单轮真实 API 验收实际退出 0，30/30；本次没有复现原 120 秒超时。** 抓到的首个长准备栈位于 ONNX 推理会话初始化，后续已推进到 PyMuPDF 字体装载，再完成 PDF。没有证据将本轮解释为 Python 进程永远未启动或固定位置永久死锁。

**原失败仍然成立，根因尚不能定案。** 原失败停在“加载翻译与排版模块”，没有当时的栈；本轮采样点和负载未严格复现原条件，不能据这次通过把原失败改为通过，也不能断言它一定由并发构建/pytest 引起。本报告不是整个 P1 放行。

## 独立性、授权与边界

由未参与实现的审核者按本轮明确授权，仅运行一次现有 `tests/native/acceptance.py`，使用 `.local/native-runtime`、指定已准备资产、全新 owned HOME/证据目录和回环 LLM fixture。没有修改产品或测试实现，没有启动 UI、真实外网/付费服务或接触其他应用；原 frozen P0/root 和原失败工件未改。

新证据根：`docs/verification/native-desktop/p1-independent-workerdiag-20261103-7b5963a01e`。独立驱动、计划、实际 argv、入口 SHA、stdout/stderr、监测、原始 py-spy JSON 和实际退出都保存在该根。资产副本位于测试自建 `.local/native-acceptance-*`，没有把模型/字体复制进证据目录。

py-spy 仅用于本轮已识别的 desktop.worker PID：校验验收根子树、解释器、完整命令行、PID/创建时间，再跨抓栈保持进程句柄以约束身份。未使用 --locals、--native 或 --subprocesses，全部 frame.locals 均为 null。没有抓取其他构建、pytest、应用或未知进程的栈。

## 实际运行身份与结果

- 验收 PID `15820`，created `1793718984.5485387`；控制 PID `12272`。
- 首任务 `379cdc4f1b9d458a`；worker PID `11116`，created `1793719008.2481468`，命令为锁定解释器 `-u -m pdf2zh_next.desktop.worker --translate`。
- 独立驱动约 23:16:23–23:18:21，总耗时 117.324 秒；驱动 exit 0、验收 exit 0、控制 exit 0，无诊断总超时，无本轮存活后代。
- 真实 API 30/30、5 次本地提供方调用；source_mode 为 repository overlay，该轮不含 WPF UI 流程，不作为最终打包环境证明。
- acceptance、engine、worker、py-spy、独立驱动 SHA 前后完全一致；provenance 记录的 10 项主要源码文件在运行后复核也无漂移。

## 抓栈与 SSE 时间对齐

| 抓栈 | Worker 年龄 | 当时 SSE 阶段 | 主要栈 | py-spy 退出 |
| --- | --- | --- | --- | --- |
| stack-1 | 20.927 s | preparing / 准备排版模型与服务 | MainThread：onnxruntime `_create_inference_session` → doclayout 构造/from_pretrained → load_onnx | 0 |
| stack-2 | 43.008 s | running / 解析 PDF | asyncio_0：PyMuPDF `fz_new_font_from_file` → FontMapper → PDFCreater；MainThread 在 asyncio IO 等待 | 0 |
| stack-3 | 63.836 s | finalizing / 生成 PDF | nonblocking 样本仅有空 frames，无法据此定位具体 native 操作或认定死锁 | 0 |

首任务从创建起 1.562 秒进入“加载翻译与排版模块”，15.754 秒进入模型/服务准备，42.389 秒出现解析进度，64.473 秒出现 SSE 完成事件。可见本轮重型本地初始化后持续推进，而不是在同一 Python 栈停留至超时。

诊断触发有一项限制：驱动读取已持久化 desktop-state 判断 preparing，普通进度不逐帧落盘；因此后两次触发仍看到旧 preparing，而 SSE 实际已为 running/finalizing。报告按原始 SSE 时间校正，**不能将 63.8 秒称为连续启动阻塞**。这不影响抓取对象全部属于本轮 worker 的身份边界。

## 负载与原失败比较

本轮 110 条系统/owned 子树采样中，系统 CPU 为 1.8%–52.1%，可用内存约 2.23–4.46 GB。监测只使用系统聚合值及本轮子树；没有枚举其他应用来归因资源消耗。py-spy 使用 nonblocking，但进程内存查询和抓栈仍有观察开销，不能拿本轮时长作无监测性能基线。

原失败 `p1-ui-current-121182c049`：真实产物检查失败、控制退出 0、没有提供方调用；最后更新是“加载翻译与排版模块”，随后超时终态。原失败与独立本轮的解释器路径、acceptance SHA、已记录的 10 项源码路径/哈希相同。

父任务报告原失败发生于完整构建/pytest 并发；独立本轮记录了 r9/试装准备日志元数据，但这些日志大小/时间在窗口内未变化，且没有主动控制其他任务负载。故**没有证明同等并发条件已重现**。本轮栈支持“ONNX/字体本地初始化是可观测耗时点”，不足以追认原失败具体卡在该处，更不足以排除其他 native 导入/IO/资源争用。

后续最终包应在负载口径明确的条件下完成实际整体验收；若启动超时再次发生，应在那一个失败运行的 owned worker 上同步采栈定位。无需改写或删除原失败来获得干净结果。

## 工件身份

| 工件 | SHA256 |
| --- | --- |
| diagnostic-summary.json | 1A54FF70ADD69F08BEBE46A201FF6CFF751F3C0F76B95FC37B8C9D1BF4D8FB5C |
| observed.json | D75B47847614D2C0438D00B77D1DB6D8B8F8C9EE683C0EB000D11C335D32FC85 |
| acceptance/result.json | 9AC92AA96D5033A3C1ED98F8871C4F13B382E29610EA3029B0D3E6CFA8C67E3D |
| acceptance.py | 77177250B78EE6A855FB99104486F18934C916C84A860AC7BD14C382F3D8531F |
| engine.py | 63836DAD302DDAEB8916B8DDE48D530B5BD83D0E580EF82990B1FB74159E1C88 |
| worker.py | 6105D82A5F87DF356214DF43A44237E0BCD25E2E3436FD539BAC2AC35B5012EA |
| 独立 driver.py | D1BF25461FB342FBD4213C7A22181C7B09796B14EC3BD389BBFFBBF3C2CD2ED1 |

原始每份抓栈还各自保留实际 argv、worker 身份、开始/结束、exit 和双流 SHA，可独立复核；不以本报告替代这些原件。
