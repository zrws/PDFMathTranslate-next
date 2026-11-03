# 更新恢复与洁净源码打包独立复审（2026-11-03）

本轮仅只读源码、Git 差异和 owned 构建记录，并核文件集合/SHA256。未执行被审入口、编译、安装、翻译、下载、代理连接或真实用户目录访问；仅新增本报告。读取到的当前 HEAD 为 `366432ce8ae69348b3df44b401b20ca3fbf23aa2`，更新恢复产品修复为 `27b57786a17cb719e18b818977fe90539e7ab5cb`。

## 裁决

**U01、U02、U03 的代码阻断已关闭；当前新的洁净构建/源码复制路径未发现仍需阻止受控验证的代码问题。** 允许继续 r9 最终包、更新恢复和安装负向验证。本报告不授予整个 P1 通过，也不把尚未完成的 r9 或新测试定义当作实际 PASS。

## 更新恢复的核对

- **U01 跨 home 与旧 marker：** `migrate_ui_prefs` 采用独立 `migration-ui-prefs-v1.json`，在 TOML 的 migration-v1 早退前执行；从明确旧安装位置复制 ui-prefs，先备份并比较内容身份，再原子切换；已有当前文件不覆盖，Store 中已有 native 偏好优先。新增跨 home 测试预先建立旧 TOML marker，再验证旧 false 被保留及当前新选择不被回退。原“已有 marker 会跳过新偏好”的缺口已修。
- **U02 安装器启动失败：** `LaunchInstaller` 在执行前重新验证期望 SHA256 和实际文件；ViewModel 先尝试验证/启动，捕获失败并维持当前服务，成功启动后才 Dispose/Shutdown。纯测试的错 hash/缺文件不会执行假安装器；DEBUG UI 验收新增真实 api/health 检查，证明缺文件失败后控制面仍就绪。此处是已核到的实现/测试定义，新的实际运行结果仍待最终绑定。
- **U03 代理：** `CreateClient` 保留 .NET 默认环境/系统代理，不再因端口监听覆盖 ALL_PROXY/系统配置，且继续关闭自动重定向、由代码验证每跳 URL。没有为本轮测试读取或修改真实系统代理。

## 新构建与源码复制

当前构建采用 `build-native.ps1` 的唯一新目录、洁净 venv、Python hash lock、NuGet locked restore 和锁定 BabelDOC 补丁，不采用已移除的 finalize-native 入口。schema2 构建报告在生成时绑定 Python/NuGet/patch locks、ownership manifest、product-source 报告及安装器 SHA；不应追填旧报告以冒充旧构建时已验证。

`copy-product-source.py` 使用 `git ls-files -z` 的跟踪文件清单，只创建全新的目标包目录。它拒绝源/目标路径链中的 symlink/junction，源链检查现已覆盖到 repo；验证源文件没有逃出包根；逐文件核复制前/后源与目标 SHA，再核包内文件集合精确等于清单。未跟踪配置、缓存和已从 Git 清单删除的旧源码不会由普通递归复制带入。

本轮发现的 source 祖先漏查已在 366432c 补成检查到 repo。没有观察到真实凭据泄漏；先前复用载荷入口对未知额外文件的风险，不再是当前构建路径。

## r9 已有源码工件的独立核验

已只读核 `dist/native-a0da2c11463d/product-source.json`：

- 记录 source_commit 为 `c9ff52cea34598d253c70b323c5e4c05d0eb1a86`，exact_set=true。
- 54 条记录的包内与当前 repo 两侧 SHA256 全部匹配，零漂移。
- 独立枚举实际包目录为 54 个文件，集合与报告精确一致，无额外/缺失文件，无 reparse 条目；当前 repo/source 与包源根也是普通目录。
- 报告 SHA256：`1AFA9FBCF3DFD1A56400E9239F54D57B38025FA75955DDFD95617264CEED1050`。

366432c 只改变构建辅助工具的祖先校验，不改变已核 54 条产品源码字节。不能称已经产生的 c9ff52c 工件运行过后来的辅助工具字节；可用上述实际输入/输出核验说明本机这次路径不存在该链接条件。最终安装器、构建报告和运行 provenance 仍须各自按实际批次绑定，不因本报告省略最后的包级验证。

## 验收 provenance

新 acceptance 记录实际 argv、packaged 布尔/模式、解释器/sys.path、从实际导入包根定位的主要源码路径和 SHA256；packaged 模式移除 repo/source overlay，并检查期望包根；结果绑定 provenance 文件 SHA。这补足了此前仅凭 payload exe 路径判断导入来源的缺项。

该短 probe 是来源绑定，不代替后续控制进程和真实管线的成功/失败观察。最终还需核新包的实际 API+UI/更新恢复、安装升级负向矩阵、清理/哨兵结果；已有的历史 31 项、30 项或 125 pytest 不自动继承到新字节。OS 输入、对话框、跨屏 DPI 等未实测范围继续明确保留。

## 本轮读取快照 SHA256（23:06）

| 文件 | SHA256 |
| --- | --- |
| build/copy-product-source.py | F1295378DA981E56F3651CAC0178B9A41BA8E9C7673DE9AB4AABD4FA458AAC65 |
| build/build-native.ps1 | 41665E1978D2B4277FFD81E9E701DB70207ACA01AD6D66C8C27DF9B48F435743 |
| source/pdf2zh_next/desktop/runtime.py | F74C95738AA71701071075967E4770C39796CD4C903A157464E751B3A6B5CE2C |
| desktop/PDFMathTranslate.Desktop/UpdateService.cs | 33E64673D975390D93E02D23CD25ECD3704FC5AE60C8E14ECA76EA6051E86219 |
| desktop/PDFMathTranslate.Desktop/WorkbenchViewModel.cs | A1A79455E80012FDEB8E2C90D454A47156A504A103FBEADE8FB2612AC1E7F907 |
| tests/native/acceptance.py | 77177250B78EE6A855FB99104486F18934C916C84A860AC7BD14C382F3D8531F |

仍不批准 main 合并、tag、Release 或正式更新源变更。
