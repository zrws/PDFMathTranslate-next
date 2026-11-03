# 本机执行计划（2026-11-03）

基线：ab5d684df52aa1ec760eb25bc777932003b984b7；工作区初始为空，独立克隆，无本地修改需要转移。分支 codex/native-desktop-implementation-2026-11-03。Git 每次通过 -c http.proxy 配置 127.0.0.1:7897（用户纠正，优先于旧文档 11178）；不改变全局或持久仓库配置。

## 安全门与用例

- 冻结用例语义：完整保留 docs/specifications/native-desktop/p0-reference/CASE_MANIFEST.json 的 24+4 项；不删除、不降低期望。历史 CHANGE_IMPACT 和 PLAN 只作规格。旧运行工件不可用，旧 B1 缺三行/四日志的成因无法在本机判定，不能猜测。
- 本轮证据由调用方传入 EvidenceRoot，默认每个独立入口创建唯一 local-时间-GUID 根；总驱动向所有后代传递同一根，绝不默认写旧轮。新证据根位于 docs/verification/native-desktop/，不提交缓存。
- 顺序：路径/前置依赖适配；B2/M4 当前代码已有部分修复，增加本机回归；M1 统一 recorder 布局发现、强制匹配；M2 按真实矩阵结构选择并排除自测；M3 统一传播根；M5 本地合成 metadata 与真实 hash 子进程失败负例；B1 使用本机 Python 标准库桩，完整 8 条及 4 日志。
- 新增回归不得替代冻结用例：路径干跑、recorder 含空格/中文参数、旧输出拒绝、矩阵选择污染、缺 recorder 语义匹配失败、hash 子进程失败、恢复分类及清理。每个驱动记录脚本哈希、实际命令/外层退出/进程身份及隔离位置。checker 变异必须包含原因错配、缺证据、漂移、复用；缺真实后端时最终 checker 必须非零。
- 静态复核 R1–R5：严格数字地址、双层 guard、子进程 HOME/CWD/config 隔离、reason/退出码分离、checker 错误计数。禁止真实外网/DNS/翻译/下载、用户缓存访问、系统修改。测试无需下载依赖。保留所有失败运行。
- 独立代理先审计划及冻结语义，再审实现和本机证据，修复阻断后复审。审核者不参与实现。

## 环境与后续阶段

本机 dotnet --info：仅运行时 6/8，无任何 SDK；默认 Python 3.9.18；无 Inno Setup 命令；无交接安装树、依赖、模型或历史证据。不静默安装全局 SDK/改 PATH/注册表。纯本地桩使用现有 Python；真实 backend/pytest/模型检查缺依赖必须明确 unverified。

只有 P0 机器证据完备、checker 实际 exit 0 且独立审通过后才实施 P1。若依赖阻塞：完成独立可做的静态修复、桩回归与 UI 现状设计，并登记 .NET 10 可选仓库外本地安装方案，不越过安全门编写产品迁移或宣告完成。

后续 P1 完整范围仍按 REMOTE-WPF-MODERNIZATION-WORK-ORDER-2026-11-03.md：WPF/.NET10/WPF UI/MVVM、共享任务/SSE、语言/目录版本/预览/资源、性能与体积实测、中文安装卸载/本地更新验证、Debug/Release/实机截图、独立终审。缺任一项如实未完成。提交推送仅功能分支，无 main/tag/Release。
