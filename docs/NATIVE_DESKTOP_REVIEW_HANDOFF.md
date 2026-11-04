# 原生桌面本机复审交接

最新用户五项需求的实现分支为 `codex/channels-batch-output-2026-11-04`，产品冻结 `a329045840db30a0b60221408f952baac409c345`。渠道记忆/探测、全页、批量、源目录平放、目录切换与中文输出版本的当前包、测试和独立审核请先阅读 [本轮交接](CHANNELS_BATCH_OUTPUT_HANDOFF_2026-11-04.md)。后续历史包和 UI 报告保持原样，不是新版下载指向或本轮通过结论。

后续用户要求按 Ardot 原版重做组件化 UI，最新功能分支 `codex/ardot-component-ui-2026-11-04` 的交接见 [2026-11-04 组件界面报告](ARDOT_COMPONENT_UI_HANDOFF_2026-11-04.md)。下文保留上一轮 be3147e 的证据与包身份，不能当作新版界面的验收或下载指向。

本机Windows重新生成运行证据，不继承旧电脑缺失证据。分支 `codex/native-desktop-implementation-2026-11-03`，交接基点 `ab5d684df52aa1ec760eb25bc777932003b984b7`。精确最终构建与交付索引见末尾；历史工单/审核保持原样。

## 安全门与环境

先修复P0路径可移植性、recovery8/4、OutDir大小写覆盖、entry-run封存扫描、矩阵选择、唯一输出根、attribution拒绝复用、资产负向与checker自测。独立克隆完整执行冻结24+4，最终checker实际0，并获未参与实现的代理复审，然后才实施产品。详见[状态文件](NATIVE_DESKTOP_IMPLEMENTATION_STATUS.md)和reviews/native-desktop/LOCAL-P0-*。

便携工具在 `D:\student\翻译\toolchains`：SDK10.0.403 / 私有运行时10.0.14、uv0.13.7、Inno6.7.1；CPython3.12.13和134项哈希锁依赖在忽略的.local。未改全局PATH/代理/系统SDK；只有测试安装器写自己的独立HKCU AppId并核清理。资源182项352451566字节，模型/字体不提交Git、不进安装包。下载准备与离线P0测试分开。

## 实现与验收映射

| 需求 | 当前行为与验证 |
| --- | --- |
| 原生产品 | desktop/PDFMathTranslate.Desktop默认替代WebView入口；实际Debug/Release构建、窗口运行。复用锁定WPF UI/Toolkit官方包与许可证。 |
| 工作台/语言 | 原生导入/拖放处理、显式语言对、预览、有效引擎/输出/目录和提交。27项.NET含空路径回退、不常见语言/空选项；真实WPF设置API读回fa/更新opt-out。 |
| 同步 | 共享行、增量/快照序号和实例识别、revision/终态保护；隐藏页面不清选择。outbox保留丢响应/重启的原key，旧响应不能清新操作。Python/.NET/实际WPF流程覆盖。 |
| 保存 | 默认目录持久化、任务覆盖；PDF名_日期目录/版本；durable计划、排他建名、SHA回执、待验证和重试。真实UI丢响应恢复仍2文件，显式二次保存4文件。 |
| 真实引擎 | 原BabelDOC0.6.2+回环LLM夹具（只替代远程文本服务，未模拟排版算法）；真实PDF/PNG/回执SHA。包级provenance证明确从payload导入，不混repo overlay。未做商业服务质量验收。 |
| 取消恢复 | 有界启动/停滞超时、Job进程树回收、观察Future、读到EOF/finish；阻塞stdin取消与下一任务、实际接口取消重试有测试。偶发准备超时仍在风险表。 |
| 资源 | 空闲不载入ONNX/布局，资源准备单独进度/取消；并发1，线程/QPS分开，最终值入快照；CPU provider默认，预览分页/边界/取消/缓存有界。 |
| 数据 | 此前127项pytest包括全部GUI password字段脱敏、事务回滚、单写者、导出TTL/清理、SSE ticket/Origin/Host/token；零外联、独立home/隔离哨兵不变，不读取真实用户缓存作比较。复审新增回归见最终索引。 |
| 兼容 | Python CLI/Gradio源码、显式LegacyWebView仍留；旧入口共享home/单写者、随机token stdin和精确源注入。旧.NET编译0、真实HTTP6项0，旧WebView GUI未测试。 |
| 更新 | fork Releases/latest.json、版本比较、SHA、旧opt-out迁移；错/缺hash和越界重定向拒绝；关闭文件后校验，启动前复验；启动失败保持后端；预览正式源请求0。原项目没有发布者签名验证。 |
| 安装 | 中文EXE/路径/可选快捷方式/标准卸载元数据；拥有清单+SHA+祖先reparse检查；未知/修改文件和home/输出保留。中文分隔符实际缺陷已修，失败与两编码修复测试均保留；最终全矩阵见索引。 |

## 当前证据入口

以下相对 `docs/verification/native-desktop`，不同批次不能替代另一个版本的全部验证。

| 批次 | 结果和范围 |
| --- | --- |
| p0-delivery-20261103-c72fd7361c | P0字节镜像；28覆盖/23负向/26变异；实际0。绝对路径checker用原克隆。 |
| p1-pytest-8e3a98cddf | 复审追加修复前的127 passed/74 warnings/258.60s；实际0、零外联、隔离哨兵不变。不能代替追加修复后的全量运行。 |
| p1-api-ui-fc01d7d9e0 + p1-ui-flow-4f51ca0917 | 当时31项API+WPF流程；真实翻译/首页预览/丢响应/多版本。旧DEBUG尚无译文第二页断言，不能据此说第二页翻页已测。此后文案和更新偏好有修订，旧图底部长notice是修复前状态。 |
| p1-ui-controls-e8b13908eb | fa/opt-out读回、缺安装器仍保持真实health；实际0。部分图截在导航动画中，不作最终可读图。 |
| p1-final-package-e2e19a08a4 | R9包级API30项0，packaged=true/实际模块路径及10SHA，结果绑定provenanceSHA。其后Python未变，C#路径/安装清单修复另测。 |
| p1-legacy-f804de3c05 | 认证200/无token401/设置200/错Origin403/单写者拒绝/正常退出，6项0。 |
| p1-perf-8eadc0a4be | 3次进程冷启、约300s实际WPF+控制面空闲；CPU/private/thread/disk/load原始样本。OS缓存未清。 |
| perf-before-20261103-929f769531 | 同机旧后端300.3s离线基线；不是旧完整桌面，旧翻译无成功吞吐。 |
| p1-independent-workerdiag-20261103-7b5963a01e | 独立真实30项0；20.9s ONNX初始化、43s字体加载栈；不证明120s失败根因已修。 |

## 性能口径

旧后端private末值986.2MiB；新WPF Debug空闲private均值133.1MiB（峰155.1），控制面均值48.3MiB（峰48.5），另有约1.3MiB conhost。旧GUI未测，不能称整个应用减少95%。UI的300s CPU增量3.890625s（单核1.30%）、控制面0.515625s（单核0.172%）；12核归一化约0.108%/0.0144%。旧后端同机归一化0.0133%，**没有控制面空闲CPU改善的结论**。

三次窗口1659.6/859.0/866.9ms、API4287.3/2953.4/3011.9ms、资源5767.2/4298.7/4436.1ms；分别观察，不以stdout替代API ready。新旧方式不同，不报告启动改善百分比。

包级翻译样本记录整个进程树CPU/private/thread/disk，活动峰值仍达数GiB；按需加载把占用从空闲移到翻译期，不等于翻译零模型占用。GPU未采样、系统冷/热缓存未控制、长文档/商业吞吐未测，均不报推测值。压缩包/解压安装/资源/缓存分别记，Gradio是旧slim已有排除，不算新增优化。

## 图像与人工边界

PNG是实际运行WPF visual tree/生产ViewModel和API/真实HWND的RenderTargetBitmap，非外部设计图。980DIP和150%/200%栅格图仅检查渲染，不能证明系统DPI。详见 `reviews/native-desktop/LOCAL-UI-AUDIT-2026-11-03.md`。

computer-use两入口均在初始化报 `failed to write kernel assets: 系统找不到指定的路径 (os error 3)`。未用shell输入注入绕过。**未验证**：原生文件/目录对话框点击键盘、OS拖放、跨屏DPI、读屏/高对比、Geek GUI、安装向导逐页点击。标准注册表发现与静默EXE生命周期另用实际测试，不能由读脚本推断。

## 失败与风险

1. `p1-ui-current-121182c049` 首任务120s准备超时，未进入UI流程。同10模块/解释器/夹具的独立30项成功，诊断见ONNX和字体加载；未受控复现同负载，根因仍未知。有界错误/重试存在，不称故障消失。
2. `p1-install-fde31af299` 前6项通过，Release未启后端；已证明null环境清理留下空字符串，旧回退误用空目录。现RuntimePaths忽略空白，明确app-relative私有.NET；最终包必须另测。
3. 中文owned卸载残留的BOM-only尝试失败。日志显示Pos字节索引与Copy字符索引混用；UnicodePos统一字符单位，保留路径防护。失败与修复前后真实测试保留。
4. 安装检查/删除不是抵抗恶意并发替换的原子操作，不宣称防管理员TOCTOU；未知/修改文件主动保留。
5. SHA256不是发布者签名；更新假feed不执行假安装器，真实EXE生命周期由独立测试安装器覆盖。线上Release/tag/latest.json未改。

多轮独立审核找到并关闭快照、导出锁、worker收尾/子进程导入、更新偏好/失败恢复、源码集合/安装预检阻断，见 `LOCAL-P1-*`。最终总审仍须读最新diff、包provenance、完整安装矩阵、可读图像和测量边界。供复审分支不意味着可合并/发布。

## 最终交付索引

最终交付根：`verification/native-desktop/p1-delivery-20261103-fd15e99f98`；任务跨到2026-11-04继续执行，分支保留原任务日期。

- 最终洁净构建R11：`dist/native-cc12e21d7a4e/build-report.json`在报告完成时记录`a2ddb929d4cc29805db03cd80f6ba49c1b99b411`、source_dirty=false；product-source.json在复制时记录`d6522783446b03e94d6ec90d118e393062a84fa4`。这是两个实际时点，不能称整个构建只在同一commit冻结。Python产品最后修复在9a2a052，55文件经独立复审确认当前repo/包内双侧SHA与精确集合一致；后续改动为legacy构建/回调、DEBUG验收和文档，Release不含DEBUG验收代码。不将Git时刻替代具体文件SHA。
- 安装包：`dist/native-cc12e21d7a4e/PDFMathTranslate-Setup-2.9.0.exe`；224832521字节；SHA256 `B1F78B5E555AB6F1A6D4E428A1AD71C2D7F43E6BE7FE33093F32A0E0AB3945CB`。预览频道，不生成/发布正式更新源。
- 解压载荷16417文件、790965794字节。受控旧入口参考（同锁定Python依赖/同Inno压缩，非历史Release复现）：784442956字节解压、256831720字节压缩。新压缩包减少约12.46%；解压占用增加约0.83%。不把Gradio的既有slim排除算成新增节省；新省去FFmpeg视频DLL30876160字节和经依赖图验证的测试包，但私有WPF运行时带来体积成本。
- 追加修复后的全量Python：`p1-pytest-final-5c8bee4c23`，130 passed、75 warnings、281.00s，实际0、guard零外联、隔离哨兵不变。原127项批次保留为之前字节的证明。
- 最终.NET27项：交付根`dotnet-final.stdout.txt`/`dotnet-final-run.json`，真实0、程序/程序集/legacy runner SHA记录；本地假feed，无假安装器执行。
- 旧入口：`p1-legacy-r2-066dcafa78`真实HTTP6项0；`p1-legacy-port-final-d20698a885`为生产C# BackendRunner+真实Python+本地占位listener，child实际1、ready=false、收到请求0/认证头0。修复了绑定前发令牌风险与旧回调污染新进程就绪状态。旧.NET编译r3实际0；r2因framework-dependent与单文件压缩参数不兼容失败，原日志同样保留。
- 新取消/上传回归：真实TCP断连杀慢renderer、等待锁的过期页不spawn、下一页200；资源取消线程闸门；长文件名保扩展名；强制UUID碰撞409且原文件SHA不变，均在130项中。认证改纯ASGI以原样传递断连，不放宽Host/Origin/token/ticket校验。
- R11包级批次`p1-package-ui-final-8c77de603a`：前30项API成功，但随后WPF后台就绪超时、UI exit1；整轮为失败，不能写31/31。失败窗口图在`p1-ui-flow-7e4beed8af`，与旧的worker120s准备失败分别登记。后续原样复跑和完整安装矩阵尚待本节补充。
- 新性能`p1-perf-timing-28e93a6cb9`在截图前计时；第1次进程冷启窗口48605.3/API70833.8/资源70834.4ms，第2次1086.9/2883.4/3963.3ms，第3次1156.1/3420.1/4997.9ms。构建/复制负载并发存在，因果未定，不能删去慢样本或宣称稳定秒开。前述旧resource_ready观测在QA截图后采集，包含截图等待，属于观测上界。
- 该最终性能轮300秒hold、298.5秒实际采样，真实退出0；UI private均值120544775B/峰131928064B，控制面50163894B/峰50327552B。CPU增量UI0.90625s/控制面0.484375s；线程峰37/11；UI读606B写112B，控制面IO0。空闲只见控制面和conhost，无翻译worker。GPU仍未采样。采样前只停留初始工作台，不能把它与已浏览所有页面后的旧UI缓存值直接当额外优化百分比。
- 磁盘映射由交付根storage.json记录：D为WD SATA机械盘，C为NVMe SSD。开发/性能在D；完整生命周期使用C盘独占`PDFMathTranslate-Codex-Install-Tests`中文空格目录，属于不同磁盘/观测口径，不能相减作启动改善。测试安装器采用独立AppId；其16415核心项与R11一致，只有version.json及测试文件/manifest不同，不能称正式AppId安装器已经运行。
- 单页夹具复跑`p1-package-ui-rerun-94088d3c18`（UI `p1-ui-flow-195c364fc2`）的API30项与cleanup均真、control0/残留[]，窗口api_ready=true、真实任务done/sharedref=true，但译文只有1页，DEBUG第二页断言失败，整轮失败。并排双语合法地产生1页，原单页输入不能证明第二页；已保留该失败并改为真正2页PDF夹具，保持页数>=2/index2和原算法。

- 完整安装矩阵：`p1-install-final-68be538f2a`，R11相同核心载荷的独立AppId测试EXE，20/20真、驱动实际0。首装/升级/卸载0；运行中卸载1、junction升级7、锁文件5，原始理由均匹配。标准HKCU发现/版本/快捷方式、淘汰未修改旧文件、保留修改/未知/home用户文件、中文owned删除和注册项清理都有实测。C盘Release进程与后端状态文件观察3832.4ms，范围不是HWND/认证API可用。
- 最终正常两页：`p1-dense-two-page-final-8e8925b474`，32/32真、驱动0/control0/残留身份[]。真正两页密集科学文本和公式，输入PDF/SHA保留；PNG解码尺寸、译文页数>=2/index2均真；未启用诊断hook。13个实际包模块SHA与UI配置源码身份一致。UI `p1-ui-flow-adf14b7393` 实际0、HWND21432256、task done、共享对象、fa/opt-out读回、缺更新安装器后health保持、丢保存响应恢复无重复和四个版本路径全部真。
- 稀疏页失败`p1-two-page-final-b5f2bbafb8`与显式诊断`p1-two-page-diagnostic-4c2fd9617b`均保留；诊断确认为原引擎`BabeldocError / Scanned PDF detected`。诊断hook仅观察本地假提供方的异常并原样转发，不进产品载荷；不将诊断轮当正常通过。密集两页轮保留扫描检测与原算法。该已知原因不解释旧120s/45s启动失败。
- 最终活动树：561样本/153.897秒（含API、预览及等待UI，非纯翻译耗时），private峰2586816512B、线程峰60；观测CPU增量61.03125s、读4862401549B、写17267315B。250ms会漏短进程初末计数，属于下界；采样末尾可能仍有控制面，但关闭后按PID+creation_time另核残留为空，不能仅凭末样本判断回收。
- 最终运行盘占用：交付根runtime-cache-observation.json，独占home总255个普通文件/360288160B；资源目录185文件/352496622B（锁资源有效内容182项352451566B，其余为运行生成内容）、翻译缓存229376B、work暂存64149B、桌面状态29690B、引擎配置21489B、tmp0。未跟随Windows生成的INetCache兼容junction。资源采用已验证离线拷贝，未计首次HTTP传输的协议/重试开销；work为可重试保留输入/产物，不假称整个work缓存有界。解压比较是payload逻辑字节，不含Inno卸载元数据/文件系统分配开销；标准安装注册口径见registered-uninstall.json。

交付索引为 `verification/native-desktop/p1-delivery-20261103-fd15e99f98/delivery-index.json`，SHA256 `F8A8D0B3FB7E810AAE7D6080AAF246266EE879E9E1B473CF04EFD6C600B7F821`；31个运行/镜像根、1511个非EXE证据文件和502个跟踪源码文件有实际大小/SHA。索引生成基点`99925ce148932517e8c910ccbe032e29d23188ef`，它是文件交付身份，不是新执行或补造历史通过。EXE仅在本机dist保留，Git不含模型/字体缓存或测试安装器。

独立最终裁决见 `reviews/native-desktop/LOCAL-P1-INTEGRATED-REVIEW-2026-11-04.md`，新正常32/20及R11逐文件校验另有独立JSON。全部人工OS项、启动稳定性、GPU/旧GUI完整基线及商业/长文档质量仍是待验，不因32/20通过而改成全部P1发布验收通过。实现和已运行验收供功能分支复审，不合并main/不建tag/不发布Release。
