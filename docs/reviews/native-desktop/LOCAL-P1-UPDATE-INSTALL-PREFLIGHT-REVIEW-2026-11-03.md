# 更新、语言与安装预检独立复审（2026-11-03）

本轮为定点只读审核，未参与实现，未启动应用/测试、更新请求或安装器，未下载、修改全局环境或读取真实用户目录，仅读取仓库与 owned 证据并计算哈希。只新增本报告。

读取开始 HEAD 为 `d1180840a006afe7a4b87517ef570b6e8bb7f551`，随后变为测试提交 `c375a0209761301c63d9e80db1d8ff188fcc83a2`。核心实现来自 9018db1、UI 调整来自 043385b。本报告不继承旧轮通过，不授予整个 P1 通过。

## 尚存代码阻断

### U01 — 不同 home 之间迁移会遗漏旧自动更新 opt-out

`runtime.py:migrate_config` 仅从旧安装 `root/home/.config/pdf2zh` 迁移 config.v3.toml；`Store.__init__` 仅检查**新 home** 下的 ui-prefs.json。旧便携目录切换到新 LocalAppData home 时，旧 `auto_update=false` 没有被复制或读取，新 Store 将默认 true。已有 `test_old_auto_update_opt_out_is_preserved_and_native_preference_wins` 只覆盖同 home，不覆盖该实际迁移路径。

要求：独立迁移/读取旧明确位置的 ui-prefs，保留备份与来源，且不得覆盖新界面中用户已明确保存的偏好。不要依赖已完成的 migration-v1 marker 跳过新偏好迁移。用两个 owned home 的旧 false、无旧偏好、损坏偏好和新偏好优先场景验证，稳定频道关闭后不得调正式更新源。

### U02 — 安装包启动失败时已先关闭后台，异常不能恢复

`WorkbenchViewModel.InstallUpdate` 先 Dispose，再直接 LaunchInstaller 和 Shutdown，没有失败捕获。已下载文件被移动/隔离、无执行权限或系统拒绝启动时，Process.Start 异常越出 RelayCommand，而后台已经关闭；UI 的原就绪状态也没有可靠收敛。

要求：确认安装器成功启动后才结束当前会话，或在失败时恢复后台并保持准确状态；显示明确可恢复错误。用本地缺失/拒绝执行文件注入验证，不执行真实更新安装器或访问正式源。失败时当前应用仍应可继续使用。

### U03 — 7897 回退覆盖系统/ALL_PROXY，与声明优先级不符

`UpdateService.CreateClient` 只看 HTTP_PROXY、HTTPS_PROXY 是否为空；二者为空且 7897 监听时，直接覆盖 handler.Proxy。没有先保留 ALL_PROXY 或已配置系统代理。因此实现不是“环境/系统优先，7897 回退”。这台电脑用户指定 7897 的偏好本身没有问题，但通用产品不能据此声称尊重所有已有代理配置。

要求：明确并实现代理优先级，保留显式环境/系统代理，仅在没有有效已配置代理时探测 7897；使用可注入的本地假代理解析结果做定向测试，不读改真实系统代理或发真实 GitHub 请求。

## 已核到的正确行为

- `LanguageChoices.Resolve` 对已有代码忽略大小写复用；未知非空代码加入选项并保留原值，不能解析名称时显示代码，不再默默替换成中文；缺失值维持未选择。目标 auto 被清成未选择，目标列表排除 auto。`fa` 的纯客户端断言与新的 UI 验收定义对应这个风险。
- 更新偏好在同 home 内会迁移旧 false，已有 native 偏好优先；PUT 设置对 auto_update 做 bool 校验，进入同一 settings transaction。U01 是不同 home 的遗漏，不否定同 home 行为。
- 稳定频道后台检查先等 8 秒，再复核开关；preview 或 version.json 无法确认 stable 时，检查路径提前返回，不建立正式更新请求。自动检查不自动下载安装器。
- 更新器限制 HTTPS 的 GitHub/资产主机、逐跳检查跳转、清单 1 MiB 上限、下载 2 GiB 上限、size/SHA256 验证、关闭写句柄后再 hash；测试源仅允许 HTTP loopback。以上为静态发现，最终要与新本地 fake-feed 测试绑定。

## 安装预检的当前结论

`PrepareToInstall` 已检查新嵌入 ownership 清单的所有目标，以及 owned-files.tsv、unins000.exe/dat 元数据目标。SafeOwnedPath 遍历完整祖先链；新文件允许缺失仅限 Win32 2/3，未知错误拒绝，文件/目录形态不符及重解析点拒绝。路径组件拒绝、保护根硬拒绝、旧文件 hash 匹配清理继续保留。

这补上了前审“只有删除检查，覆盖安装未预检”的结构缺口。**ISCC 语法成功仍不等于实际安装/升级/卸载通过。** 需继续唯一 TestAppId/TestGroup/owned 安装根的完整试装，特别是已有程序子树 junction 指向 owned 外部哨兵、中文/空格路径、中文清单文件名、旧 hash 匹配/修改/未知文件、用户目录保留、运行中/锁定文件卸载、注册项和快捷方式。不得据当前静态检查宣称 attrs/hash/Delete 分离操作已具有原子抵抗并发路径替换的保证。

## 本轮独立抽查的新证据

| 证据 | 已核事实与口径 |
| --- | --- |
| p1-api-ui-fc01d7d9e0/result.json | 31/31 true，passed=true，control_actual_exit=0 |
| p1-ui-flow-4f51ca0917/ui-result.json | 真 WPF 窗口、task done、shared_task_reference=true、丢导出响应留待办/恢复不重复、saved_versions=4；UI PID 2736；完成 22:20:37；明确不是 OS 输入自动化 |
| p1-pytest-e52ee2f85c | pytest-child 实际 exit 0，125 passed、74 warnings，运行约 53.17 秒；22:17 启动 |
| p1-packaged-api-a0dd6a8c16 | 30/30 true、control_actual_exit=0；mono/dual 的实际字节数和 SHA256 均与 task-final 身份匹配；过程样本 357 条，末尾进程表为空 |
| p1-perf-8eadc0a4be | 3 次真实 Debug WPF 启动；第三次 293 行原始采样，monotonic 400976.515→401275.734，实际跨度 299.219 秒，actual_exit=0；全窗 UI 后代名称仅 python.exe/conhost.exe，control 后代仅 conhost.exe |

性能原始样本与 summary 的“请求约 300 秒、实际采样 299.219 秒”一致。它是已有离线资源、进程冷启动而 OS 缓存未清的 Debug UI/control 空闲场景；GPU 未测。不能把此结果当完整翻译峰值或所有硬件结论。裁剪包 API 的采样整树 private bytes 峰值约 3.12 GB，不能拿控制进程约 50 MB 的空闲值代替翻译峰值。

UI4f 的结果没有后来新增的 uncommon_language_readback/auto_update_opt_out_readback 字段，125 pytest 也早于本轮最后的更新改动；**不能用这些旧于改动的成功行关闭 U01–U03 或证明新增逻辑已经运行通过**。新 UI 和短回归结果仍需单独核对。

当前 acceptance 支持 `--packaged`（移除 repo/source overlay）。最终纯打包证明还应落盘该轮真实 argv、packaged 标记、模块 __file__ 与源码/补丁哈希；仅进程 exe 位于 payload 不能单独证明导入的是 payload 源码。本轮未据记录缺项推断实际没有使用该参数。

## 证据文件身份

- UI4f result SHA256：`F6455AC4F0FEF46D9EB07DCCE878034814248E6840D6448AA7FDA8FB0F4CABC4`。
- 裁剪包 API result SHA256：`E575F5FCFBC506EBE3538AF6ACB4647DCB2F28F0D0D8E328E715B9AA2B8F657C`。

## 22:43 源码读取快照 SHA256

| 文件 | SHA256 |
| --- | --- |
| desktop/PDFMathTranslate.Desktop/UpdateService.cs | C66F5EC5DA7926747632949B69FEB8B9BD5941D2BA70A34504828F608B765221 |
| desktop/PDFMathTranslate.Desktop/WorkbenchViewModel.cs | A964CE97AB759C9898A7B7CBFDED54F7CB726021A9657DE265F2AA12789DFBB4 |
| desktop/PDFMathTranslate.Desktop/Models.cs | 8C2F0887A4B91819B1D231889B9F2FACE090B859CA04CA250FACC323B8671630 |
| source/pdf2zh_next/desktop/storage.py | 687B8DA36996EB19942DAC8AEE3B008351B75FD54D0E9CECAB490133E1EABD97 |
| source/pdf2zh_next/desktop/runtime.py | C9389AA9EAD663521A1F60BAA1F91B90E1F82AE6E0ECE2F4EFB209A77899C4AA |
| source/pdf2zh_next/desktop/server.py | 67A13137F07FA2B6F3FADC7ED2752B9CECDD8CC358BFB71CC144034A253B0D66 |
| build/installer.iss | AA2218A9B4B871A0C306BA1F1E291F0B785DCC8341D5AC223F0FFA41A9C8C2BB |
| build/apply-engine-patches.py | 705B72A30FF5372F30604CC85999E6040CC6FC989855121EA9692C62C59C07DA |
| build/patches/babeldoc/patch-lock.json | 069FF7E8D8972E5EB029AE8397845475251C9565A7040DBBF6B5CDE2E5A5055A |
| tests/native/acceptance.py | 1F4C5AB80527C08F4147E746056B47AA1A4ABC03F08CA546C8D9A2252EF892F7 |

新的 0003 patched 锁为 LF canonical SHA256 `E478B59421097D58E8D14C95261ECC3FB5774D050668682DF3F5262C3CD1F043`。apply 脚本仅在 CRLF→LF canonical hash 已属于锁定 original/patched 时规范化，未知字节拒绝，git apply 显式关闭 autocrlf；本轮未重跑该入口，不以旧 CRLF hash 充当新字节。

下一次复核需关闭 U01–U03 并绑定新短回归，核实际安装负向矩阵和最终洁净包入口；所有历史失败保留，手工 UI/DPI 未验证范围继续明示。不合并 main，不发布 tag/Release，不变更正式更新源。
