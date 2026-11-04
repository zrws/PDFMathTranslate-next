# Ardot 组件改版独立初审

审核基点为 `be3147e7867de07c991351ce2e181b5e8eca6ee6`，分支 `codex/ardot-component-ui-2026-11-04`。本报告审核工作区，源码在初审期间仍由实施者修复，不将其称为冻结版本。审核者没有参与实现，没有启动应用、测试、后端或网络；仅阅读差异、未跟踪的新代码、固定上游本机源码与已有运行 JSON。未修改产品或原始工件。

已完整阅读 `ARDOT-COMPONENT-BRIEF-2026-11-04.md`。本轮视觉从新实现重新验收；上一轮原生桌面总审和首轮 Ardot 控件成功不能替代。

## 当前结论

组件方向符合约束：五页分别组合 WPF UI 的导航、卡片、表格、表单与消息控件；App.xaml 自定义 Style 已移除，未改旧 webui CSS，未见自写 ControlTemplate、Storyboard、颜色画刷或装饰 Path/Canvas。accent 通过官方 API 应用；XamlFlair.WPF 1.2.13 实际引用，Logging 10.0.0 显式锁定，并有新许可复制路径。

尚不授予本轮最终通过。首轮 `ardot-controls-9de36014a9` 只证明当时控件/后端检查通过，其透明背景与窄窗挤压不是视觉通过；第二轮 `ardot-controls-2f92a4b4d7` 真实 exit 1，980 窄窗源语言下缘裁切被新几何断言抓到。后续视觉修复须用新真实运行、两页流程和截图证明。

## 可行动问题与状态

### A01：损坏的外观偏好不能阻断后台就绪

初审 `DesktopAppearance.Load` 对合法 JSON `null`/`[]` 调用 `TryGetProperty`，会抛出未捕获的 InvalidOperationException，继而被 InitializeAsync 当成整个服务启动失败，使健康后端对应的 Ready=false。每次 Load 也应先恢复默认值，否则换 home/缺文件/解析失败会沿用上一份外观状态，却提示已经用默认值。

实施者已经补上每次默认重置和 Object 根检查、转 JsonException 后走外观告警。**源码方向已关闭，待 owned 夹具验证 `null`、数组、缺字段、不可读/损坏文件时后台仍可用。** 不需触及真实用户目录。

### A02：顶部与设置页的保存必须有同样的密钥清理语义

新增顶部“保存设置”只有 SaveSettingsCommand，没有旧 SettingsPage.SaveClicked 的 PasswordBox 清理。成功后 VM.NewApiKey 已清，控件仍留旧输入；用户追加字符时，完整旧输入又回写 VM，可造成错误更新密钥。

实施者已经新增成功保存事件，SettingsPage 订阅后清空 PasswordBox。**源码方向已关闭，待真实头部按钮与设置页按钮各自验证成功清空；失败保存应保留可重试输入，且不得产生第二次意外保存。** 不应以记录或回显凭据证明此检查。

### A03：Primary=null 不是停止动效的证据，缓存页的再次进入也未覆盖

已读取固定 XamlFlair `cd5bd4a55d22001ebaef5a4643b408e60dba9810` 的实际源码，非凭印象判断：

- `XamlFlair.Shared/Animations.cs` 的 OnPrimaryChanged 只做 InitializeElement 和 RegisterElementEvents，没有停止或 Cleanup 当前 timeline；null settings 仍会选择默认 Loaded 事件。
- `XamlFlair.WPF/Extensions/AnimationExtensions.cs` 的 FadeFrom 先将 element.Opacity 写为 0，再由库 storyboard 到 1。停用时必须确保既有 clock 不再影响画面且可见度恢复，不能只检查 GetPrimary 是否为 null。
- 库 Loaded 订阅采用 TakeUntil(Unloaded)；本应用缓存同一 Page 实例，之后进入时同一 Primary 值不一定重新注册。测试必须覆盖首次进入、离开、再次进入以及过程中切换减少动效。

**待修/待实证。** 建议在页面生命周期内用库公开 trigger 明确启动有限淡入；减少动效/系统关闭动画时停止属性上的动画影响并恢复 Opacity=1。库仍负责生成动效，不需手写 Storyboard。验收应观察真实元素的 Opacity/HasAnimatedProperties、再次导航和快速离开/返回，不把附加属性为空等价为停止。

### A04：外观文件读取应与写入使用同一目录边界

初审重解析检查仅在 Save，Load 的 File.Exists/ReadAllText 会先跟随已有 desktop junction 读取 home 外的文件。建议读写前统一验证偏好目录，再访问文件；使用本轮两个 owned 目录建立负向夹具，确认拒绝，不读取真实 home/config/cache。原 authenticated health 给出的绝对 home 应继续作为唯一入口，不能为了主题回退改读别处。

**待核后续修正。** 保存原本采用唯一临时文件和替换，不会因本次发现而要求修改后端设置事务或导出逻辑。

## 其他定点核对

队列和输出页的 SelectionChanged 已用 IsLoaded/IsVisible 与非 null TaskRow 防止隐藏表格在刷新时清掉共享选择，绑定 OneWay，不会把控件暂时清空直接写回 VM。ResultsPage 的 Loaded 在用户进入输出页时选择完成任务；还应以正在运行任务/无完成任务/历史刷新组合验证其导航语义，初审未据此断言已发生隐藏页回归。

SavedFiles 由同一 TaskRow 的真实 saved_paths 派生，版本卡片使用实际路径；打开操作仍只允许已存在 PDF/CSV，目录使用 explorer 的参数数组，没有拼 shell 命令。Python/BabelDOC、SSE、输出幂等、更新协议没有在本轮被替换。

系统事件在 Dispose 中均有退订，UserPreferenceChanged 的主题应用已经投递 UI dispatcher。建议统一线程/关闭状态处理，避免已排队回调在关闭后继续切主题。固定 light/dark 进入 HighContrast 前应先刷新系统主题缓存，避免旧缓存选错 HC 字典；若设计要求无 backdrop，Apply 的第二参数应显式 None，库默认值是 Mica。这里可复用组件库 API，不添加自定义主题画刷。

新运行前，继续保留两轮 Ardot 失败/局限；最终审核须重新核 light/dark、980 窄窗、两页真实任务、四版本卡片、密钥成功清理、坏外观偏好、减少动效与系统事件、清理事实及实际包依赖/许可证。OS 输入、对话框、跨屏 DPI 等原有工具限制依然单列，不因进程内渲染通过而消失。
