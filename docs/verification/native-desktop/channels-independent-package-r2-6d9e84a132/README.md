# 独立最终包与证据核验

本根只读取本轮 repo、payload、owned 运行证据及本机工具链；没有启动产品、安装器、翻译任务或网络请求。原始运行根与 PDF 未改。产品提交 a329045840db30a0b60221408f952baac409c345，安装器 SHA256 F80586C92829DE67ADB64D7A0BFC864AE3B11C4F2C831F10F682F45DA5A70236。

- package-review.json：全载荷 16,432 文件/793,023,102 字节；16,431 清单拥有项全匹配，集合仅排除清单自身，路径/重复/重解析检查均无异常；安装器、源码报告、三份锁和许可证匹配。字段 python_source_files 是复用校验器的旧名称，57 项实际为 53 个 .py、2 个 .png、1 个 .json、1 个 .yaml，即产品文件数。
- nuget-content-review.json：SDK 官方 PackageArchiveReader 内容哈希 7/7 匹配锁，ZIP 内实际 runtime DLL 与载荷字节匹配。驱动从前轮复用；其 correction 字段是历史算法语义说明，不表示本轮发生过原始 ZIP SHA512 误判。
- evidence-review.json：保留审核者首次派生比较 false。其数值计算正确，但错误地比较两份解释性 scope 文案，并按大小写比较同一个 SHA256；没有真实产品/资源数值不符。
- evidence-review-r2.json：保留原件后重新只读运行，按数值和哈希语义比较，通过。57 产品文件与 30 native 文件均核当前字节及 Git 归一内容身份；11 个实际 packaged 模块匹配；4 个真实任务完成，输出/保存/交付副本身份匹配。387 个原始采样重新计算通过，未使用实施者已标无效的 Int32 派生统计。
- pdf-body-review.json：PyMuPDF 独立逐页提取10份交付 PDF，共37页。严格正文加公式检查为 false，原件保留：所有译文页确有完整预期回环夹具正文，但 mono 页1–7缺少源公式 E=m c^2。dual 保留公式的源文半页不能当作译文公式通过。
- pdf-body-scope.json：明确限定为真实全页 pipeline 与正文落入，不作语义/公式/复杂版式质量断言。恒定回环服务对每个文本块都返回同一句，包括方程文本，不能据此确认真实服务翻译质量，亦未证明本次改动引入算法回归。
- pdf-text/ 是逐页原文提取；pdf-render/ 是 Poppler 只读渲染。审核者查看了原文/mono/dual 页7及 mono 页1/4；mono所有7页已生成渲染。页面1水印靠近标题，亦不把本轮称为版式质量通过。运行 WPF 六张关键图另外只读查看，包括窄窗、页7、保存与深色。

源/包身份与实际运行范围不同：完整新功能流程使用冻结源码构建的 DEBUG WPF 外壳和本轮最终 Release payload；Release EXE 另有窗口/私有 CLR/无凭据401烟测，控制器终止实际-1，不是正常退出、OS输入或完整认证流程。OS对话框/拖放/跨屏DPI、实际提供方质量及完整性能/安装生命周期未在本轮重新通过。

完整裁决位于 docs/reviews/native-desktop/LOCAL-CHANNELS-BATCH-FINAL-REVIEW-R2-2026-11-04.md；本根完成后冻结，不回填未来交付索引或审核文档。
