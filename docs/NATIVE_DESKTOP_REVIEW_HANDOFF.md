# 原生桌面本机复审交接

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
| 数据 | 127项pytest包括全部GUI password字段脱敏、事务回滚、单写者、导出TTL/清理、SSE ticket/Origin/Host/token；零外联、独立home/用户哨兵不变。 |
| 兼容 | Python CLI/Gradio源码、显式LegacyWebView仍留；旧入口共享home/单写者、随机token stdin和精确源注入。旧.NET编译0、真实HTTP6项0，旧WebView GUI未测试。 |
| 更新 | fork Releases/latest.json、版本比较、SHA、旧opt-out迁移；错/缺hash和越界重定向拒绝；关闭文件后校验，启动前复验；启动失败保持后端；预览正式源请求0。原项目没有发布者签名验证。 |
| 安装 | 中文EXE/路径/可选快捷方式/标准卸载元数据；拥有清单+SHA+祖先reparse检查；未知/修改文件和home/输出保留。中文分隔符实际缺陷已修，失败与两编码修复测试均保留；最终全矩阵见索引。 |

## 当前证据入口

以下相对 `docs/verification/native-desktop`，不同批次不能替代另一个版本的全部验证。

| 批次 | 结果和范围 |
| --- | --- |
| p0-delivery-20261103-c72fd7361c | P0字节镜像；28覆盖/23负向/26变异；实际0。绝对路径checker用原克隆。 |
| p1-pytest-8e3a98cddf | 最终Python功能字节127 passed/74 warnings/258.60s；实际0、零外联、哨兵不变。 |
| p1-api-ui-fc01d7d9e0 + p1-ui-flow-4f51ca0917 | 31项API+WPF全流程；真实翻译/分页/丢响应/多版本。此后文案和更新偏好有修订，旧图底部长notice是修复前状态。 |
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

最终构建/安装/图像批次和独立总审完成后填入；该段空缺期间不作为最终完成凭据。
