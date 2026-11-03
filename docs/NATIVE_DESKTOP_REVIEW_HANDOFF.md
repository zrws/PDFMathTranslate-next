# 原生桌面迁移主交接报告（审核入口）

> **当前状态快照（2026-11-03，优先于下方历史记录）**：P0 仍未放行 P1。最新 Codex 审核为 `docs/reviews/native-desktop/P0-CODEX-r2-review-2026-10-03.md`；随后独立安全门 `docs/reviews/native-desktop/P0-r2-integrated-safety-review-20261003-01.md` 的裁决为 **BLOCKED**，指出 B1、B2、M1–M5。先完成该报告 §4 的放行条件并取得独立复审，再开始 WPF 产品迁移。
>
> 本次 GitHub 交接不会提交 `docs/verification/native-desktop/**` 下本机生成的运行记录、字体/ONNX 缓存或其他大体积测试缓存；相关报告路径在另一台电脑上可能不存在。不要把历史报告里的通过数量当作该电脑已经复核的证据。

> 本报告交独立审核 AI 使用。按固定结构维护，随实现推进逐节填充。
> 实施规格：`docs/NATIVE_DESKTOP_OPTIMIZATION_PLAN_2026-09-28.md`
> 进度状态：`docs/NATIVE_DESKTOP_IMPLEMENTATION_STATUS.md`
> 报告只覆盖已实际发生的实现与验证；未发生的事项目标值不写入本报告。

## 1. 审核入口

- 项目路径：`D:\paper\PDFMathTranslate-next`
- 分支：`codex/native-desktop-2026-09-28`（自 main@`b504906769f15a3b048e2336755a2d563b0cb1ae` 创建）
- 迁移前基线提交：`b504906769f15a3b048e2336755a2d563b0cb1ae`（= 远程备份分支 `origin/codex/baseline-before-native-2026-09-28`）
- 本次实现对应的提交号或提交范围：**尚无提交**（HEAD=b504906；整改产物全部未跟踪，创建本地提交待用户授权）
- 尚未提交的修改：**用 `git status -u` 查看**（本机全局配置 `status.showUntrackedFiles=no` 会隐藏未跟踪文件，直接 `git status` 会误显"干净"）
- 报告覆盖到哪个实现提交：尚无
- 报告之后是否仍有改动：是（报告随实现持续更新，以"最后更新"为准）

## 2. 完成情况

### P0 系统性测试与证据整治（当前轮，2026-10-02 完成）

> **唯一当前验收证据根（P0 安全/证据体系）**：
> `docs/verification/native-desktop/systematic-acceptance-20260930-01/`
> ——S1–S6 全部关闭；24 冻结 mandatory + 4 新增（N01–N04）逐项映射（REQUIREMENTS.json）；机器派生覆盖矩阵 `runs/coverage-derive/matrix.csv`；全量负向矩阵 20/20（`runs/matrix-20261002-231058-111384/`）；guard 三模式 3/3；entry-gate 负向 5/5（含拒绝原因断言）；env 恢复 9/9；wrapper 变异 4/4 被拒；校验器 13 变异自测全拒；pytest 100 passed（net-guard 下零外联）；最终绑定校验 **360/360、0 失败、exit 0**（`EVIDENCE_CHECK.json` 由校验器自生成；实际退出与 stdout/stderr 独立记录于 `runs/checker-final-std/`）。
> 审核链：安全门 A 首轮 BLOCKED（`P0-systematic-acceptance-safety-review-20260930-01.md`）→ 修复 → 复审 PASS（`...-r2.md`）；实施记录 `P0-systematic-acceptance-implementation-20260930.md`；独立最终复审 `P0-systematic-acceptance-final-review-20260930.md`。
> 旧证据根（systematic-closure-20260929-01 等）整体为历史快照，不复用、不回填。

### P0 基线与契约

> **唯一当前基线入口（口径 A：当前仓库后端，正式测量）**：
> `docs/verification/native-desktop/run-v2-20260928-120431/` + `P0-baseline-report.md` v2 §4.1
> ——启动 apiReady 4.24/3.57/3.56s（n=3）、空闲 303.2s CPU 增量 0.45s（归一化 0.0074%）、private 末值 1488.5MB、预览 n=12 median 20ms/p95 35ms、manifest 齐备。
> **v2 测量条件边界**：该 run 在无 net-guard、无权威资产预检、无 PIL PNG 解码的 harness v2 下采集——后续轮次增加的安全验证层不追溯保护该测量。后续受控性能对比可用此数据但须注明此限制。
> **后续任何性能对比只允许与口径 A 同口径进行**；下方"历史"块与其余安装版数据整体作废为探索样本，禁止作为对比基线。
> 本轮（acceptance-20260930-01）的短 smoke/归因/perprocess 为**功能与隔离验证运行**（`runs/baseline/run-v3-20260930-223345` 等），不替代口径 A 性能基线。

- 已实现且已验证（当前状态）：
  - 方案 §1 现状逐条核实（P0-baseline-report.md §1，20 条，含 `__init__.py:27-30` 导入链与 WORK_DIR 漂移实证）
  - BabelDOC 0.6.2 补丁归档 + 双向核验 + 洁净下载哈希（patch-verify-20260928-114134.txt）
  - 测试隔离：`source/tests/conftest.py`；隔离 pytest **100 passed 且真实用户目录前后快照零变更**（run-v2-20260928-122042-pytest）
  - 测量 harness v3：失败统一累计+单一退出点、stdout 仅观测、root200 必需、PNG 严格校验、缓存逐文件完整性校验、子进程 socket 出站防护（F2/F3/F4）
  - 契约 v1.2（F1 导出内容身份/清理校验最终文件/5 验收案例；F5 唯一事件信封+四条生命周期+幂等 tombstone）
  - 证据封存：两个合成样本 PDF（哈希与终审一致）+ 7 份脱敏日志（含 F3 下载尝试证据，原始+脱敏双哈希）
- 已实现但未验证：
  - 契约中的 P1 功能（SSE/回执/幂等/ticket）——本轮仅规范，标为"规范审核通过"，产品功能未实现未运行
  - 真实翻译基线、完整桌面进程树（口径 C）、WPF 指标、GPU、长文档——延期清单见基线报告 §5
- 未实现：P1 及以后全部工作包
- 阻塞：无（.NET 10 SDK 未安装，P1 前需解决，见 STATUS 风险节）

#### 历史（安装版 v2.9.0 探索样本，2026-09-28 上午测量；禁止用作对比基线）

- 测量对象为安装版后端（与仓库 source 文件哈希不同）；启动 6.43/3.74/3.73s、空闲 0.005%、预览 mean 23.4ms/p95 57.6ms、翻译 1 单 40.98s（产物已清理、质量未验证）。原始数据：run-20260928-104200/；旧命令与口径细节见该轮 HANDOFF 历史记录，不在此重复。

### P1 原生端完整最小流程

- 未开始

### P2 资源治理

- 未开始

### P3 功能齐备与本地发布验证

- 未开始

## 3. 改动清单

P0 阶段（全部为新增文件，无源码行为修改；提交前以 `git status` 为准）：

| 文件/模块 | 目的 | 行为变化 | 兼容方式 | 风险 |
|---|---|---|---|---|
| docs/NATIVE_DESKTOP_IMPLEMENTATION_STATUS.md | 进度/上下文恢复入口 | 无 | — | — |
| docs/NATIVE_DESKTOP_REVIEW_HANDOFF.md | 本报告 | 无 | — | — |
| docs/DESKTOP_API_CONTRACT.md | P1+ 接口契约 | 无（规范文档） | — | — |
| docs/verification/native-desktop/* | 基线测量证据（脱敏） | 无 | — | 证据目录含运行日志，不含密钥/用户文档内容 |
| tests/performance/p0_baseline.ps1 | 基线测量 harness | 无 | PS 5.1 兼容（ASCII） | 运行会启动后端进程（隔离 PDF2ZH_HOME） |
| tests/performance/p0_probe_perprocess.ps1 | 按进程内存分解探针 | 无 | 同上 | 同上 |
| build/patches/babeldoc/0001-assets-upstream-env.patch | 把安装环境的 BabelDOC 手改固化为可复现补丁 | 无（归档） | 受控构建时应用并校验哈希 | 若上游更换版本需重新核对 |

## 4. 需求验收表

（随实现提交填充；特别覆盖：进度同步、语言选择、保存目录、多版本输出、安装、卸载、更新隔离）

## 5. 构建与测试记录

### 5.1 现有测试套件（P0 测试条件核实）

- 日期：2026-09-28；工作目录：`D:\paper\PDFMathTranslate-next\source`
- 命令：`$env:PYTHONPATH='D:\paper\PDFMathTranslate-next\source;D:\paper\pdf2zh-install-test\uv-tools\pdf2zh-next\Lib\site-packages'; $env:PDF2ZH_HOME="$env:TEMP\pdf2zh-p0-testhome"; & D:\paper\pdf2zh-test-venv\Scripts\python.exe -m pytest tests -q --no-header`
- 工具版本：pytest 9.1.1（隔离 venv `D:\paper\pdf2zh-test-venv`，由产品 python 3.12.13 `--system-site-packages` 创建，未改动产品 site-packages）；Python 3.12.13
- 退出码：0；关键输出：`100 passed, 74 warnings in 18.44s`（警告为 gui.py:856 Pydantic V2.11 deprecation）；`pdf2zh_next` 实际从仓库 source 导入（已验证 `__file__`）

### 5.2 BabelDOC 补丁核查（P0）

- 日期：2026-09-28；方法：dist-info/RECORD 逐文件 SHA256（352 个）+ 对比 PyPI 官方 wheel
- 结论：唯一失配文件 `babeldoc/assets/assets.py`（BABELDOC_ASSETS_UPSTREAM 支持）；官方 wheel SHA256 `FA7252AA2B4B57C833334A0AB3F3466A1DE8300953AAFF86B53CD5DF4B30DB1E`
- 证据：`build/patches/babeldoc/0001-assets-upstream-env.patch`

### 5.3 基线测量（P0）——【历史记录，已被收尾轮取代；当前基线以 §2 顶部口径 A 入口为准】

- 历史（安装版探索样本，2026-09-28 上午；harness v1；隔离与失败判定弱于 v3，数据仅探索参考）：Windows 11、20 逻辑核；隔离 PDF2ZH_HOME=%TEMP%\pdf2zh-p0-baseline（缓存 336.2 MiB 从安装 home 复制）；样本 PDF 为本地生成非用户文档；原始证据 run-20260928-104200/。
- 历史 h1 备注：harness v1 开发过程失败 3 次（PS 5.1 流事件冲突、缺 System.Net.Http 程序集、漏设 PYTHONPATH）；当时失败运行证据目录现**已删除**（收尾轮如实登记为缺失，不重造）。
- 当前（口径 A，正式）：见 §2 顶部唯一基线入口。**该基线在 harness v2 下采集**（无 net-guard/权威资产预检/PIL 解码——见 §2 顶部测量条件边界）；当前 harness 为 v4（含失败注入、net-guard、权威资产预检、PIL 解码），仅用于后续安全验证，不追溯改变 v2 测量条件。

## 6. 性能对比

- 未测对比：P0 仅采集**修改前基线**；任何修改后数据必须与 §5.3 同口径（进程树、归一化 CPU、隔离 home、相同样本与档位）采集后方可比较。
- 基线快照：`docs/verification/native-desktop/run-v2-20260928-120431/`（口径 A 正式，已封存）。

## 7. UI 与安装验证

- 未开始（P1 起）

## 8. 自动更新安全核对

- push / tag / Release：**未执行**（无授权）
- 生产 latest.json / 线上安装包：**未触碰**
- 更新源：未变化
- 开发预览与正式更新隔离：P1 设计时落实，尚未实施

## 9. 独立审核与整改

### 第一轮 P0 审核（GLM 子代理，2026-09-28 上午）

- 审核者：独立审核代理（未参与实现，general-purpose 子代理）
- 实际审核范围：本报告、STATUS、契约、基线报告、run-20260928-104200 全部证据、两个 harness 脚本、补丁归档；实核方案 §1 断言 19 条（含行号）；复跑 pytest（100 passed）；独立复验 BabelDOC 补丁（RECORD 全 352 条重算 + 代理下载官方 wheel 逐文件对比 350 个 + RECORD 差异归因）
- 审核报告：`docs/reviews/native-desktop/P0-review.md`
- 结论：**阻断 0 / 一般 2 / 建议 8，建议放行 P0**
- 其后 CODEX 独立审核（`P0-CODEX-review-2026-09-28.md`，R1–R6）认定 P0 需整改、暂不放行；**两份审核均保留不覆盖，以 CODEX 结论为准进入整改轮**。

### 整改轮（2026-09-28 下午，依据 P0-remediation-prompt-2026-09-28.md）

- WP1 测量入口安全：三个 harness 脚本 + `source/tests/conftest.py` 重写；独立安全审核 `P0-harness-safety-review.md`（阻断 0/一般 3/建议 7，"允许试运行"）；3 项一般问题（G1 归因探针失败路径不回收、G2 翻译 skip 恒致 exit 2、G3 探针遗留复查缺失）已修复后运行。
- WP2 离线证据：基线报告重写为 v2（`docs/verification/native-desktop/P0-baseline-report.md`）——测量对象三分口径（仓库后端基线/安装版探索样本/完整桌面基线延期）；口径 A 正式测量（run-v2-20260928-120431：apiReady 4.24/3.57/3.56s、空闲 303.2s CPU 增量 0.45s 归一化 0.0074%、private 末值 1488.5MB、预览 n=12 median 20ms p95 35ms）+ manifest（babeldoc 0.6.2/pymupdf 1.25.2/onnxruntime 1.27.0）；归因 v2（导入握手+全环境隔离：http_api 导入 1416.7MB，与 `__init__.py:27-30` 导入链吻合）；隔离 pytest **100 passed 且真实用户目录前后快照零变更**（run-v2-20260928-122042-pytest）；统计修正（58 样本、private 最大 1490.2=首值、线程 42–51、预览中位 20.3ms）；撤销 v1 三项错误结论（stdout≈API 等价、"5 分钟证明非泄漏"、"12 次=UI P95"）。
- WP3 契约 v1.1：R4 导出身份改为内容校验（允许另存为改名/冲突后缀、同 export_id 异载荷 409、暂存清理前置、外置盘离线=待验证）；R5 retry 幂等、SSE wire 格式/水位/重放/溢出/竞态测试清单、鉴权传递格式（Bearer/WebView2 头注入/一次性短时效 ticket）、目录所有权与单写者、环境变量边界、P1/P2 归属标注。
- WP4 补丁核验：反向应用=官方 wheel 文件哈希（208B394D…）、正向重放=安装文件哈希（3261EFFF…）、py_compile 通过、洁净下载 wheel 哈希核验通过（FA7252AA…，与 uv.lock 一致）；证据 `patch-verify-20260928-114134.txt`；全程临时副本，site-packages 未动。
- R1 整改落实：测量写入真实安装目录问题根除（v2 数据全落隔离根）；真实 home 污染查明并清理（config.fake.pdf 删除；cache WAL/SHM 触碰如实记录，用户缓存 db 本体未动）；全部运行带快照对照。
- 整改轮独立复审：见 `docs/reviews/native-desktop/P0-remediation-review.md`（复审代理写入）。
- 本轮约束：未 commit/push/tag（未获新授权）；未调用真实翻译；未修改产品源码与安装环境；conftest.py 属用户授权的"测试隔离辅助文件"。

## 10. 后续审核重点与回退

- 回退参考提交：`b504906769f15a3b048e2336755a2d563b0cb1ae`（迁移前基线）
- 回退注意事项：不得自动执行；用户数据目录与导出文件不在 Git 内，回退代码不影响用户数据
- 后续审核重点：随阶段填充
