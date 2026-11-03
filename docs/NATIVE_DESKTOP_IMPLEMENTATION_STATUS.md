# 本机原生桌面实施状态

本文件替代此前“P0 BLOCKED / P1 未开始”的进度快照；历史裁决保留在 reviews 和 Git 历史中，不是本机运行结论。

- 目录：`D:\student\翻译\PDFMathTranslate-next`；初始目录为空，没有覆盖用户改动。
- 已核交接：`codex/native-desktop-2026-09-28` @ `ab5d684df52aa1ec760eb25bc777932003b984b7`。
- 实施分支：`codex/native-desktop-implementation-2026-11-03`；GitHub 单次请求按用户更正使用 `127.0.0.1:7897`。
- P0：**本机新轮安全门通过，已获独立复审**，产品迁移在该门之后实施。
- P1：**WPF 产品、Python 控制面、构建与中文安装器已实现**；这是供复审的开发预览。最终包级测试和独立总审状态见主交接报告，不把单项成功推成整个发布验收通过。

最终本机已运行项：130项Python、27项.NET、32项正常两页包级API+真实WPF内部流程、20项独立AppId完整安装矩阵均实际退出0；最新运行图为 `verification/native-desktop/p1-ui-flow-adf14b7393`。R11预览安装包224832521字节/SHA256 B1F78B5E555AB6F1A6D4E428A1AD71C2D7F43E6BE7FE33093F32A0E0AB3945CB。独立最终裁决与证据完整索引见主交接报告末尾。

## P0 当前证据

实际冻结运行位于独立克隆 `D:\student\翻译\p0-frozen-fa97b2e6f9`，执行源码 `080262216d6a405519097d30b90f09a1ffdb130a`。Git 中 [p0-delivery-20261103-c72fd7361c](verification/native-desktop/p0-delivery-20261103-c72fd7361c) 是字节一致的交付镜像，**不是重新运行的路径根**。绝对路径绑定 checker 须用原根，不能搬目录后声称通过。来源见 `P0_DELIVERY_ORIGIN_2026-11-03.json`。

冻结24+新增4覆盖、23项负向矩阵、26项checker变异、202条脚本绑定、1048条输入哈希均有机器证据；outer/relay/prior/final checker实际退出均为0。封存摘要 `3BCD79E48A6FBDEAEDF90590D539E940A07D477C532CBF9327090E1FADEB7374`。本机 recovery 有8条断言和4份stub日志；旧运行未随Git提供，旧缺项原因未知，未编造解释。独立裁决见 reviews/native-desktop 的 `LOCAL-P0-FINAL-SAFETY-REVIEW-2026-11-03.md`、`LOCAL-P0-PORTABLE-RUN-REVIEW-2026-11-03.md`、`LOCAL-P0-DELIVERY-FINAL-REVIEW-2026-11-03.md`。

## 产品实现

| 领域 | 当前行为 |
| --- | --- |
| 窗口 | .NET10 WPF、WPF UI4.3.0、Toolkit8.4.2；工作台/任务/结果/术语/设置。默认入口不加载WebView2。 |
| 统一任务 | 共享TaskStore/TaskRow；SSE、游标去重、实例重启快照、终态保护、持久化幂等恢复。取消、重试、有效配置、错误及保存路径可见。 |
| 语言和保存 | 显式源/目标语言；保留不常见语言；未选不能提交。默认目录持久化/任务覆盖；日期目录、多版本命名和SHA回执避免覆盖。 |
| 资源和性能 | 三态启动、轻量空闲控制面；独立资源准备进度；按需有界预览；并发1、线程/QPS独立档位、GPU默认关闭。 |
| 引擎兼容 | 保留Python/BabelDOC算法与CLI/Gradio源码；三个锁定补丁仅处理环境、线程和原保存函数的轻量子进程导入。 |
| 安装更新 | 私有.NET运行时、单套CPython、洁净哈希锁构建、中文Inno EXE。拥有清单+SHA+路径防护清理，保留用户/修改文件。保留latest.json/版本比较/SHA/旧opt-out，预览不访正式源。 |

## 验证边界

已有实际验证：此前字节127项pytest（零外联、隔离哨兵不变）、27项.NET回归、真实BabelDOC API30项、真实WPF内部流程和PNG、旧入口6项、约300秒空闲进程采样。后续复审修复及其全量新验证、完整安装矩阵和最终包由交付索引绑定，不沿用旧包结果。哨兵是本轮独占测试目录，不读取真实用户缓存来比较。

图像来自运行窗口的RenderTargetBitmap，有真实HWND和生产ViewModel/API，**不是OS输入截图或系统DPI验收**。computer-use初始化因kernel assets路径错误失败，文件/目录对话框输入、OS拖放、跨屏DPI和Geek GUI尚待人工验证。GPU、旧完整桌面进程树未测，不报告它们的改善百分比。

真实引擎曾间歇出现120秒准备超时；同输入/源码独立重跑成功，诊断看到ONNX初始化和PyMuPDF字体加载，但未证明失败根因或已消除。失败记录保留。

精确构建、证据、残余风险见[主交接报告](NATIVE_DESKTOP_REVIEW_HANDOFF.md)。不合并main、不建tag、不发布Release、不改线上latest.json。
