# Ardot 组件桌面独立终审

本轮审核以 `be3147e7867de07c991351ce2e181b5e8eca6ee6` 为基点；UI 冻结提交为 `60aa6dc3c40a5b8f44a6b67c271f8d108a82fe97`。其后 `bc4e36836301816a99c635244275728d65d38415` 只修构建、MIT 与 NOTICE，没有改变 UI 或 Python。审核者未参与实现，没有修改产品代码。只读审查、独立 owned 夹具的真实 WPF 运行及静态包核验分别记录，不把文件索引当重新执行。

## 当前裁决

当前代码、DEBUG UI、新包静态核验、严格新驱动的最终 API、Release 烟测与交付候选通过独立复审；初审 A01–A04、旧包许可阻断以及测试观察/超时回收代码边界均已关闭。允许普通提交并推送 `codex/ardot-component-ui-2026-11-04` 供复审，没有剩余的本轮推送阻断。旧 C923 包仍未获通过，其后续本机漂移和全部已知失败仍保留。本裁决不批准合并 main、force push、tag 或 Release，也不把下述人工与稳定性限制改成通过。

## 组件与流程

五页组合 WPF UI 4.3.0 的 NavigationView、Card/CardAction/CardControl/CardExpander、DataGrid、Badge、InfoBar、TextBox、PasswordBox 和 ToggleSwitch。原生组合框/列表使用组件库主题。没有新增 CSS，也未修改旧 webui CSS；App.xaml 自写 Style 已移除，未见自写 ControlTemplate、画刷、装饰 Path/Canvas 或 Storyboard。文本颜色引用官方 DynamicResource，accent 由库 API 应用，没有另造控件皮肤。

XamlFlair.WPF 1.2.13 实际生成有限淡入，Logging 10.0.0 显式锁定，System.Reactive 5.0.0 与 DI Abstractions 10.0.0 随锁解析。LibraryMotion 只管理库 trigger 和清理：Event=None、页面 Loaded 显式触发、Unloaded/减少动效解除 Opacity clock 并恢复 1、完成回调归一。180ms 动画没有布局尺寸变化或循环；没有用手写动画替代库。

读写外观共用重解析检查、64KiB 上限、Object 根及默认回退；异常偏好不会阻断健康后端。偏好未读前不动画；系统主题缓存刷新、None backdrop、disposed/事件退订保留。保存成功事件统一清密钥输入，失败保留草稿。队列/输出的可见性与非 null 选择门保留同一共享 TaskRow，不以隐藏控件的临时清选覆盖全局任务。

固定主动作旁显示语言组合，文件列表有界；输出页独立展示真实版本路径与打开动作。Python/BabelDOC、SSE/重连/实例去重、完整任务快照、保存/重试幂等和自动更新协议均未在本轮改写。P0 未受影响，不要求重复已关闭的无关 28 案。

## 独立实际 UI 与边界夹具

完整记录见 `LOCAL-ARDOT-REMEDIATION-REVIEW-R2-2026-11-04.md`。新根 `ardot-independent-appearance-r2-64928c986e9e` 的实际外层/WPF exit 都为 0，PID 18200，DEBUG DLL SHA256 `199EF9736EB4F283AB979131E967682AB0611B4B9414FAB8572FB67C3A11FA12`；20 个经父 PID、创建时间、预期 exe 校验的观察身份无退出后残留。

独立生成的 `.local` home/target junction 被 Load 和 Save 拒绝；37 字节 dark/true 哨兵前后 SHA256 均为 `5F5599E6231EC5CE632CFFDEFADB56CAB73C99BABC7598B1A10F777E3F8F4783`。坏 JSON、真实 Opacity clock/停用/完成释放/缓存重入、保存失败草稿保留与成功统一清理均真。四次真实上传在 980×680 的语言与主动作边界通过；只上传四次，没有提交四次翻译。实际译文视图读到已有真实任务第 2/2 页。

已独立查看深色、四文件待提交窄窗、真实译文第二页、保存组顶部和输出选中项/版本卡。没有透底、选中灰字或新增相互覆盖；长参数和版本列表使用可见滚动容器。首轮透明、2f92 裁切失败、73cc 未强断言的弱动效证据均保留，不继承为通过。

正常完整两页 `ardot-two-page-32f2c2f6f9` 为 32/32、control 0/无残留，UI `p1-ui-flow-c3a603904d` 的真实任务、共享引用、页二、丢保存响应恢复及四版本/卡片均真。它属于此前 aea9 同批字节；独立 60aa 轮补验证其后固定语言 Caption、选中文字继承和 DEBUG 布局/视图变化，没有伪称旧轮执行全部当前字节。

第一轮审核者自写 observer 漏核创建时间，误归属陈旧父 PID，外层 exit 1 而 WPF 本体 0。原 raw 仅在本机保存、明确排除 Git；本报告不复述无关进程元数据。安全摘要只引用原件本机路径/SHA及原因。修正后的独立 R2 在全新根执行，未覆盖旧记录，未停止或修改误识别的进程。

## 旧包核验、拒绝与更正

`dist/native-9b66790bc7ea/PDFMathTranslate-Setup-2.9.0.exe` 为 225,341,691 字节，SHA256 `C92302A5DFD6638D7465FC973D52DF066A82C427AF0AE0EE19C2484788524D6C`。独立冻结根 `ardot-independent-package-ee125c188592` 保留全部原报告与 SUMMARY：16,428 个声明拥有项 hash 均匹配，无缺失/重解析；55 个 Python 源码在源/包两侧与精确集合一致。

但旧 `Microsoft.Extensions-LICENSE.txt` 实际为 SDK 的 Microsoft .NET Library 条款，不是两个 NuGet 包声明的 MIT，因此该包拒绝。修正源已从两个 nuspec 的精确 `dotnet/dotnet@b0f34d51fccc69fd334253924abd8d6853fad7aa` vendored MIT，另以 NOTICE 保留 Microsoft 版权、包版本和来源；原 SDK 条款仅作为 dotnet-LICENSE 保留。MIT 原文 SHA256 `CFC21F5E8BD655AE997EEC916138B707B1D290B83272C02A95C9F821B8C87310`。

旧 payload 后续出现 30 个 PIL/psutil pyc，来自验收 host 未禁字节码；没有删除或加入清单。它们是本机运行后漂移，不反推已经封装的 C923 EXE；新轮须禁 host 字节码并核前后集合。

审核者初始 Python 检查把原始签名 ZIP 的 SHA512 与 NuGet lock contentHash 比较，语义错误。原字段保留但明确不能据此判依赖不符。后续用 SDK 10.0.403 自带 `NuGet.Packaging.PackageArchiveReader.GetContentHash` 核 7/7 匹配，并直接读取各 ZIP 的 runtime DLL 条目算 SHA256，7/7 与载荷 DLL 匹配，不是只比 deps 字符串。更正在同根 `nuget-content-review.json`，没有用该错误阻断依赖版本。

旧包真实 API 根 `ardot-packaged-api-d9761645c0` 实际 exit 1：15 个已执行检查中真实产物失败，错误为引擎启动或响应超时；control 0、观察身份无残留。此轮不算通过，也不据并发哈希/磁盘负载推断原因。此前间歇启动风险仍未知，新轮成功也不能声称已经消除。

## 新包静态终核

新构建 `ardot-build-r2-5e589b61ae` 实际 0，build-report 与 Python 复制报告的提交均为 `bc4e36836301816a99c635244275728d65d38415`，报告 source_dirty=false。新安装器 `dist/native-cd32fa24a67f/PDFMathTranslate-Setup-2.9.0.exe` 实际 **225,338,584 字节**，SHA256 **`CC2BCECCFAD905314D70344F8B758747B5FE56D14D17264A40120446C61EF531`**，预览频道。

独立根 `ardot-independent-package-r2-fa79d046c77e` 的标准库静态检查实际退出 0：16,429 拥有项逐文件 hash 全匹配；整个 payload 16,430 文件、792,943,181 字节，只有清单自身不在拥有项，没有缺失/额外文件、重复/越界路径或 reparse。55 个 Python 文件源/包两侧 hash 与精确集合全部相同。manifest、源码报告、安装器和 Python/补丁/NuGet 三份锁均与报告绑定相符。

| 工件 | SHA256 |
| --- | --- |
| build-report.json | `3174C1E9F4E7814B413CC180A5ED8B2C66CE711C066D2A8DF576C8C55E3F538B` |
| owned-files.tsv | `19D85A01AC707768F07229F366AB48DE254A082188CC102F0A57869E1EEC634C` |
| product-source.json | `D489DF75803315A4B3710BA59330E196AE1362EA83AED13D2AAD186B86701D98` |

新载荷 XamlFlair、System.Reactive、Extensions MIT/NOTICE 与 vendored 原件逐字节一致，Extensions MIT 固定上游 SHA 与 NOTICE 来源/版权字段均匹配。WPF UI/Toolkit/.NET 原许可与 notices 保留；Extensions 两份原 nuspec 和 third-party notices 也在载荷中。不是用 SDK 条款重命名代替 MIT。SDK NuGet API 的真实内容哈希 7/7 匹配锁，直接 ZIP runtime DLL 条目与载荷比对 7/7 相符；SourceLink/Git 构建任务不在 runtime libraries 中。

相对上轮 WPF 载荷，增加组件/动效和许可后，压缩增加 506,063 字节、payload 增加 1,977,387 字节。相对同锁/同压缩设置的受控旧 launcher 参考，压缩约减少 12.26%，解压约增加 1.08%；参考不是历史 Release 复现，不能称两种体积都降低。本轮未重测 UI 的完整 CPU/GPU/冷启动对照，不沿用旧 UI 百分比。

## 最终正常 API、运行边界与候选终核

新包静态核验完成并停止大文件读取后，`ardot-packaged-api-r2-1dbbdcd967` 实际 0、31 项全真，control 0、观察身份无残留，host/child 禁字节码，payload membership 前后不变。它只跑 API，不能写成含 UI 的 32 项。新 Release `ardot-release-smoke-e581bbd0c1` 实际进程 PID 25608、主窗口句柄 15468820，本轮子控制端口的无凭据请求得到 401，观察子控制退出后无残留；实际加载的 hostfxr、hostpolicy、coreclr 均位于本轮 payload 的私有 .NET 10.0.14 中。控制器终止为真、主进程实际 exit -1；这不是正常关闭、认证健康或 OS 输入通过。完整认证功能由正常 API 轮覆盖。

交付筛查曾把旧完整 API 的 30 条、API R2 的 25 条镜像记录称为“未知”，后续核实全部是各自 payload 同目录的合法 pythonw.exe，其它未知镜像为 0。**本报告撤回由这些计数推导出的“外来/污染”判断；它们没有证明 PID 复用或隐私泄漏。** 它们与审核者第一轮 observer 已证实的误归属不是同一事实。旧 API 没有从该采样导出新的 CPU/内存改善结论，功能断言、自产 PDF 与 UI 图仍保留；若保守排除旧 raw，应明确理由为当时观察归属约束不足，不能把排除称为已证实污染。

验收入口仍需严格 owned 保证，现已修复：专用 Windows Job 按本次 Popen 内核句柄指派，成功后才释放 stdin bootstrap；超时关闭 Job，移除 `taskkill /T`。采样逐父创建时间/预期镜像/live identity/真实 Job 成员验证，只记录通过的身份，拒绝候选仅计数。后置使用 fresh psutil.Process 重查，避免 create_time/exe 缓存不能验证 PID 代际；允许同一运行时 python.exe/pythonw.exe 及受核 conhost，不静默漏掉合法保存子进程。

已独立只读核七项回归的原始 stdout 和实际 exit 0，包括陈旧父 PID、未知镜像不输出、非成员、根身份变化、无效 handle、真实 owned 嵌套进程 Job 回收/同轮 outside sentinel 保活，以及旧缓存对象不冒充 fresh 身份。helper SHA `89D26C6612185B0421E49734896DEF89CC47BE39C9C600522B18C497602E3C39`。这是测试工具边界收紧，不声称此前实际停止过其它应用，也不要求重建产品或重做无关 P0。

最终正常根 `ardot-packaged-api-final-2af91b4c73` 已在 `c24b7e32f1a161a7e0dc9ae4a81b6638ecf22ce1` 的新验收入口下实际退出 0，31/31；control 0、survivors=[]、measurement_thread_stopped=true、payload_membership_unchanged=true。packaged=true、diagnostic_observation=false，13 个实际包模块与 payload 源码 SHA 相符，验收入口和 ownership helper 与 provenance 相符。独立核 1,347 条采样，含 18 条合法 pythonw.exe，全部为本次 Job 成员，父子创建时间有效，没有未知镜像或无效归属项；自产 PDF 的大小/SHA 也匹配。API result SHA256 `F1B91D86C19187FD60487CF1589BD35E506D49A1E3C4BBB5AC6D3E4ADCE13DE4`，provenance SHA256 `EC428A727D13648947E794EDD1D9367FF311D9E6C8AE4082D5C7DC12321F2F99`。后续正常通过不消除旧 d976 启动/响应超时风险。

交付索引 `docs/verification/native-desktop/ardot-delivery-20261104-bc4e368/delivery-index.json` SHA256 **`CEEA7083E7E4019DB6E850EE6A4E74CEDBD93431509B4BC64B8485967A29EDA5`**，绑定索引源提交 c24b7e3。22 个根、200 个公开运行证据、514 个源文件及 2 个排除摘要的大小/SHA 全部匹配；200 个公开证据均已暂存，逐一读取实际 Git blob 后与原始字节一致，没有依赖 CRLF 转换后的推断。核验时 207 个暂存文件中，没有 EXE/DLL/PYD/PYC、模型、字体、wheel、压缩包或 .local 载荷。

两份旧 API process-samples raw 明确排除，只纳入路径、大小、SHA 和中性原因；它们未暂存。审核者首轮真正误归属的整个 observer 根既未暂存，也未进入当前 HEAD 历史。显式 exclusion 只说明交付范围，不把原失败或未证实归属改写为通过，不制造污染结论。原始 sealed 运行字节保持，产品/文档的独立空白检查通过。

只读终核结果另存 `docs/reviews/native-desktop/ARDOT-FINAL-EVIDENCE-REVIEW-2026-11-04.json`，SHA256 **`84F7A495BF04DB52B31538CB6E49B9B253CD4202157DC2DD0EFD1C071FF0916A`**，passed=true；它是索引之后的独立复核产物，不回填已封存的索引。最终报告与该 JSON 可一并暂存提交。UI 60aa、包 bc4e368、验收/索引 c24b7e3 的身份分别保留；后续文档/证据提交不伪称安装器由最终分支 HEAD 构建。

OS 文件/目录对话框输入、拖放、跨屏 DPI/辅助功能、Geek GUI、GPU、新 UI 的完整性能对照及商业/长文档质量仍单列未验。RenderTargetBitmap 与 150/200% 栅格是运行中 WPF 渲染，不能作为上述系统交互通过；本轮不批准 main、force push、tag 或 Release。
