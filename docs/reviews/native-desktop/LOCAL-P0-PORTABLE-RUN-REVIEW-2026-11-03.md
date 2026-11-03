# 小体积 P0 交付轮启动前定点复审（2026-11-03）

审核者：`independent_p0_review`，未参与实现。只读 0802622 的四项 P0 短修、冻结 clone 状态、运行窗口/relay 调用链及哈希；分别作 PS5.1/7 AST 解析。没有执行被审入口、后端、翻译、下载或修改证据。唯一写入为本报告。

## 裁决

**允许冻结提交 `080262216d6a405519097d30b90f09a1ffdb130a` 在独立 clone 中以全新根完整运行交付验收。** 本机既有 P0 安全门及 P1 许可继续有效；新交付轮尚未运行通过，不能继承旧轮 current hash 或宣称其成功。

独立 clone：`D:\student\翻译\p0-frozen-fa97b2e6f9`。本审核 HEAD 精确匹配、tracked/untracked 工作区均干净，不含主仓库未跟踪 WPF 产品工程。P1 与新 P0 使用不同代码树；共用的已锁定 InstallRoot/runtime/site-packages/assets 在交付轮期间保持只读，若 P1 要修改引擎包应另用独立运行环境，性能测量串行。

## 四项修改

1. **损坏 cache 外置**：corrupt-cache 也改为唯一 owned TEMP GUID 路径；在证据内保留 owner/PID/cache_root/source_cache 元数据。仍从本轮 staged cache 复制并注入同样的模型损坏，真实 asset_corrupt 断言未减弱，未新增排除协议或豁免 checker。旧轮约600MB原件不移动、不删除；新轮应仅保留日志、元数据、小样本。
2. **真实起点**：perprocess 在 New-RunResult 后显式设置 started_at=$startIso，取启动前保存值；不再把结果构建时间误写作运行起点。
3. **保留真实终点**：Write-RunResult 仅在 ended_at 未设置时填当前时间，保留 perprocess finally 完成回收后采集的 runWindowEnd。result_built_at 仍单列。其他未设置终点的调用者保持原默认行为。
4. **统一宿主**：PS7 调用者在写任何 raw run 前，用已审核 Start-P0PowerShell 启动真实 Windows PowerShell 5.1、转发全部参数并等待实际退出。子进程处理整轮，raw JSON 的 UTF8 BOM 与后续读取一致；PS7 仅在末尾向被排除的 reports 写 relay 观察，不更改摘要输入或旧记录，并传播真实 child ExitCode。直接 WinPS 调用不再 relay；硬编码本机 WinPS 可执行路径避免递归进入 PS7。

relay 创建入口仍拒绝已存在 EvidenceRoot，且不预先创建它；参数包含中文路径时使用共享 Windows quoting。Start-P0PowerShell 已保留进程 Handle，避免短进程 ExitCode 为 null。此修复针对已证实的混合宿主解码问题，没有更改 guard、回环约束、测试地址、真实翻译开关或安装发布范围。

## 语法与身份

当前33个PS脚本在 Windows PowerShell 5.1.26100.9711 和 PowerShell 7.6.5 AST 解析均 0 语法错误。

| 文件 | SHA256 |
|---|---|
| p0_acceptance.ps1 | D104DAC63F5B82B039A803D850F065E2BFF3D9EDEDC6069B8D0F678BBB7C0E9A |
| p0_isolation_negtest.ps1 | D4152C4B40B628D47031ECEA8A81006D0868E114D49759ACED6A6113017FEC74 |
| p0_probe_perprocess.ps1 | B52264BBC57294BD50C768A1BC2BB9D2E2949F5E9AA963E872781503F18EA242 |
| p0_result.ps1 | CE4BB7FF2D5813FD8E8F98FF029FD30E1764BFAEB3B664668E48DD513673C87C |

本审只解除此次定点修改的启动前审核条件；真实 relay 全程退出、修正后的窗口时间、夹具未混入可提交证据、新轮完整覆盖/两遍 checker/哈希仍须由执行结果和后续独立终审确认。原 CSV 逗号及计数口径等已披露事项不在此次四项修改范围，不能默认为已修复。
