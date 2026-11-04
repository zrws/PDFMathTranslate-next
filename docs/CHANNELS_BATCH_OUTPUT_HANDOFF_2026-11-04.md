# 渠道、批量与输出修订交接

用户提出的五项功能在 `codex/channels-batch-output-2026-11-04` 实施，基于 `74d54222b58f8ab8ab104aabe6eba66978cc6290`。产品与测试代码冻结于 `a329045840db30a0b60221408f952baac409c345`。后续证据/交接提交不改变该包源。原交接 `ab5d684…`、本机 P0 和 Ardot 组件版的历史审核保留；本报告只对本轮明确运行的项目负责。

## 功能与验证

| 用户要求 | 当前实现 |
| --- | --- |
| 渠道管理与记忆 | 具名档案、当前渠道提示、新建/编辑/启用/删除、重启恢复，密钥本机 DPAPI 保护。真实模型列表探测与短请求连接测试；切换草稿取消旧请求，过时结果不能写入另一个渠道。OpenAI 兼容接口支持探测，其它原引擎继续翻译并允许手填模型。 |
| 默认全页与文章记录 | 默认全部页面，隐藏的旧 1–5 范围不会传入任务。历史按源目录与文章名归组，同一文章保留多次翻译记录。超过五页的真实 PDF 验证最后一页。 |
| 保存目录 | 默认目录和方式可单独保存并读回，结果页可改本次目录、改用当前默认目录。按用户后续澄清，源目录模式直接放在源 PDF 旁边；自定义目标按文章建子文件夹。上传时核对源文件 size/SHA，不使用上传缓存目录充当原目录。 |
| 中文命名与准确输出 | `_双语对照.pdf`、`_译文.pdf`、`_术语表.csv`，冲突增加 `_第2版` 等。控件显式双向绑定，创建/引擎接收/导出均过滤未选种类，至少一个 PDF。结果页仅可选实际产物。已有计划和旧幂等指纹兼容。 |
| 多份文件和排版 | 待处理 DataGrid 支持多份、移除、清空与逐份提交；一次批量固定渠道/revision、语言、页码、目录和输出。中途切换渠道不改变已开始的批次，部分失败保留未提交文件。固定主操作、可滚动参数区、文章组和版本卡片均使用 WPF UI + XamlFlair；无 CSS、自定义皮肤/动画实现。 |

## 密钥与迁移整改

独立审核发现并修复 C01–C04：原生 TOML/事务日志/旧明文备份的密钥泄漏、批量提交时渠道改变竞态、模型探测过时回写、慢速滴流绕过请求时限。档案中仅存 DPAPI 密文；API/任务/日志不回显密钥。旧配置先建立可恢复原始字节的 DPAPI 归档，再持久化 prepared 标记、发布脱敏配置并提交标记；两个故障点均有重启恢复测试。旧自有明文备份仅在加密归档校验和标记持久化之后移除，用户来源文件不修改。文件及祖先 junction/reparse 越界拒绝，独立目标哨兵不变。DPAPI 归档绑定本机 Windows 用户，不充当跨机器密钥备份。

渠道探测总时限 15 秒、两项并发、512 KiB 响应上限、不跟随重定向，断开/取消释放槽位。任务快照包含渠道非密钥参数；整批传显式 id/revision，配置改变返回 409，重试按原渠道与当前已保存密钥恢复。

## 本轮运行证据

路径均相对 `docs/verification/native-desktop`；原始失败与成功目录分别保留，不修改已结束运行记录。

- `channels-full-pytest-fee2387c5d`：146 passed、74 warnings、246.71 秒，实际退出 0。运行时尚未提交；source-identity.json 绑定所有桌面 Python 和 config/main.py、http_api.py，冻结时逐项重核无差异。
- `channels-validation-5fbed8bf46`：最终 Debug publish、27 项 .NET、组件约束均实际 0。frozen-source-binding.json 补充冻结提交与 DLL/测试程序集身份，不替换原 completion。
- `channels-workflow-abc0265562`：实际 WPF 控件/生产 ViewModel/回环 API/原 BabelDOC 完成三份 7/2/1 页 PDF，再做第 4 个七页仅译文任务；进程退出 0，未残留自有身份。测试提供方仅替代远程文本回答，排版与生成仍是真实引擎。全页、批量渠道快照、单输出、源目录平放、自定义目录切换、中文版本、丢响应幂等、三文章分组、重启与密钥不落明文均通过；pdf-audit.json 独立读回四份 PDF，七页产物末页含中文。此轮使用 repo overlay 与较早 Debug DLL；后续仅压缩进度卡空态并增加任务渠道说明，最终包运行另行列出。
- `channels-unit-26469f8a4f`（10 项）、`channels-backend-tests-f912db548b`（42 项）、`channels-migration-tests-46a4155f4b`（15 项）是逐步整改记录，最终 Python 总体验证以上述 146 项为准。

失败留存：`channels-workflow-1536162aeb` 主进程 0 但无 UI 结果，不能当通过；`e07f88b9b3` 实际 1，启动诊断确定缺 VisibleWhenFalse 资源，已补；`776c4185cd` 实际 1，980 布局裁切源语言选择，已压缩上传区；`d079cd54bf` 布局运行 0 但第三行视觉不完整，未作为三文件布局终验。`abc0265562` 增加三行完整可见断言后通过。

## 交付边界

仍保留 Python/BabelDOC、CLI/显式旧入口、私有 .NET、中文安装卸载和假 feed 更新验证。没有合并 main、tag、Release 或修改线上更新源。安装器逻辑未在本轮修改，旧安装矩阵只作为历史证据；不声称重新执行了整个 OS 向导/Geek/DPI 验收。

图像来自实际运行 WPF Visual Tree 的 RenderTargetBitmap，有真实 HWND 与 API 状态；它们不代表 OS 鼠标键盘输入、文件/目录对话框、拖放或跨屏 DPI 测试。付费提供方质量、超长论文/GPU、旧全桌面资源基线，以及此前偶发 120 秒 worker 准备超时根因仍未验清。当前采样仅包含创建时间/镜像链/内核 Job 核对的自有进程，不据此宣称未测得的资源降幅。

## 冻结构建与本地安装包

`channels-build-5ab91a13ee` 于 2026-11-04 19:27:01–19:40:20（+08:00）离线构建实际退出 0，绑定 `a329045840db30a0b60221408f952baac409c345`、source_dirty=false。134 项哈希锁依赖与锁定 NuGet、私有 .NET 10.0.14、CPython 3.12.13，新增渠道与迁移模块没有增加 Python 依赖。Release 有两条同源 CS0168 未使用 DEBUG 诊断变量警告，未隐去或计为失败。

- 安装包：`D:\student\翻译\PDFMathTranslate-next\dist\native-0814d6ecd733\PDFMathTranslate-Setup-2.9.0.exe`。
- 225,365,325 字节；SHA256 `F80586C92829DE67ADB64D7A0BFC864AE3B11C4F2C831F10F682F45DA5A70236`。
- payload 16,432 文件、793,023,102 字节；拥有清单 SHA256 `AB80DA701122CDADE2B3213BF32618A99F18142A1D4093082BE779D6C50FEED6`。模型、字体、SDK 和用户配置均未装入。
- 相对上轮许可修正包，安装包增加 26,741 字节、payload 增加 79,921 字节；这属于功能增量，不能宣称本轮进一步缩小包体。完整报告副本与产品源集合见 `channels-delivery-20261104-a329045`。
- `channels-release-smoke-54096bd29c` 实际观察到非零 HWND、包内 .NET 10.0.14 的 hostfxr/hostpolicy/coreclr 与无凭据 401。主进程由控制器终止，实际 -1，子进程无残留；不把此项写成正常关闭、认证 health 或翻译验收。
- `channels-workflow-6044de5f3a` 使用冻结 Debug DLL（SHA256 `6685E0BAD394E70B19805235147498353895B941A6B63F85127159A96CEFE548`），layout-only 实际 0，source_dirty=false；覆盖最终空态/任务卡调整和三行完整可见断言，不冒充另一轮完整翻译。

## 最终包级运行

`channels-workflow-d343def72d` 实际退出 0、passed=true，观察错误和残留身份均为空。source_mode=packaged，直接从新 payload 导入 11 个受影响 Python 文件，未混入 repo overlay；启动时 source_commit=a329045、source_dirty=false，全部 native 源文件与上述最终 Debug DLL 绑定。三份 7/2/1 页独立任务和第四份七页仅译文全部完成，完整 WPF 检查、输出选择、源目录平放、当前目录切换、中文版本、丢响应恢复、文章组、重启记忆均通过。原始 JSON、8 张浅深色/窄窗/页七图、实际任务、PDF audit 和采样保留在唯一新根。

为避免只靠中文水印误判末页，交付目录补充 `collect_pdf_evidence.py`、`pdf-body-audit.json` 与 10 份本轮自有原文/产物/源目录保存副本。每个生成/保存副本的末页均实际提取到夹具正文“科学论文译文保留公式与页面结构”；复制字节的 size/SHA 与原件绑定。自定义目录的三个中文版本文件已位于 workflow/ui 内。该补充审计只读本轮源文件，不是另一次翻译测试。

独立正文审核另外检查了公式：该恒定回环提供方把包括底部 `E = m c^2` 在内的文字请求一律回复为同一句中文，mono 与 dual 的译文侧因此未保留该公式，dual 原文侧仍有。严格公式检查的 false 原件保留；本轮只证明真实全页流程与指定正文生成，不能据此宣称数学公式或语义质量通过。没有把这个夹具结果定性为已证实的本次产品回归，也没有为迎合测试改写 BabelDOC 算法；真实提供方质量仍需单独验收。

窗口图均来自实际 WPF 运行，截图路径为 `channels-workflow-d343def72d/ui`；主界面 `04-batch-ready.png`，渠道 `02-channel-management.png`，结果与目录 `07-article-history-and-save-directory.png`，深色 `08-results-dark.png`。正式 EXE 的启动边界由前述 Release 烟测覆盖，业务视觉流程由冻结 Debug 与包内后端覆盖，不把两者混为同一可执行文件。

本轮包级流程观察到窗口就绪约 1.16 秒、API 就绪约 6.36 秒，整段流程 255.72 秒；不是冷/热启动基准。387 次受内核 Job/新建进程身份约束的采样中，峰私有内存合计 3,388,551,168 字节、峰工作集合计 3,023,704,064 字节、线程合计峰 100，观察到 CPU 累计 348.9375 秒。工作集合计可能重复计算共享页，CPU 为采样下界；包含 WPF/控制面/预览/真实排版的整段流程，不能当单 worker 峰值或与不同样本旧值直接比较。GPU 和旧全桌面基线未测，不宣称资源降幅。

首个派生统计因 PowerShell Math.Max 的 Int32 重载在超过 2 GiB 时非终止报错，虽然命令返回 0，错误峰值仍无效。该原结果移名保留为 `owned-process-summary-invalid-int32.json`，`derivation-correction.json` 记录原因与替代 SHA；最终 `owned-process-summary.json` 从原始 raw 重新计算。原始进程数据及翻译验收未改变，错误统计不作通过依据。

## 独立终核与交付索引

独立代理未参与实现，阶段报告 [R1](reviews/native-desktop/LOCAL-CHANNELS-BATCH-REVIEW-2026-11-04.md) 关闭 C01–C04 与迁移恢复/祖先 junction 边界。最终报告 [R2](reviews/native-desktop/LOCAL-CHANNELS-BATCH-FINAL-REVIEW-R2-2026-11-04.md) 的机器证据根为 `channels-independent-package-r2-6d9e84a132`，60 个文件已冻结，SUMMARY.json SHA256 `6DADF9128AB394F5263FC325D3CD5879C7827354657156E086DD0E968F62A73E`。

独立逐项核对 16,431 行拥有清单及自身之外的精确文件集合，57 份产品文件（53 Python + 4 资产）、30 个 native 源文件、11 个实际导入模块均与冻结 Git/包身份相符；7 个 NuGet 官方内容哈希及从 nupkg 读取的运行库字节、许可证/NOTICE 相符。最终 WPF 图、37 页 PDF 提取及两张 Poppler 页七图均已复核。package、NuGet、修正后的 evidence-r2 和限定范围的正文 gate 均通过；资源数值经独立重算一致。审核器首次因 scope 文案/哈希大小写比较而产生的 false 原件，以及严格公式检查 false 均保留并解释，未覆盖失败记录或改写通过范围。

`channels-delivery-20261104-a329045/delivery-index.json` 封存本轮 17 个新证据根、每个文件的字节与 SHA、冻结产品/测试来源。只收录本轮受控材料；旧的无关进程元数据原件、所有运行时/模型/缓存/安装 EXE 均未进入候选 Git。索引是交付身份，不替代各轮真实退出码及断言。功能分支仅供复审，不合并 main 或发布。
