# PDF 子进程与安装清理定点独立审核（2026-11-03）

审核者未参与实现。本轮只读源码、锁文件、已有工件，计算 SHA256，并用 `python -I -S -B` 对文本执行纯 AST 比较；没有导入被审模块、启动应用/测试、执行 PDF 操作、编译或安装/卸载、下载或访问真实用户目录。仅新增本报告。

## 结论

**0003 的边界迁移与保留 BabelDOC 原算法的要求一致，可以进入新的真实产物及性能验证。安装器当前清理检查有明显改善，但尚不能批准安装/升级/卸载交付，更不授予整个 P1 通过。**

代码仍未冻结；以下是约北京时间 22:04–22:11 的定点读取，不将其冒充最终提交或运行绑定。`p1-api-9d3db488ff/result.json` 已核为 passed=true、30 项 true、control_actual_exit=0；该运行早于新 0003 的验证，不能代替新补丁运行或 WPF 流程。

## 0003：操作等价性与兼容边界

已直接读取本机锁定原包 `pdf_creater.py`，其 SHA256 为 `67572926C787A2AF47D51C639EFB965245B08F1B6000BEC5262BAB1B04B4BFB5`，与 patch-lock 的 original 一致。native-runtime 补丁后文件 SHA256 为 `39E4777FEB718E5BF790F9D9CB025DC580E84BB405A37EF8AE5274CC1D996F02`，与 patched 一致。

纯 AST 比较只规范化函数名并移除函数 docstring，结果如下：

| 原 BabelDOC 0.6.2 函数 | 新 pdf_operations 函数 | AST 结果 |
| --- | --- | --- |
| _subset_fonts_process | subset_fonts_process | 完全相同 |
| _save_pdf_clean_process | save_pdf_clean_process | 完全相同 |

这包括参数顺序、默认值、`pymupdf.open/subset_fonts/save` 操作、全部 save 参数、异常分支、错误消息及 `os._exit(0/1)`。新模块仅导入 logging、os、pymupdf；`pdf2zh_next.desktop.__init__` 不导入重型翻译组件。logger 所属模块名改变，不影响 PDF 操作。

补丁只在 `PDF2ZH_NATIVE_POLICY` 非空时，将原两目标变量绑定到新模块中对应函数；原 BabelDOC 的 Process 构造参数、父进程等待/超时/终止、结果检查及 fallback 代码没有改动。未设置 native policy 时仍使用原目标。新函数的模块/名称可独立定位，符合 Windows spawn 通过可导入模块取目标的结构；避免目标函数本身要求重导整个 pdf_creater 的依赖图。

本轮没有据此宣称启动时间、CPU、峰值内存或排版质量改善已经实测。最终需要新补丁下的真实 mono/dual 产物、可读/渲染验证、内容身份、进程退出/清理，以及与同机基线口径一致的性能结果。不得只以旧 30 项成功或导入图推断运行 PASS。

## 安装器清理规则的已核内容

`[Files]` 使用 uninsneveruninstall，将程序负载删除交给 ownership 清单；未见递归 InstallDelete/UninstallDelete。升级只处理旧清单列出、新清单已不再列出的文件，且要求当前文件 SHA256 等于原清单值；卸载也要求当前字节匹配。未知文件、修改后的程序文件不在这条自动删除路径中。删除目录仅尝试移除空父目录，没有递归删除用户目录。

审核中即时发现并反馈的两类问题已读到整改：

1. `GetFileAttributesW=$FFFFFFFF` 原先被放过，现已拒绝清理；现有路径链中任一已观察到的 reparse point 也拒绝。
2. 初版保护目录字符串比较可被 `.\home\...`、`home.\...`、`home \...` 及 8.3 别名绕过。现在按组件拒绝空/单点、首尾空白、尾点和 `~`，再对 home、outputs、pdf2zh_files、logs、config、cache、.cache、.config、downloads 做执行期硬拒绝。冒号、绝对/UNC 前缀、斜杠和 `..` 也拒绝。保守拒绝可能保留部分非标准名称文件，符合安全清理优先保留的方向。

这些是**静态清理检查**的结论，不能直接升级为完整安装器安全验收。

## 仍待关闭的安装边界与实测

- **覆盖安装的重解析点边界未证明。** 手写 SafeOwnedPath 目前仅用于旧文件清理及卸载；`[Files]` 的递归 ignoreversion 覆盖未见同等前置路径链检查。本轮不猜测 Inno 运行时是否另有保护。必须用纯 owned 夹具，把 `{app}\uv-tools` 或其他程序子树设为指向 owned 外部哨兵的 junction，记录升级是否拒绝且外部字节不变；如果运行时不拒绝，需在实际覆盖前补检查。
- **检查、hash、删除不是一个原子操作。** 当前路径属性检查后会另行打开文件取 hash，最后按路径 DeleteFile。它能拒绝检查时存在的 reparse point，不能据此声称防住并发路径替换。清单本身也不是带认证的所有权证明。正式文案/报告须保留这个边界，不把注释中的“Never traverse”解释成已完成内核级原子保护。
- **尚无本轮编译与试装事实。** 需实际验证中文/空格路径，UTF-8 清单里的中文相对文件名，首次安装、同目录升级、已拥有且未修改旧文件移除、被修改程序文件保留、用户数据/输出保留、损坏清单/保护目录/路径变体拒绝、junction 拒绝、应用运行或文件被占用时卸载行为，以及控制面板/Geek 可识别的卸载登记。
- 对无法取 hash/删除的文件，应有保留和可诊断结果；不能仅通过脚本阅读推断运行时异常后的卸载状态。`AppMutex` 已设置，但应用运行时卸载的实际行为仍须观测，不以配置项名称替代测试。

这些试装可以在唯一 TestAppId/TestGroup 与唯一 owned 安装目录中继续，保留注册项/进程/退出码、安装/卸载日志和哨兵前后哈希。不要触及真实旧安装、用户历史或缓存，也不要把夹具通过表述为生产升级已全面实测。

## 读取快照 SHA256

| 文件 | SHA256 |
| --- | --- |
| source/pdf2zh_next/desktop/pdf_operations.py | 80AE0F1840D2C24880898B794BC1ACFD1472313A8744CCF14F87EAFCA71FEADD |
| build/patches/babeldoc/0003-native-lightweight-pdf-spawn.patch | BA3F600CB0FD909C526B7C5A8535EDEA43B4E63C77BF56F24546450E82DB7D12 |
| build/patches/babeldoc/patch-lock.json | EAEB5447F70A1A24E627114DEBF21C6E24A779ECB0AD00203F24E7845F9DD77D |
| build/installer.iss（22:10 读取） | 8FD8C08A58EA04EB4E533DA794DC85A3B87D2B8C07D052696D57A7DB6C38F3AD |

后续若改变上述字节，需要重新绑定受影响验证。本报告不批准 main 合并、tag、Release 或正式更新源变更。
