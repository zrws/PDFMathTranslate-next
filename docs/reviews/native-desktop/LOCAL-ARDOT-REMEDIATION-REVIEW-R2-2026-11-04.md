# Ardot 组件整改独立复审 R2

本轮产品冻结提交为 `60aa6dc3c40a5b8f44a6b67c271f8d108a82fe97`，基点 `be3147e7867de07c991351ce2e181b5e8eca6ee6`。审核者未参与实现，只读核源码/上游固定源码/已有工件，并按实施者明确授权，用独立构造的 owned junction 夹具运行一轮真实 DEBUG WPF 检查；没有修改产品代码、启动真实外网或付费提供方，也没有操作用户目录。

## 裁决

**初审 A01–A04 在当前源码及 DEBUG 实测范围内关闭，未发现剩余阻断。** 当前五页组合、浅深主题、保存目录和实际输出选中项文字可读。可以继续当前洁净 Release/安装器构建；本报告尚不授予新安装包通过，也不以旧包或旧视觉结论替代新包身份核验。

## 整改核对

- A01：Load 每次先恢复默认，校 JSON Object 根，`null`、数组、字符串和损坏 JSON 按外观警告处理；偏好未读完前 EntranceAnimation=null，不阻断后台 Ready。64KiB 上限和同一 CheckPreferencePath 在读取前生效。
- A02：成功保存统一发 SettingsSaved，设置页清 PasswordBox；顶部和页内按钮共享同一命令。失败保存不发成功事件、保留密钥草稿。实测均真，无需记录或回显凭据证明。
- A03：XamlFlair 的设置 Event=None，页面 Loaded 显式用库 PrimaryBinding trigger 启动淡入，Unloaded 和关闭动效时清 Opacity 动画并恢复 1，库完成命令也归一。没有自写 Storyboard/ControlTemplate。LibraryMotion 的订阅随实际视图加载/卸载，不依赖库一次性 Loaded 订阅。实际观察了动画属性、完成后释放和缓存页再进入，不再将 Primary=null 等同已停止。
- A04：读写均在访问文件前核 desktop 目录和 appearance.json 的重解析属性；保存创建目录后再核一次。独立夹具实际证明已有 desktop junction 不会导入 target 的 dark/true 偏好，也不覆盖 target 字节。
- 主题应用每次刷新系统主题缓存，先设置官方 accent，再切库主题；明确 WindowBackdropType.None。关闭后系统事件退订并检查 disposed，已排队的系统主题回调也检查关闭状态。新的 DynamicResource 引用沿用库官方文本画刷，避免库 TextBlock.Appearance 缓存旧主题画刷。
- 任务行仍来自原共享 TaskStore/TaskRow；队列和输出选择写回有 Loaded/Visible/非 null 门。独立输出页由真实 saved_paths 生成版本卡，不改 SSE、导出幂等或 Python/BabelDOC。未发现原流程被本次视觉重写替换。

## 独立实际运行

本轮干净观察根：`docs/verification/native-desktop/ardot-independent-appearance-r2-64928c986e9e`。入口是独立准备的 scenario，使用生产 DEBUG 应用的验证通道，**不是 OS 输入自动化**。已与父任务协调 AppMutex 空闲；构建负载同时存在，不把此轮耗时当性能基线。

| 项目 | 实际结果 |
| --- | --- |
| WPF 身份 | PID 18200；2026-11-04 10:05:28.7714320 +08:00 启动；10:06:18.8956610 退出；实际 0 |
| 外层观察器 | 实际 0，未超时；20 个通过父 PID/创建时间/预期 exe 链验证的观察身份，退出后无残留 |
| DEBUG DLL | `199EF9736EB4F283AB979131E967682AB0611B4B9414FAB8572FB67C3A11FA12`，运行前后未变 |
| junction 哨兵 | 独立 `.local` home/target，两者均本轮生成；target 为 37 字节 dark/true JSON；读写拒绝均真 |
| 哨兵前后 SHA256 | 均 `5F5599E6231EC5CE632CFFDEFADB56CAB73C99BABC7598B1A10F777E3F8F4783` |
| 动效/偏好/保存 | 真实 Opacity clock、减少后清 clock、完成后释放、缓存重入、坏 JSON 回退、失败保草稿/成功清输入均真 |
| 多文件窄窗 | 四次实际上传同一 owned 两页 PDF，未提交四次翻译；980×680 源/目标和固定主动作边界均通过 |
| 真实译文视图 | 复用刚完成的真实任务，显示译文第 2/2 页；不是合成 PDF 列表或静态图片代替接口 |

实际新图已经独立查看：`04a-four-pending-documents.png`、`04b-actual-translated-page-two.png`、`02b-save-directory.png`、`12-restored-results.png`。四份文件列表保持有界滚动，固定服务卡始终显示语言组合，主动作没有被参数挤出。保存目录组顶部定位正确；输出列表黑底选中项的文件名与语言文字均清晰，版本卡显示真实文件名/路径。先前 b0 的深色与 980 图也已查看，透底问题已消失；首轮透明/窄窗失败和 73cc 弱动效观察均保留，未继承为当前通过。

`driver-observed.json` SHA256：`CBB13B94BFDC8DF53CD9BAE108441C719277991F04C7CF78E9F28FE7C88FBDA8`；`ui-run/ui-result.json` SHA256：`3EA48677D69D6B62D19F1D798922FB41CA4708D7425A5CAD831DBE3F09AF8F9D`。独立重读观察身份，父链均存在且子创建时间不早于对应父身份；不是仅按 PID 数字查残留。

## 第一轮观察器错误的保留边界

独立第一轮 `ardot-independent-appearance-8d1c22abf146` 的 WPF 本体实际 0，junction/控件检查通过，但审核者自写外层观察器漏核创建时间，按陈旧 ParentProcessId 误归属其它进程，最终外层实际 1。这是观察器 false positive，不能改写为产品失败或原轮外层通过；没有停止或修改误识别的进程。

原始 `driver-observed.json` **仅在本机保留，明确排除 Git**；本报告不复述其中无关进程元数据。其本机绝对路径为 `D:\student\翻译\PDFMathTranslate-next\docs\verification\native-desktop\ardot-independent-appearance-8d1c22abf146\driver-observed.json`，46,335 字节，SHA256 `BFE7CD9DCA3B5C200715391FB2B86D12C201CA24559FD1C2F25E5CCDCC3D8706`。可公开的 `observer-error-summary.json`/本轮 `previous-observer-summary.json` 仅包含本轮自身身份、实际退出、排除理由和原件 hash，不包含无关身份列表。

R2 修正为查询前后验证活父 PID+创建时间+exe，WQL 限子创建不早于父、预期镜像白名单、再核实际子创建时间，只沿通过链继续观察。R2 源码与原失败源码各自保留，不覆盖旧记录。仅本次启动的 WPF 可以在超时时被 driver 回收，观察器没有向其它应用发停止命令。

## 证据组合与剩余范围

真实两页完整 API/WPF `ardot-two-page-32f2c2f6f9` 32/32、control 0/无残留，以及 UI `p1-ui-flow-c3a603904d` 的真实任务完成、共享引用、第二页、丢保存响应恢复、四版本/卡片，属于此前 aea9 同批 UI 字节；其后固定语言 Caption、选中文字继承和 DEBUG 布局验证变化，不能把旧轮说成 60aa 全部字节执行。当前独立 60aa 轮补了这些新显示/边界/路径行为，没有再跑一次翻译。

还须核新 Release/安装包 hash、锁定依赖及许可证载荷、构建与当前源码的绑定和最终交付候选范围。原生文件/目录对话框输入、OS 拖放、跨屏 DPI/辅助功能、Geek GUI 及旧启动稳定性限制继续保留；RenderTargetBitmap 与 150/200% 栅格渲染不改变这些范围。P0 没有受本轮界面改动影响，不要求重做已关闭的无关安全矩阵。
