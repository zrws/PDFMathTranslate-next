# Ardot 组件化原生界面复审交接

用户 2026-11-04 指出上一版视觉偏离 Ardot 原版，并要求 GitHub 提示词调研、禁止手写 CSS、必须使用组件库和动效库。本轮在 `codex/ardot-component-ui-2026-11-04` 实施，基于 be3147e，UI 产品代码冻结于 `60aa6dc3c40a5b8f44a6b67c271f8d108a82fe97`；后续打包许可修正为 `bc4e36836301816a99c635244275728d65d38415`，不改 UI/Python 源文件。未修改原 Python/BabelDOC 算法、原 API、安装/卸载及正式更新协议。

## 实现与设计依据

[设计提示词、GitHub 来源和组件清单](reviews/native-desktop/ARDOT-COMPONENT-BRIEF-2026-11-04.md)。保留原顶部品牌/保存/主题工具栏、五页导航顺序，工作台恢复左参数右预览。WPF UI 4.3.0 提供 Card、CardControl、CardExpander、CardAction、Badge、InfoBar、DataGrid、ToggleSwitch、输入框和原生导航；移除上一版 App.xaml 自写 Style。新增独立文档输出页，以真实文件版本组合卡片。没有新增或修改 CSS，没有自制 ControlTemplate/Storyboard/装饰矢量。

XamlFlair.WPF 1.2.13 实际提供 180ms 淡入，Logging 显式锁定 10.0.0。LibraryMotion 只负责库触发器与页面生命周期：重复进入缓存页面时重新触发；停用、卸载和完成时解除 Opacity 时钟影响并恢复 1。系统关闭动画或用户选择减少动效时不启动页面动画。外观偏好写入已认证后端给出的本应用 home/desktop/appearance.json，读取/写入均拒绝重解析点；损坏 JSON 恢复默认并告知，不阻断健康后端。所有保存入口共用成功清理密钥草稿的事件，失败时保留草稿。

所有界面颜色/文本层级使用组件库主题和 FontTypography；Ardot slate-900 原色经官方 accent API 应用。深色主题使用动态主题资源，选中文档文本继承库的选中态前景色。长参数/保存路径/版本文件有滚动容器；固定主动作旁显示实际语言组合，多文件列表高度有界。

## 新运行证据

| 运行 | 范围与结论 |
|---|---|
| ardot-validation-32ccef0d9c | 冻结 60aa：组件契约退出 0；27 项 .NET 检查退出 0；绑定 Debug DLL 与测试程序集 SHA。 |
| ardot-two-page-32f2c2f6f9 | 32/32、驱动/控制面均 0、回收身份残留为空。真实两页 PDF + 原 BabelDOC + 回环 LLM 夹具，保留 API/任务/预览/配置/幂等导出检查。 |
| p1-ui-flow-c3a603904d | 上述驱动的实际 WPF 运行，退出 0：真实任务完成、共享引用、译文第二页、丢保存响应恢复及四个保存路径；浅/深色、980 布局、外观往返与减少动效。源码为同批 aea9 内容，运行时尚未冻结；不是最终 60aa DLL。 |
| ardot-controls-b0e7e04226 | 动效实测 Opacity 约 0.75018、IsAnimated 真；停用后与完成后 IsAnimated 假、Opacity 1，缓存页面重入可见；坏 JSON 四类与保存密钥草稿行为通过。后续修订由最终独立运行覆盖。 |

32 项使用上一轮 R11 的本机受控 Python payload 重新实际执行，不是沿用上轮通过结论。Python 产品源码没有改变，最终新包另按哈希核对身份。LLM 只由回环夹具替代回答，不替换排版/翻译实现；不据此评价商业翻译质量。

独立 60aa WPF 运行在 `ardot-independent-appearance-r2-64928c986e9e`，WPF 与观察器实际均为 0，20 个有创建时间和镜像链核对的自有进程身份退出后无残留。独立构造的 desktop junction 读取和写入均被拒绝，37 字节 target 哨兵前后 SHA 不变。四次真实上传的 980×680 布局、译文第二页、浅深主题、设置保存、损坏偏好回退和实际动画时钟均通过。Debug DLL SHA256 为 `199EF9736EB4F283AB979131E967682AB0611B4B9414FAB8572FB67C3A11FA12`。详见 [独立整改 R2](reviews/native-desktop/LOCAL-ARDOT-REMEDIATION-REVIEW-R2-2026-11-04.md)。运行中任何失败均保留原始证据。

## 保留并撤回的首个 UI 安装包

`ardot-build-7ca349a770/completion.json` 记录实际退出 0，2026-11-04 09:59:51–10:14:15（+08:00）。构建入口 `build/build-native.ps1 -Offline`，使用私有 SDK 10.0.403、uv 0.13.7、CPython 3.12.13、Inno 6.7.1。锁定还原与 Release 发布完成；构建报告 `source_commit=60aa6dc…`、`source_dirty=false`。构建期间产品代码未变。

- 首个安装包（许可审核阻断，不作为最终下载指向）：`D:\student\翻译\PDFMathTranslate-next\dist\native-9b66790bc7ea\PDFMathTranslate-Setup-2.9.0.exe`。
- 225,341,691 字节；SHA256 `C92302A5DFD6638D7465FC973D52DF066A82C427AF0AE0EE19C2484788524D6C`。
- 解压 payload 16,429 文件，792,950,454 字节。模型/字体资源仍不随安装包分发；资源缓存与运行缓存另计。
- 安装器逻辑与上一轮相同；本轮没有再操作正式 AppId 安装或卸载，没有把旧 20 项安装矩阵说成新版向导的 OS 输入验收。
- 构建报告、依赖图、Python 产品源报告与 Release 组件身份复制于 `verification/native-desktop/ardot-delivery-20261104-60aa6dc`；EXE/DLL/模型/缓存不提交 Git。

本轮仅推送功能分支，不合并 main、不创建 tag/Release、不调用正式发布或线上更新源。

独立包核验 `ardot-independent-package-ee125c188592` 检查 16,428 个拥有项 SHA、55 个 Python 产品源与报告绑定；旧包把 SDK 根许可误复制为 Microsoft.Extensions 的 MIT 许可，因此仍被明确阻断。`bc4e368` 已改为两个 NuGet nuspec 所指向 `dotnet/dotnet@b0f34d51fccc69fd334253924abd8d6853fad7aa` 的原始 MIT 文本，另附 Microsoft 版权/来源 NOTICE，SDK 自己的条款独立保留。修正使用新的构建根，不覆盖旧包。

该旧 payload 的实际验收 `ardot-packaged-api-d9761645c0` 退出 1：真实 BabelDOC 准备或响应超时；后端实际退出 0、身份残留为空。没有用诊断钩子替换引擎或声称稳定性已解决。测试驱动 host 因未关闭字节码写入，导入 psutil/PIL 时在旧本机 payload 生成 30 个额外 pyc；原拥有项字节不变，此本机漂移不等同封装 EXE 内容，原件保留。后续新包测试同时设置 host 与子进程的 PYTHONDONTWRITEBYTECODE。

## 许可修正后的交付包

洁净构建 `ardot-build-r2-5e589b61ae` 实际退出 0，2026-11-04 15:33:58–15:49:49（+08:00），绑定 `bc4e36836301816a99c635244275728d65d38415`、`source_dirty=false`。UI/Python 源相对 60aa 无差异，最终文档提交不改变构建源身份。

- **最终预览安装包**：`D:\student\翻译\PDFMathTranslate-next\dist\native-cd32fa24a67f\PDFMathTranslate-Setup-2.9.0.exe`。
- **225,338,584 字节**；SHA256 **`CC2BCECCFAD905314D70344F8B758747B5FE56D14D17264A40120446C61EF531`**。
- 原始 payload 16,430 文件、792,943,181 字节；拥有清单 SHA256 `19D85A01AC707768F07229F366AB48DE254A082188CC102F0A57869E1EEC634C`。
- 报告副本与最终组件/许可身份：`verification/native-desktop/ardot-delivery-20261104-bc4e368`。首个 60aa 包的报告另存原目录，不覆盖或冒充最终包。

独立新包根 `ardot-independent-package-r2-fa79d046c77e`：16,429 个拥有项逐个 SHA 全匹配、无集合缺失/额外项/重解析点，55 份 Python 产品源两侧与精确集合匹配；SDK NuGet.Packaging 官方内容哈希 7/7 与锁一致，直接从 nupkg ZIP 读取 runtime DLL 7/7 与载荷字节一致，许可原文与 NOTICE 匹配。此项只读静态退出 0，不代替应用运行。

`ardot-packaged-api-r2-1dbbdcd967` 实际 31/31、驱动/控制面退出 0，真实两页排版、第二页预览、四版本、取消/重试均通过，payload 文件集合和 manifest 前后不变；此轮尚用旧测试观察器。`ardot-release-smoke-e581bbd0c1` 直接运行最终 EXE，真实 HWND 非 0，实际加载包内 .NET 10.0.14 的 hostfxr/hostpolicy/coreclr，子控制面无凭据请求返回 401。烟测结束由控制器终止自己的主进程，实际退出 **-1**，观察子控制面退出；没有将它写成正常 UI 关闭、认证 health 或 OS 输入通过。

最终验收驱动整改在 `e887ee4`/`c24b7e3`，只改 tests，不改产品或包。新驱动在 stdin bootstrap 前按 Popen 内核句柄指派独占 Windows Job，失败不继续启动业务；超时关闭 Job，删除旧 `taskkill /T` 分支。采样要求新建 psutil 对象读取创建时间/镜像、父子时间链及实际 Job 成员，允许同 runtime 的 python/pythonw 与预期 conhost，拒绝项只计数。7 项专项检查实际退出 0，包含旧对象缓存不变但 fresh 身份变更、无效指派、真实嵌套 Job 回收和 Job 外自建哨兵保活。初轮 6 项、R3 31 项均保留各自原始版本；最终 helper 的专项根为 `ardot-observer-tests-r2-597fbea7ee`。

旧 API 32 项及 API R2 采样中的 30/25 条最初被过窄名单误判为未知，已核全部是包内 pythonw.exe，其它未知镜像为 0，**不能称其混入外来程序或证明 PID 复用**。这两份旧 raw 仅因旧观察器缺严格归属约束而保留本机、显式排除公开交付，不据其 CPU/RSS 导出性能结论；没有相应 process-summary 或派生性能图。真正包含无关进程元数据的仍只有前述独立观察器第一轮原件。交付索引记录被排除文件的路径/字节数/SHA/原因，不收录内容；缺理由或排除根外文件两项负向实际均拒绝且不生成索引。

最终驱动 `c24b7e32f1a161a7e0dc9ae4a81b6638ecf22ce1` 的实际包验收为 `ardot-packaged-api-final-2af91b4c73`，2026-11-04 16:06:25–16:08:59（+08:00），**31/31、驱动与控制面实际 0、测量线程停止、残留身份为空**。实际导入最终 payload、无 repo overlay/诊断钩子，真实 BabelDOC + 回环文本提供方完成两页 PDF、第二页预览、四版本保存、配置快照和取消重试。1,347 条新采样均通过 Job/时间链检查，含 18 条合法 pythonw；payload 前后仍 16,430 文件、无额外或缺项、manifest SHA 不变。这一轮是最后驱动的实际结果，不能用此前较弱观察器的通过替代。

## 已保留的失败与验证边界

- ardot-controls-9de36014a9：功能检查通过，但视觉存在透明底、卡片/窄窗问题，不作为视觉通过。
- ardot-controls-2f92a4b4d7：新增 980 源语言可见性断言真实失败，进程退出 1。已压缩上传区、限制待提交列表并保留固定语言组合，由后续实际四文件运行复核。
- ardot-controls-73cc6b63a2：即时动效采样为假但当时未强断言，不能作动效发生证明。b0 增加下一帧观测和强断言后实际见到 Opacity 时钟。
- 首次直接调用 acceptance.py 的基础解释器缺 psutil，未开始验收；随后明确将已锁定的本机 packages 加入该测试驱动 PYTHONPATH，实际 32 项通过。
- 独立观察器首轮误按复用 PID 收入无关进程，外层退出 1；WPF 本体实际退出 0。该原始观察元数据保留本机，含无关进程信息的文件不纳入 Git；最终由修订观察器在新根核对。本轮不会把外层误报写成产品故障或回收通过。

PNG 是真实运行 WPF 视图的 RenderTargetBitmap，包括真实 HWND、生产 ViewModel/API 和真实 PDF 页面，非设计图，也不是 OS 截屏。computer-use 初始化仍失败；原生文件/目录对话框鼠标键盘、OS 拖放、跨屏 DPI、读屏/高对比和安装向导逐页输入仍未验。150%/200% 图仅为同一布局栅格渲染。上轮 130 pytest、安装 20 项和性能数据仍是各自旧轮的证据，本轮没有重跑就不写成新轮结果。

## 交付索引与独立裁决

最终索引为 `verification/native-desktop/ardot-delivery-20261104-bc4e368/delivery-index.json`，SHA256 `CEEA7083E7E4019DB6E850EE6A4E74CEDBD93431509B4BC64B8485967A29EDA5`。绑定 22 个运行根、200 个证据文件、514 个源文件；这是身份索引，不是新的测试运行。另记录两份本机保留 raw 的摘要和中性排除理由，不包含其内容。首次独立观察器含无关元数据的整根完全不在候选中，仅其安全摘要由 R2 证据保留。

实施者重新读取全部 714 条源/运行记录及两条排除摘要，大小和 SHA 全匹配；候选禁止二进制/模型/字体/密钥文件为 0，高置信凭据模式命中为 0，被排除 raw 暂存为 0。运行根原始 CRLF/日志空白保持封存字节，产品与交接文档的单独空白检查通过。Git 没有提交 EXE、SDK、Python、NuGet、模型缓存；本机安装包由上文大小和 SHA 绑定。

最终独立裁决见 [LOCAL-ARDOT-FINAL-REVIEW-2026-11-04.md](reviews/native-desktop/LOCAL-ARDOT-FINAL-REVIEW-2026-11-04.md)。复审用实际 diff、最终新包、运行图和新验收，保留坏 JSON/密钥草稿/动效/路径及打包许可等初审整改过程。产品构建源为 bc4e368，最终测试驱动/索引源为 c24b7e3，后续仅封存文档和证据。
