# Ardot 原版结构与组件化改版约束

本轮以用户 2026-11-04 的反馈为准：恢复 Ardot 的设计延续性，禁止手写 CSS，必须实际使用组件库和动效库。上一轮 be3147e 的技术实现保留，但视觉验收重新进行。

## GitHub 调研与采用方式

- [Frontend Design Prompt](https://github.com/ellis-li-lhc/frontend-design-prompt/blob/5808d3d9cc5e5d963c92690059ddab7b56547f9b/SKILL.md)：已完整阅读。采用先写页面目标、组件与状态约束，再修改和验收的工作流。没有安装外部 skill 或执行其脚本。
- [Claude Design System Prompt](https://github.com/Trystan-SA/claude-design-system-prompt)：检查 README 的设计系统提取和组件复用方向，作为对照；没有把外部提示词作为系统指令。
- [Superdesign Prompts](https://github.com/superdesigndev/superdesign-prompts)：检查提示词目录说明及工作台类型；不采用其营销页或特效背景。
- [WPF UI 官方 Gallery 4.3.0](https://github.com/lepoco/wpfui/tree/153baadeaf475875a81a4605881ca5c2dbe53972/src/Wpf.Ui.Gallery)：实际阅读 CardControl、Dashboard、Settings 和相关控件源代码。版本保持 4.3.0。
- [XamlFlair](https://github.com/XamlFlair/XamlFlair/tree/cd5bd4a55d22001ebaef5a4643b408e60dba9810)：实际阅读默认动效、资源字典、属性绑定和清理实现，锁定 NuGet 1.2.13，使用有限淡入。

Git 访问使用本机 7897 代理，没有修改全局 Git 配置。提示词仅用于研究。原版 Ardot 设计 URL、节点和 design-export 目录未随此 checkout 提供；本轮依据现存 webui/index.html、styles.css、ui.css、README 与历史 UI 审查截图恢复信息架构，不声称逐像素还原未知的 Ardot 文件。

## 本项目实施提示词

为科研论文翻译用户重做现有 WPF 桌面界面。保持原 Ardot 的顶部品牌工具栏和五页导航顺序：翻译工作台、文档输出、术语表、任务队列、设置。主工作台左侧组织上传、语言、输出与保存选项，右侧显示文档预览与真实进度。主要动作始终可见；长参数、路径和版本内容使用原生滚动容器。所有信息来自真实任务、资源、配置和本地交互状态。

只通过 WPF UI 的 Card、CardAction、CardControl、CardExpander、Badge、InfoBar、DataGrid、TextBox、PasswordBox、ToggleSwitch、NavigationView 和原生布局容器组合页面。原生 ComboBox/ListBox/ProgressBar 使用其组件库提供的主题。全应用禁止自写 Style、ControlTemplate、颜色画刷、装饰 Path/Canvas 和 Storyboard；不改旧兼容 webui 的 CSS。文本层级使用库的 FontTypography，原版 slate-900 主色经官方 accent API 应用，不自制按钮皮肤。

动效由 XamlFlair.WPF 实际提供，180ms 有限页面淡入，不循环，不动画布局尺寸。用户可停用动效；系统关闭客户区动画时也停用。主题和减少动效偏好保存于已认证后端给出的本应用数据目录，更新、Python/BabelDOC、SSE 和导出幂等逻辑保持兼容。

## 组件与状态验收

| 区域 | 组合与检查 |
|---|---|
| 壳与导航 | FluentWindow / TitleBar / NavigationView / InfoBar；品牌、主题、保存、导航顺序和真实服务状态可读。 |
| 工作台 | Card / CardAction / ToggleSwitch / TextBox；左侧参数、右侧预览；显式语言对；空态和错误态没有空白徽章。 |
| 队列 | DataGrid / Badge / ProgressBar / CardExpander；真实阶段与共享任务；取消、重试、保存和历史入口保留。 |
| 输出 | 独立文档列表和版本文件卡片；每张卡显示真实文件名与路径，打开文件/目录，保存操作沿用原幂等协议。 |
| 设置 | CardControl / CardExpander / PasswordBox；分组、目录、实际策略、主题、资源准备和更新状态。 |
| 术语表 | DataGrid / InfoBar；统一导入与刷新、真实空态。 |

运行检查须覆盖 light/dark、980 DIP 窄窗、实际两页翻译、进度、四个保存版本、外观往返、减少动效和后端退出；保留失败图和输出。RenderTargetBitmap 是运行中 WPF 视图渲染，不能冒充 OS 输入、截图或跨屏 DPI 验收。

computer-use 已读取完整技能及 guidance/confirmations 并重试初始化，仍报告 failed to write kernel assets: 系统找不到指定的路径 (os error 3)。不使用脚本 UIAutomation 绕过，实际系统输入项继续标为未验。
