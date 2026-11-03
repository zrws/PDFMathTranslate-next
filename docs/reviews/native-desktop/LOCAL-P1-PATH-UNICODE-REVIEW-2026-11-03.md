# 路径与中文 ownership 清理独立复审（2026-11-03）

本轮只读源码、既有构建/运行日志与 owned 测试注册项，计算哈希；没有执行安装器、应用、测试、编译或修改产品。仅新增本报告。产品修复提交为 `fe16ed8905955254a9f41dfe3c524c68c4b8994a`，读取期间 HEAD 后续为仅测试改动的 7ffcc41。

## 裁决

**本次路径/Unicode 修复未发现尚存产品代码阻断，可以继续新的洁净全量构建及完整安装生命周期验证。** 最新最小安装器两种 BOM 的实际结果均已核实；不能据此宣布完整安装升级、Debug/Release 或整个 P1 全部通过。

## 实现核对

- `RuntimePaths.OptionalEnvironment` 将 null/空/纯空白覆盖值视为未设置，显式 Unicode/空格路径原样保留。BackendSupervisor 的 app/runtime/home/source 覆盖均采用该辅助函数；因此空串不会再替代 packaged 默认路径，也不会制造空 PYTHONPATH 前缀。更新版本定位调用也相同。
- csproj 同时指定 `AppHostDotNetSearch=AppRelative` 与 `AppHostRelativeDotNet=dotnet`，用于私有 .NET 运行时定位。这一配置需要实际部署有相对 dotnet 目录；不能以 Console 模型测试替代 WPF host 启动。
- 本次 Debug 实际部署位于 `.local/native-app`，其 dotnet 为普通目录、不是链接。新 `p1-ui-final-48bbb6af48/ui-result.json` 记录 PID 9224、真实窗口可见、api_ready、passed=true；少见语言、auto_update 关闭读回、缺安装器后真实健康检查均 true。它关闭了本次实际 Debug 部署的运行时定位顾虑，不说明标准 bin 目录可脱离运行时直接分发。
- `UnicodePos` 使用 String 的 Length/Copy 扫描，返回与后续 Copy/Delete 一致的字符索引；所有 ownership 分隔符和路径 token 搜索均已改用它。它不是仅改变文件 BOM。
- 路径防护没有因允许中文而放宽：仍拒绝绝对/UNC、冒号、斜杠、`..`、空/单点组件、尾点/首尾空白、8.3 别名以及保护根；仍遍历祖先链拒绝 reparse/类型不符；AllowMissing 仅限预检中的 Win32 2/3。安装预检、升级旧清单清理、卸载均使用同一 Unicode 解析。attrs/hash/Delete 的既有非原子边界没有被本次改动消除。

## 新最小实测及判定修正

初始读取根为 `p1-installer-encoding-d8103427d7`，随后已核新的严格判定根 **`p1-installer-encoding-1553f96d39`**：

| 清单 | install exit | uninstall exit | 中文/ASCII owned 文件残留 | 注册项 |
| --- | --- | --- | --- | --- |
| UTF-8 无 BOM | 0 | 0 | 无 | 安装后实际存在且 InstallLocation 正确，卸载后删除 |
| UTF-8 有 BOM | 0 | 0 | 无 | 安装后实际存在且 InstallLocation 正确，卸载后删除 |

最新脚本采用短 12 位唯一测试 ID，安装后先读取实际注册项并核 InstallLocation，再验证同一键消失；两种 BOM 任一失败均 throw。日志实际创建的键与结果中的 registry_key 完全一致。

本轮发现旧入口只对 BOM 分支失败报错、且长 ID 检查错了 Inno 截断带 hash 的真实注册键；这些测试判定问题现已修正。旧 d810 两个真实带 hash 的测试键也已仅按日志中的精确 owned 名称只读核为不存在，未改任何注册项。

更早 `e841c4c701`、`4baee172b0` 两轮结果保留：两种 BOM 当时都残留中文程序文件。新的两种格式都能清理，与 Unicode 字符索引修复相符；不能把结果解释为仅添加 BOM 就解决了路径解析。

## 其他已核证据与剩余范围

`.local/p0-temp/dotnet-tests-r6.txt` 记录 passed=true、27 项模型/协议/更新测试，含空覆盖与显式 Unicode 路径。它不覆盖 WPF apphost 或完整安装；本轮 WPF 启动另有前述真实 UI 记录。

Debug r16 发布日志有两条 CS8601（同一测试辅助代码在临时项目/主项目各一次），不要将该次表述为零警告。本轮未见因此造成产品失败，完整 Release 结果待新批次核。

完整新包的首次安装、升级、修改/未知文件保留、junction/锁定文件/运行中卸载负向、快捷方式和标准卸载发现仍待全生命周期工件；最小两文件夹具不能替代。UI 记录明确为真实 WPF 进程内渲染，不是 OS 输入自动化；原 worker 120 秒失败的独立诊断结论也不由本次通过改变。

## 文件身份（SHA256）

| 文件 | SHA256 |
| --- | --- |
| build/installer.iss | 831476573C19B728DDA9F2FD25314543C0C217A339E6B7963C38287FF4B02AE4 |
| desktop/PDFMathTranslate.Desktop/Models.cs | C598B727E9175247057D06E9381F269236379751FF6D3FC0C99AF9C4604D830C |
| desktop/PDFMathTranslate.Desktop/BackendSupervisor.cs | 89F0E40E0DA37CA953E4B8618334D770CBF1EF7394A6BD8A0F9F54649E6CE053 |
| desktop/PDFMathTranslate.Desktop/PDFMathTranslate.Desktop.csproj | 983739589F3B9CEC85F904D5200A2EFBEEDC910168A2693EE20A2DDF7E9C5F22 |
| tests/native/installer-encoding.ps1（修正后） | AC1DEBE2D02E796AAE27C66B48148889F2D3ECBFB20E49765BB29C6510783D01 |
| p1-installer-encoding-1553f96d39/result.json | C38ACB034BAC656ABD262C2A8B6340C55615E9BF90ABD05361718020349ED410 |

最终整体复审及是否允许推送供复审，待新增完整工件另行裁决；不批准 main、tag 或 Release。
