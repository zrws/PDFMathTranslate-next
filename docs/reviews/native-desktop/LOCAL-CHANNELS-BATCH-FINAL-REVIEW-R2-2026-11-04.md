# 渠道、批量与输出修订：独立终审 R2

审核分支 `codex/channels-batch-output-2026-11-04`。冻结产品提交 `a329045840db30a0b60221408f952baac409c345`，基点 `74d54222b58f8ab8ab104aabe6eba66978cc6290`。R1 原件保持。本轮审核者只读核代码身份、运行证据、整个自有载荷、NuGet 工具链、PDF 正文/渲染与截图；未启动产品、安装器或翻译任务，未联网或访问真实用户 home。独立核验脚本和观察结果存于新根 `channels-independent-package-r2-6d9e84a132`，该根现已冻结。

## 当前裁决

本轮包、冻结源码、正常功能流程、公开交付索引与 Git 候选通过独立复审，C01–C04 及迁移失败恢复/路径归属阻断均保持关闭，没有剩余的本轮推送阻断。**允许普通提交并推送 `codex/channels-batch-output-2026-11-04` 供复审。** 本文不批准 main、force push、tag 或 Release；也不把回环夹具升级为真实提供方翻译质量、公式或复杂版式通过。

## 新包与冻结身份

`channels-build-5ab91a13ee` 的构建 actual_exit=0。`dist/native-0814d6ecd733/build-report.json` 为 schema 2，source_commit=a329045、source_dirty=false，Python 3.12.13、SDK 10.0.403，版本 2.9.0 preview。

| 工件 | 独立核实结果 |
| --- | --- |
| PDFMathTranslate-Setup-2.9.0.exe | 225,365,325 字节；SHA256 `F80586C92829DE67ADB64D7A0BFC864AE3B11C4F2C831F10F682F45DA5A70236` |
| 完整 payload | 16,432 文件，793,023,102 字节；清单 16,431 拥有项逐文件 SHA 全匹配，集合只有清单自身不入拥有项；无额外/缺失、越界/重复路径或重解析项 |
| owned-files.tsv | SHA256 `AB80DA701122CDADE2B3213BF32618A99F18142A1D4093082BE779D6C50FEED6` |
| product-source.json | SHA256 `391B3A12923EFEAE84AF439CB0588870AFD5AE6B34002F07505201C29FCBBE02`；源/包两侧 57 产品文件字节及精确集合一致 |
| build-report.json | SHA256 `C59FAE5682D7967D5C1D0832680545DD0D3550F7E6788426C5D2CB16638571FF` |

57 项为 **53 个 .py、2 个 PNG、1 个 JSON、1 个 YAML**，不能称全部为 Python 文件。独立通用脚本沿用的 `python_source_files`/`python_source_count` 字段是历史命名，计数解释在 README 与 SUMMARY 明确更正。57 项逐一核当前字节及 a329045 的 Git 归一内容身份，30 个 native 源文件也核当前 SHA/Git 身份，均一致。Git 归一内容检查与源/包原字节检查分别执行，没有把 CRLF 转换混为包字节一致。

Python/补丁/NuGet 三份锁与 build-report 的 SHA 绑定全部匹配，未新增锁定依赖。SDK 官方 `NuGet.Packaging.PackageArchiveReader.GetContentHash` 的 7 个包内容哈希全部匹配锁；从 ZIP 读取的实际 runtime DLL 与载荷全部匹配，不是只核 deps 字符串。XamlFlair、Reactive、Extensions MIT/NOTICE 与 vendored 字节相同，原 SDK/.NET、WPF UI/Toolkit 许可与第三方 notices 保留；SourceLink/Git 构建任务不在 runtime libraries。复用 NuGet 驱动的 correction 字段是前轮历史算法解释，不表示本轮新出现过 signed ZIP SHA512 误判。

压缩比上轮 Ardot 包增加 26,741 字节，payload 增加 79,921 字节。无模型/字体缓存加入载荷；这些体积数字只证明本轮身份和差值，不等于性能改善或历史 Release 重现。

## 正常流程与实际 WPF 字节

最终完整根 `channels-workflow-d343def72d` 的外层 actual_exit=0、passed=true、timeout=false，observer_errors=[]、surviving_identities=[]。source_mode=packaged、source_commit=a329045、source_dirty=false；11 个记录模块实际来自本轮 payload，其 SHA 均匹配。30 个 native 源文件及实际 DEBUG DLL `6685E0BAD394E70B19805235147498353895B941A6B63F85127159A96CEFE548` 绑定一致，R1 之后的进度空态/任务渠道/padding 微调已由本轮新图覆盖。

这轮是冻结 DEBUG WPF 外壳加最终 Release Python/runtime payload 的全功能验收；不伪称 Release DLL 执行了 DEBUG 测试入口。Release DLL `9AEE0927850B5CBA58996DFCCEB257958E0FE1E1A597B864415CEAE8C90C74E3` 另在 `channels-release-smoke-54096bd29c` 正常 EXE 烟测：真实 HWND、实际加载 payload 私有 .NET 10.0.14 的 hostfxr/hostpolicy/coreclr、子控制端口无凭据 401。主进程由控制器终止，实际 exit=-1、观察子身份残留空；这是窗口/运行时/监听烟测，不是正常关闭或认证功能通过。

最终流程包含以下真实断言：

- 两个具名渠道保存、切换、模型探测与回环连接测试；迟到 A 响应不能改 B 草稿；后端重启后渠道、默认目录、保存方式及 DPAPI 凭据恢复。
- 7/2/1 页三份 PDF 实际导入并创建三个不同任务。默认全部页面覆盖遗留 `Pages="1-5"` 草稿；首份响应返回前切 B，三份批量任务仍使用已捕获的 A id/revision。三任务完成、仅有 dual；随后新单语任务完成、仅有 mono，合计四项完成任务。
- 源目录模式每份实际平放 `_双语对照.pdf` 于其源 PDF 旁。单语自定义目录按文章建文件夹；默认目录独立保存/重启读回，结果页另选目录真实生效，中文版本名保留。丢响应 pending 回放不重复文件，后续新保存才增加版本。
- 三文章分组容纳四次翻译，原源 PDF 字节不变；最终后端重启后配置与历史恢复。10 份实际生成/保存路径身份逐份匹配，10 份交付 PDF 副本与原始本轮文件也逐字节匹配。

回环服务记录共 87 次，2 次探测，A/B 非探测分别为 45/40 次，认证不符 0；完整正文请求包含第七页标记。六张最终 WPF 图已独立查看：渠道管理、980 DIP 三行/语言/固定提交动作、正常宽待提交状态、实际第七页、保存目录/文章分组、深色选中项。没有观察到新的裁切、透底、文字对比或共享选择退化。图为运行中 VisualTree/RenderTargetBitmap，未使用 OS 输入自动化。

R1 的本地 Python 146 passed/actual_exit=0 与迁移专项记录保留，不因新包产生而伪造重跑；本轮源码身份核对表明相应 Python 字节未变。`channels-validation-5fbed8bf46` 的 Debug publish、27 项 .NET 检查和组件约束实际 exit 均为 0，frozen-source-binding 补记最终 DLL。C01–C04 的原生密钥脱敏写入/验证前内存恢复、事务回滚、批次渠道固定、探测 generation/取消及总时限链未在冻结后改变。

## 七页正文与质量边界

按 PDF 技能，审核者用独立 PyMuPDF 逐页读取 10 份交付 PDF 共 37 页，并用 Poppler 生成 mono 七页、原文/dual 第七页 PNG；目视检查 mono 第1/4/7页及原文/dual 第7页。所有 27 页译文/保存副本页都包含完整夹具正文“科学论文译文保留公式与页面结构，逐页记录实验结果和有效配置。”，对应 body block 与位置已记录。**这个判断没有依赖 CJK 水印。** 37 页包含源文与保存副本，并非 37 个不同的翻译页。

但上述句子本身不能证明它声称的内容。恒定回环服务会给每个请求块返回同一句，包括源文底部的 `E = m c^2`。mono 页1–7实际缺少原公式，dual 公式只保留于源文半页；第七页渲染已确认替换。第一页还有接近标题的 BabelDOC 水印。严格正文加公式检查 `pdf-body-review.json` 为 false，原件保留；`pdf-body-scope.json` 仅给本轮实际全页 pipeline/正文落入通过，明确 formula_quality 不通过。没有把它改写为公式或版式通过，也未证明这是本次界面/渠道改动引入的算法回归；本轮未修改 BabelDOC 排版算法。真实服务语义、公式、复杂版式与商业长文档质量仍不在通过范围。

## 原始采样重算及派生错误保留

对最终 raw 的 387 个采样点独立使用 Python 整数重新计算：45 个观察身份，accepted Job 成员与父子时间无异常，未知 accepted 镜像 0；私有字节峰值 **3,388,551,168**，采样点内 working-set 之和峰值 **3,023,704,064**，线程峰值 **100**。逐身份最大 CPU 观察值之和 **348.9375 秒**，外层完整窗口 **255.72024989128113 秒**，raw 采样跨度 **253.72316312789917 秒**。

与实施者修正后的统计数值全部一致。旧 `owned-process-summary-invalid-int32.json` 的 Math.Max Int32 溢出派生无效，原件及更正元数据/SHA保留，未引用其资源结论。审核者首份 `evidence-review.json` 亦因错误比较解释性 scope 文案和 SHA 大小写而 false；数值本身一致。该原件保留，重新执行的 `evidence-review-r2.json` 按数值/哈希语义比较为 true，未原地覆盖失败原件。资源数字仅属于本轮 17 个实际翻译页的四任务流程；WS 会重复计共享页，CPU 是采样下界，没有 idle/baseline/GPU 对照或降幅结论。

## 独立核验工件

| 工件（独立根内） | SHA256 |
| --- | --- |
| SUMMARY.json | `6DADF9128AB394F5263FC325D3CD5879C7827354657156E086DD0E968F62A73E` |
| package-review.json | `E57568F7995C1FDD7AE4E2FDD20EB774DFB4567D9D0939CA5B5D80A70DF9E1F9` |
| nuget-content-review.json | `A588FEE28BAAB83FA481C3AF9FACA88BD4BDA512631D6273B6FDBDD52C646918` |
| evidence-review-r2.json | `DDB33A5F28DF1812120723C5F5AA268FE33A7C4F6B7F7F76560DA235E020B3E0` |
| pdf-body-scope.json | `5A6D034958D005D74EE2FCCD88E31D8108278E8E49B657918F124B1C58952F47` |

独立根共 60 文件已冻结，不回填未来索引或审核文档。OS 文件/目录对话框输入、系统拖放、跨屏 DPI 未通过本轮实测；旧间歇启动/响应超时亦不能由本轮成功宣布根因已修。未新跑完整安装生命周期/性能矩阵，不继承为本包通过。上述限制保留，普通功能分支供复审与发布批准分别处理。

## 交付索引与候选

最终 `channels-delivery-20261104-a329045/delivery-index.json` SHA256 **`C22687D00B9C8C32601520811F1509E24DEB4DEEFD638ECFD6CBA87C8B8A7F71`**，绑定 a329045，17 个根、191 个证据文件、520 个源文件，无排除项。711 条文件大小/SHA 全部匹配，无重复、缺失或额外运行根文件；索引自身在枚举完成后生成，按设计不自索引，由上述外部 SHA 绑定。

191 个公开证据和索引均已暂存。独立读取这 192 项实际 Git blob，与磁盘原始字节逐一相同；未以 CRLF 归一后的 hash 替代 sealed 运行记录字节。核验时 196 个暂存文件全部属于本轮 docs/证据，无额外证据根，无 EXE/DLL/PYD/PYC/ONNX、字体、wheel/压缩包或 .local 载荷。143 个文本文件高置信凭据样式扫描无命中，PNG/PDF 不按文本扫描；不能由此声称检测了所有可能的秘密形态。source/desktop/launcher/build/global.json 对 a329045 无产品差异。

独立索引核验的首份 `CHANNELS-FINAL-DELIVERY-REVIEW-2026-11-04.json` 把预期自排除的索引自身当额外文件而 false；其全部文件大小/SHA 与 Git blob 原始观察已经一致。原件保留，更正分类在 `CHANNELS-FINAL-DELIVERY-REVIEW-R2-2026-11-04.json`，SHA256 **`0FAADE8D0B50C06996964B093CC08F0C2D1DFF4D00E904F12F56416F7BA8C5C6`**，passed=true。它不重写封存索引或伪称重新测试，只修正索引自排除的解释。

本文件与两份索引复核 JSON 位于 reviews，属于索引之后的独立复核材料，可随后暂存提交，不回填已核索引。后续文档/证据提交的 HEAD 会不同于产品构建 a329045，安装包身份仍以 a329045 和本报告所核字节为准。普通功能分支提交推送可继续，保留全部已列失败和人工/质量/稳定性限制。
