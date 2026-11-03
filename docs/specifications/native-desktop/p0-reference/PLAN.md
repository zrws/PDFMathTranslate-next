# R2 整包整改实施计划（r2-integrated-20261003-01）

> 依据：用户本轮授权 + docs/reviews/native-desktop/P0-CODEX-r2-review-2026-10-03.md（R1–R5）。
> 基线：分支 codex/native-desktop-2026-09-28，HEAD b504906769f15a3b048e2336755a2d563b0cb1ae，零 tracked 修改。
> 上轮证据根 systematic-acceptance-20260930-01 保持历史，不复用、不改写。
> 本轮证据根为本文件所在目录（唯一当前入口）。

## 三个工作包与文件所有权（主代理为唯一写入方，同文件单人写）

| 包 | 文件 | R 项 |
|---|---|---|
| A | p0_guard\sitecustomize.py、p0_guard\guard_fallback.py（严格 IPv4）、p0_asset_check.ps1（隔离+失败路径）、p0_guard\png_check.ps1（子进程隔离+finally）、p0_baseline.ps1（样本生成子进程）、p0_pytest_isolated.ps1、source/tests/conftest.py（PDF2ZH_CONFIG_FILE）、p0_manifest.ps1 | R1/R2 |
| B | p0_negative_tests.ps1（泛型裁决+拒绝覆盖+自测）、p0_run_recorder.ps1（新,外层 recorder）、p0_probe_perprocess.ps1（outer 接入+窗口时间）、p0_probe_attribution.ps1（回收持久化+覆盖率修订）、p0_recovery_negtest.ps1（新,回收桩）、p0_guard_mutations.ps1、p0_evidence_check.ps1（v5 收口） | R3/R4 |
| C | p0_seal_round.ps1（v2 诚实原件状态+COVERAGE+INPUT_MANIFEST）、文档 STATUS/HANDOFF/REQUIREMENTS | R5 |

## 执行顺序（本轮实际，非倡议）

1. CHANGE_IMPACT.json（本根）。
2. A/B/C 代码实现 + 纯本地验证（谓词回归、隔离哨兵、判定器自测、回收桩、校验器新旧变异全套）。
3. 独立安全审 A（网络路径、隔离、判定语义）。
4. 安全门后按 CHANGE_IMPACT 复跑受影响入口（外层 recorder 全套）。
5. pytest 受 guard/env/helper 变更影响 → 隔离复跑一次。
6. 24 mandatory + N01–N04 逐案映射：新跑 / 复用（注明依据）。
7. 封存 + INPUT_MANIFEST digest + 校验器自测 + 最终校验（输出进独立报告目录）。
8. 独立终复审 → 修复 → 复审 → 交付。

## 红线（继承）

不 commit/push/tag/Release；不改产品业务代码/start-webui.py/launcher/webui/site-packages/安装缓存/用户数据；
不真实翻译/下载/公网/外部 DNS；不改系统或用户环境；仅本次回环桩+独立安全门后真实后端回环；
不删除旧原件/旧失败 run；不伪造完成；不做无条件重跑全部历史测量（以 CHANGE_IMPACT 的受影响映射为准）。

