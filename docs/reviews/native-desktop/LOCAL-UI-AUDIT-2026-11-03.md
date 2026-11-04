# 本机 WPF 界面审查与图像边界

本文件为上一轮历史记录。用户 2026-11-04 否定其视觉结果，后续以 [Ardot 组件约束](ARDOT-COMPONENT-BRIEF-2026-11-04.md) 和 [新交接报告](../../ARDOT_COMPONENT_UI_HANDOFF_2026-11-04.md) 为准；不再沿用此处的 Linear 风格决定或把旧图当新版通过证据。

本轮已在改视图前读取 guo-taste-design-2 的 SKILL.md 与 Linear DESIGN.md，将层级、单强调色、对齐、焦点和状态原则映射到原生 WPF UI；遵循用户的密集桌面工作流要求。没有引入营销首屏/图片或网页控件。现已实现并运行，早期“仅静态/无 WPF”快照不再是当前状态。

## 原界面与目标

原 WinForms/WebView2 五页，目标语言与保存默认目录原本存在，不能误称旧产品没有这些功能。主要问题是参数占据工作区、预览偏小、保存入口分散、设置和最终生效值不直观。现以左侧五项导航、文件列表/预览/参数三栏工作台、统一任务详情与结果路径、可滚动设置页组织。源和目标语言常驻，提交前显示语言组合；队列和结果共享TaskStore，不靠跨页轮询同步。

复用官方锁包：lepoco/wpfui4.3.0 tag `153baadeaf475875a81a4605881ca5c2dbe53972`；Toolkit v8.4.2 tag `35dfe7b12da0e64384bfaec7ebc0883196a89f9f`。已通过7897核实仓库/tag、NuGet精确包/许可证与实际编译，不仅列候选。颜色/控件来自WPF UI资源，中文系统字体，正常文本14DIP，辅助12DIP。

## 实际图像

最终 controls 图像根：`docs/verification/native-desktop/p1-ui-final-48bbb6af48`，Debug实际窗口HWND53805836，api_ready=true，生产ViewModel/真实HTTP，语言fa与自动更新opt-out读回、缺安装器后health均true。`ui-result.json`保留手工待验范围。此轮为内部流程/渲染通过；GUI用PowerShell直接启动时调用立即返回，因此最终实际进程退出码由后续performance/完整API驱动记录，不从该调用的0推断。

| 文件 | 所见状态 |
| --- | --- |
| 01-workbench.png | 显式源/目标语言、导入/预览/提交和统一服务状态。 |
| 02-settings.png | 服务/模型/API/密钥不回显、独立资源档位/准备进度。 |
| 02b-save-directory.png | 默认目录、数据目录/保留政策、设置读回和预览更新隔离。 |
| 03-queue.png | 任务表、阶段/进度和同源详情。 |
| 11-update-recovery-and-saving.png | 缺安装器中文错误、后台仍就绪、目录与保存设置。 |
| 12-restored-results.png | 已保存历史和版本路径，底部notice单行截断/tooltip，完整路径在详情。 |
| 08-compact-980.png | 980×680 DIP窄窗，工作区独立滚动，不以截图栅格缩放充当DPI。 |
| 09/10-render-*.png | 相同布局150%/200%栅格渲染，仅用于检查文字图像质量。 |

已逐图检查主窗口/设置/结果：导航和正文可读，长路径在输入框/详情中呈现；设置滚动到保存区后按钮/保留政策可见。最早 `p1-ui-flow-4f51ca0917` 的结果图有多行notice裁切，已修为单行通知；后续controls曾在180ms导航动画中截图发白，当前在750ms和新render pass后采集，未修改旧图或伪造补图。

最终正常全流程图在 `p1-ui-flow-adf14b7393`：真实两页密集科学文本/公式翻译、译文第二页、统一进度、fa/opt-out读回、缺安装器后保持health、保存丢响应恢复和四个实际版本，UI实际退出0。对应包级批次 `p1-dense-two-page-final-8e8925b474` 为32项全真、正常provenance未启用诊断hook。

本机再次查看了最新06-results-versions.png和07b-save-directory.png：四条实际保存路径在详情可读，notice为单行保存数量；设置/目录/保留策略/更新失败文案可读，没有先前动画发白。源/译文实际页数由API页头与UI记录核对，不能从图像自行推断。该轮窗口HWND21432256、window_ready1396ms、API_ready12256ms；这是内部运行观测，不与另一组性能轮混算。

旧 `p1-ui-flow-4f51ca0917` 保留修复前UI形态；它当时只验证首页预览，不证明第二页。单页断言失败和稀疏两页被扫描检测拒绝的失败均保留；最终用真正密集两页，未关闭扫描检测或改变BabelDOC算法。

## 尚未完成的 OS 验证

computer-use入口在初始化失败：`failed to write kernel assets: 系统找不到指定的路径 (os error 3)`。没有使用PowerShell/UIAutomation/输入注入绕过。PNG由真实运行WPF的RenderTargetBitmap生成，**不是操作系统截图、鼠标键盘验收或系统DPI测试**。原生文件/目录选择器输入、OS拖放、跨屏DPI、系统高对比/读屏、Geek GUI及安装向导逐页操作均未验证。控件有AutomationProperties、原生焦点/命令/键盘处理，但静态存在不等于这些手工项通过。

Pre-Flight：桌面信息架构、中文标签、单强调色、密度和错误恢复已落地；内部真实流程/渲染有证据。剩余OS项须在工具可用的机器人工复核后，才可给完整产品UI验收通过。
