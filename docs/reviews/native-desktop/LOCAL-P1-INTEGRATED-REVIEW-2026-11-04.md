# P1 实现与交付证据独立总审（2026-11-04）

本报告由未参与产品实现的独立审核者编写。范围是完整工单、当前源码/差异、原始本机工件及文件身份的交叉核对；没有代改实现。本次总审只运行只读文件/JSON/哈希核查，没有再运行产品或安装器。此前经单独授权执行的一轮回环 worker 诊断，另见 `LOCAL-P1-WORKER-STARTUP-DIAGNOSTIC-2026-11-03.md`，不能与本次审查合并成新的产品运行。

## 当前裁决

**允许将本次已审实现、证据与文档正常提交并推送 `codex/native-desktop-implementation-2026-11-03`，供下一轮复审。** 代码与已运行必需流程复审通过：没有尚未处理的安全或数据一致性代码阻断，R11 核心载荷完整安装生命周期 20/20、正常两页 API/WPF 32/32 均已核实，交付候选清单及 Git 内原始证据字节已终核。尚不能宣称全部 P1 人工验收或启动稳定性通过。本裁决不批准 main、force push、tag、Release 或改写线上更新源。

最新 `p1-package-ui-final-8c77de603a` 的前 30 项真实包 API 检查为真，随后实际 WPF 启动失败，第 31 项为假、整轮失败。不能将这一批写为 31/31，通过的旧 UI 批次不能覆盖本次失败。失败的真实窗口记录在 `p1-ui-flow-7e4beed8af`：`api_ready=false`、错误为后台操作取消/超时。当前没有该 WPF 子后端 stderr，不能认定其与原 worker 120 秒准备失败同因，也不能认定合成 HOME 或机器负载已被证实为原因。

随后原样复跑 `p1-package-ui-rerun-94088d3c18` 为 API 30 项真、回收真（control 0、采样身份无残留），但 UI `195c364fc2` 仍失败：此次 API 12.295 秒就绪、真实任务 done、共享引用为真，失败点是新第二页断言。实际一页输入、双语输出 `/Count 1`，未启用 alternating-pages；请求第二页被正常夹到第一页。静态字节核查旧成功双语 PDF 也是 `/Count 1`。这是具体的夹具与“至少两页”断言不相符，不能通过删断言冒充多页验收，应采用真正多页输入后保留第二页要求；不据此认定翻页产品代码有错。

第一轮真两页 `p1-two-page-final-b5f2bbafb8` 又有独立失败：上传 2 页和 1600×2265 预览边界通过，真实引擎在“检查扫描页”阶段失败，未到 UI；control 0、回收无残留。现有通用错误工件没有原异常类型，不能把原因写死。静态源码提示锁定 BabelDOC 对一页跳过该检测、两页开始检测，稀疏合成页可能触发扫描页判断；这只是有出处的排查推断，后续应保留检测和算法，用有效科学文本夹具及原始异常核实，不能关闭检测来凑通过。

其后独立诊断批次 `p1-two-page-diagnostic-4c2fd9617b` 的 opt-in 测试 hook 记录 `worker-error-28372.json`，真实异常为 `BabeldocError: Scanned PDF detected`，证实该次稀疏夹具被原引擎扫描页检测拒绝。审核了 hook 的限用 fake loopback 凭据检查、异常观察和原样 pipe 转发；它不进产品载荷，provenance 明确 diagnostic_observation=true，不能作为正常验收通过。新的密集两页夹具仍保留扫描检测、公式、原算法、第二页和尺寸断言，最终须以未启用 hook 的正常轮证明；这个诊断不解释前述启动超时。

最终正常轮 **`p1-dense-two-page-final-8e8925b474` 32/32 通过**，`diagnostic_observation=false`、packaged=true。亲核 13 个实际导入模块路径/hash、输入与执行脚本 SHA，全部一致；结果与 provenance 的 SHA 绑定一致，双语/单语 PDF 与本轮 owned 原件的 size/hash 一致。真实第二页返回 X-Page-Count=2、X-Page-Index=2，源 PNG 解码后 1600×2265。WPF `p1-ui-flow-adf14b7393` actual exit 0、窗口可见、API ready、真实任务 done、共享引用、fa/auto_update 读回、缺安装器保留健康服务、丢保存响应恢复、四版本文件均真；四个导出 PDF 已逐个查存在并计算 hash。control actual 0，采样过的 PID/creation 身份清理检查无残留。

该正常结果 SHA256 `249F21C5AEE25DE916C2654F113CF2376E90DED28F417128C5E083C06C75AEE1`，UI 结果 `46C664CFEAE683B861A3442E57701A01CC2DAE26678BF5CDCC7C7F0E9FCCD8AC`，provenance `7556A7B95031ED5913EDE9CC7EE3999489F97C76F9229E3309835DAA7C574A91`。独立派生文件为 `P1-DENSE-FINAL-EVIDENCE-REVIEW-2026-11-04.json`；它是只读核对，不是又执行一轮。新 01/06/07b/08 截图已独立查看，主要信息清楚，无新增相互覆盖；980 窄窗依赖已显示的滚动条。空态页码 1/0 仍可作小型文案改善，不阻断供复审。

## 审查身份与 P0 前提

首份总审快照 `P1-CODE-REVIEW-SNAPSHOT-2026-11-04.json` 记录 HEAD `a2ddb929d4cc29805db03cd80f6ba49c1b99b411`、130 个跟踪实现/测试文件，排序哈希行摘要 `ea0ce5dac5422c53b0ce79419320f488b3496e356aacc4c4e711b5a87a2b80bd`。随后仅有测试/记录变动时，不将该快照表述为后续所有文件的同一提交。

P0 已由独立报告认可；冻结源为 `080262216d6a405519097d30b90f09a1ffdb130a`，实际运行根在独立 clone `D:\student\翻译\p0-frozen-fa97b2e6f9` 的 `p0-delivery-20261103-c72fd7361c`。主仓库副本是逐字节镜像，不是第二次执行：28 个冻结覆盖、23/23 矩阵、26 变异全部拒绝、prior/final/外层/WinPS relay 实际 0 的身份与限制见 `LOCAL-P0-DELIVERY-FINAL-REVIEW-2026-11-03.md`。没有继承缺失的历史运行通过结论。

## 已关闭的实现阻断

- 后端仍为 Python/BabelDOC；默认桌面入口是真正 WPF、.NET 10、WPF UI、CommunityToolkit.Mvvm，没有把 WebView 包装当原生升级。配置/语言/术语与原 HTTP、CLI、更新路径的兼容代码保留。
- 控制服务只监听回环，用 stdin 交换随机会话凭据，argv/环境/URL 不存 token；Host/Origin/Bearer 及一次性短期 SSE ticket 均失败关闭。纯 ASGI 鉴权保留原 receive 通道，关闭了 BaseHTTPMiddleware 吞断连的问题。更新下载仍限制来源、重定向、体积及最终 SHA。
- Engine 明确监督进程退出、stdout collector 排空、Future 和阶段 deadline；协议结束标记不再冒充进程 EOF。取消和 Job 对象覆盖真实 Windows 子树，任务失败不会停留在“准备中”而无终态。
- 保存/重试 outbox 使用持久稳定操作 ID；丢响应后重放、重启恢复与历史清除后的 tombstone 保留有针对性证据。完整非密钥设置及术语内容冻结；供应商凭据字段以真实字段定义剥离，重新执行只注入对应当前凭据。导出大 I/O 不持任务 Store 全局锁，多版本文件不覆盖。
- TOML 与桌面偏好跨存储更新有 prepared/committed journal、恢复和内存回滚；已有 TOML 迁移标记前仍会执行独立旧 ui-prefs 迁移，旧 auto_update=false 得以保留，当前偏好不会被覆盖。
- SSE 使用同一 TaskRow 引用并按 ID 恢复选择，提交/进度/完成在工作台与任务页共享状态。少见语言代码保留；下载目录、取消目录选择、双语/单语、恢复保存、版本号与打开结果/目录均有实现和分项运行。
- 预览的唯一 communicate task 被 shield，断连包含等渲染锁期间，finally kill+drain 回收真实渲染子进程；资源下载开始前的取消及线程闸门取消进入统一终态。长中文文件名保留 `.pdf`，上传碰撞返回 409，只删除本次实际创建的文件。
- 兼容旧 launcher 在精确 bind/listen 成功及 uvicorn.started 后才输出带本轮 PID 的 ready。父进程收到本轮精确 ready 前不发 HTTP，HTTP 不自动重定向；每轮独立不可变 expectedReady 和事件，不会由旧回调满足新一轮。最终真实占位端口 probe 为 child exit 1、ready=false、请求 0、Authorization 未发送。
- PDF 保存/字体子集两个轻量 spawn target 的操作、参数、异常和 os._exit 契约与锁定 BabelDOC 0.6.2 原函数 AST 一致，仅 native policy 环境下替换目标，未改排版/翻译算法。CPU 层级、全局主/术语请求预算和 GPU 默认关闭保留。

## 构建、安装与更新边界

R11 是新建依赖环境与新 payload，未使用被弃用的 finalize 收尾入口。Python 哈希锁、NuGet 锁和补丁锁均记录；复制器只读 Git NUL 跟踪清单，拒绝 reparse 祖先，并比较包内源码精确集合。源和包 55 个 Python 文件的实际 SHA 全部匹配、无额外/缺失文件。

R11 `product-source.json` 的复制时提交是 `d6522783446b03e94d6ec90d118e393062a84fa4`；`build-report.json` 的完成时提交是 `a2ddb929d4cc29805db03cd80f6ba49c1b99b411`。两者不是同一时点。当前 Python 字节一致，后续差异属于 legacy 构建或测试辅助代码，不能把整个包说成单一提交同时冻结。

R11 安装器 `dist/native-cc12e21d7a4e/PDFMathTranslate-Setup-2.9.0.exe` 实际 224,832,521 字节，SHA256 `B1F78B5E555AB6F1A6D4E428A1AD71C2D7F43E6BE7FE33093F32A0E0AB3945CB`；源码报告 SHA256 `CE0B6D575C547113E6796C562488A7083CD7B8F4375FE6D2249B6797AAB44E19`。这是构建产物身份，不替代安装运行。

独立 `P1-R11-PAYLOAD-HASH-REVIEW-2026-11-04.json` 另核了清单 16,416 项的全部实际字节，全部 hash 匹配；payload 16,417 文件，只有清单自身不在拥有项中，没有其它额外文件。清单 SHA256 `695019777011DBEC60A3AE085EFBDDD2D20EFE33EB72089900F85E67F9CA0311`，build-report SHA256 `3910EE78285E7C1C820A4E0CC771892853E7D2A3714492E63F37105E2864BFB1`。

安装器不以目录递归删除用户文件；仅清理清单拥有且内容 hash 一致的程序文件，修改/未知文件和配置/缓存/输出保护根保留。PrepareToInstall 验证所有新增路径与元数据祖先，拒绝 junction、错误类型和未知错误。UnicodePos 的字符索引修复保留全部路径防护，并非仅增加 UTF-8 BOM。新最小两 BOM 安装/卸载、真实注册项先存在再消失均实际 0，详见路径复审；完整新批次结果如下。路径属性检查与删除之间不是对抗同用户恶意并发替换的原子操作，未超出本轮证据范围。

`p1-install-final-68be538f2a` 的 20 项检查全部真，首装/升级/卸载实际成功。它是 R11 相同核心载荷、独立 AppId 的测试安装器，而非正式 AppId EXE：首版 SHA256 `735F7ABD8787BAF550DE19ADCA8E472DEA2CFF3EAC1390742CCE2CB5D5D77A43`，升级版 `FDF49E7D28B390FD04EA23BB9EBAD0439ED178A56EE23DC18192C90BCDB74C52`；测试 stage 清单与 R11 相比，16,415 核心项 hash 相同，只有 version.json、manifest 和预设测试文件不同。

独立核对了原始日志：运行中卸载 exit 1 明确因程序运行，junction 升级 exit 7 明确为 PrepareToInstall 拒绝链接路径，锁定文件 exit 5 明确为 Win32 错误 32，不能只凭非零认负向通过。Release PID 23820 在真实 C 盘中文空格目录启动，3.832 秒只表示后端状态文件观测，不是已认证健康或窗口就绪。注册记录含显示名称/版本/安装位置/卸载及静默命令/EstimatedSize；精确 HKCU 测试键卸载后独立只读核实不存在，快捷方式检查通过。安装目录最终只剩预期的用户说明、修改 owned 文件、home 用户译文三个文件；主程序和中文 owned 文件已删除。结果 SHA256 `CD6E1576EF96C2062A9F18F75F5C8A5D1CF84C7E74C7EAE4B378DF59D4C4A149`，执行脚本 SHA256 `37B9822DE5A8DF460A804837032DBE67825E22E1CE054E37EF28908B3B4FA7AF` 与 input_binding 一致。完整安装必需项在这一范围内关闭，Geek GUI 与向导鼠标操作仍未测试。

自动更新最终 SHA 在启动安装器前复核；成功启动后才关闭服务，失败保留服务及恢复信息。stable 后台检查尊重关闭偏好；preview 不访问正式源。HTTP 使用 .NET 默认环境/系统代理，包括 ALL_PROXY，不强改 7897。legacy 元数据显式保留 stable/preview channel；其完整旧 GUI 安装器未运行，不能声称旧 GUI 全测通过。当前产物未签名；不存在发布/Release 通过结论。

## 证据分层与限制

最新 Python 全量 `p1-pytest-final-5c8bee4c23`：130 passed、75 warnings，隔离哨兵不变、guard 零外联；包括真实 TCP 断连/慢子进程/下一页、等锁旧页不得 spawn、资源线程闸门取消、长名与碰撞。27 项 .NET 协议/模型/更新测试实际 0；这是 Console 测试，不能替代 WPF apphost。旧失败 stdout、安装失败、原 worker 120 秒失败均保留。

真实 UI 旧 31 项批次 `p1-api-ui-fc01d7d9e0` 与新控件读回 `p1-ui-final-48bbb6af48` 各自范围明确，不能代替最新失败批次；旧 UI 记录没有第二页调用与页数检查，不能把旧首页预览称为第二页翻页通过。截图已经过独立查看，中文层级、保存路径和多版本结果可读；它们是实际 WPF 视觉树 RenderTargetBitmap，不是 OS 输入自动化。CUA/Node 初始化失败限制如实保留。文件/目录原生对话框、OS 拖放、跨显示器 DPI、键盘/读屏/高对比及 GeekGUI 仍需人工验证，不能以缩放渲染冒充已通过。

独立 worker 诊断实际 30 项 API 完成，只证明其新轮能完成。20 秒栈在 ONNX Session，43 秒栈在字体初始化；后续持久 task 状态不能代表持续准备状态。原 `p1-ui-current-121182c049` 120 秒超时没有当时栈，不得声称根因已定位或已经修复。本次 WPF 45 秒失败也必须单独保留。

已有 300 秒闲置数据和三次 process-cold 启动，不是 OS 冷缓存。进程采样不等于硬件 GPU 测量；后端默认 CPU policy 不证明 GPU 利用率。旧基线只有旧后端而无成功旧全 GUI/翻译吞吐对照，不能宣称所有 CPU/内存/速度指标均改善。旧资源 ready 数字包含截图时间，应标观测上界；先计时再截图的新批次单独报告。

新计时 `p1-perf-timing-28e93a6cb9` 实际 0，300 秒 hold 的采样跨度 298.5 秒：UI private 均值 120,544,775 字节、峰值 131,928,064，control 均值 50,163,894、峰值 50,327,552；CPU 增量 UI 0.90625 秒、control 0.484375 秒，分别约单核 0.304%/0.162%，线程峰值 37/11。三次窗口/API ready 为 48.605/70.834 秒、1.087/2.883 秒、1.156/3.420 秒，慢的首次样本没有剔除，因此不能宣称启动延迟已经稳定达标。采样来自 Debug 真进程和既有资产；磁盘映射只说明 D 盘 SATA 机械盘、C 盘 NVMe，不能证明本次启动故障原因。CPU 百分比是单核基准，12 逻辑核整机比例需再除 12。

正常两页包级轮的 561 条原始采样跨 153.897 秒、15 个进程身份；独立重新计算与 summary 一致：树 private peak 2,586,816,512 字节、working set peak 2,166,083,584、线程峰值 60，观测 CPU 增量 61.03125 秒、读 4,862,401,549/写 17,267,315 字节。它包含 API 生命周期、预览及等待独立 WPF 流程，不是单纯翻译耗时；250ms 可能漏掉短进程和初始/终止计数，增量是观测下界。最后一次采样仍有控制面/conhost，与之后 shutdown 的无残留检查是不同时间点，不能把“最后采样”冒充“退出后”。没有可比旧多页翻译完成基线，不给优化百分比。

安装测试新增 `InstallParent` 只接受精确的 per-user 独占 `LocalAppData/PDFMathTranslate-Codex-Install-Tests`，不接受任意路径；默认仍 repo `.local`。审核时该父目录尚不存在，全部既存 C 盘祖先为普通目录，未见 reparse；GUID install/backup/sentinel、移动前边界及链接删除前身份核对保留。允许在该现场进行新矩阵。`state_observed_ms` 明确只是 Release 活进程与后端状态文件观测，不是已认证 health 或 HWND ready 时间。

同压缩设置的受控旧 launcher 体积参考为 256,831,720 字节压缩、784,442,956 字节解压；R11 为 224,832,521 字节压缩、790,965,794 字节 payload。压缩减少约 12.46%，解压增加约 0.83%。受控参考未安装/运行，不是历史 Release 复现。模型/字体缓存不计入安装包，首次资源就绪仍需单独报告。

## 必需收尾工件与交付终核

1. 已完成：绑定 R11 核心载荷的新完整安装/升级/修改未知文件/锁定文件/junction/运行中卸载/卸载注册与快捷方式结果；旧失败根没有重写。
2. 已完成：原样产品超时、owned 环境下的新两页真实 API/UI 结果与清理事实；旧失败及诊断分别保留，没有把新轮通过表述为原始启动根因已修。
3. 已完成：性能原始数据、最终交付索引、当前 handoff/STATUS/UI audit 对正常批次、失败、未验事项和体积取舍的核对。

交付 `delivery-index.json` 的实际 SHA256 为 `F8A8D0B3FB7E810AAE7D6080AAF246266EE879E9E1B473CF04EFD6C600B7F821`，基点 `99925ce148932517e8c910ccbe032e29d23188ef`。独立逐项核完 502 个源码与 31 根/1,511 个证据文件的大小及 SHA：没有重复路径、缺失或漂移。全部 1,511 个证据均已经存在于 Git index，另用 `git cat-file --batch` 读取 Git blob 实际字节核其 SHA，全部与原件/索引一致；`.gitattributes` 对 verification 根禁用文本换行转换，原始 Windows 工件字节未因 stage 丢失。

精简候选 `.local/candidate-staged-22e91bc0d9.json` SHA256 `BD8D18462FC2349400278B1741A99B6FA3A841632E42AB7DE743F5CFBA3A62C3`，151 项/36,995,553 字节，集合与当时 `git diff --cached` 精确一致，blob ID/mode 全匹配，没有 EXE/DLL/PYD/PYC/ONNX/字体/WHL 或 `.local` 路径。它是本次尚未提交的新增/改动集，不是整个分支；早已提交内容由源码/证据索引另覆盖。独立终核机器摘要为 `P1-DELIVERY-CANDIDATE-REVIEW-2026-11-04.json`。本报告最后追加及该摘要在 reviews 中，不在 delivery-index 的自引用范围，应另行正常 stage。

`driver-completions.json` 如实注明实际外层退出来源为本轮工具会话完成，未补造缺失 PID/StartTime；此类事后记录与 P0 原始 recorder 不是同一种工件。handoff 已区分 R11 复制时/报告时提交、独立 AppId 安装器、原始启动失败/稀疏页诊断/正常密集页通过、采样末时刻与 shutdown 后检查，并明确仍缺人工 OS 项。安装器 EXE 和大缓存仅留本机，不进入候选 Git。

**终裁：可以推送已审功能分支供复审，无剩余代码或证据交付阻断。** 仍须如实保留人工 OS/DPI/Geek、GPU、旧完整 GUI 基线、长文档/商业质量与间歇启动风险；这些没有被本次分支推送许可改成通过。最终 commit 会在收录本报告后变化，不能把索引生成基点说成最终 HEAD，也不能将推送表述为已合并或已发布。
