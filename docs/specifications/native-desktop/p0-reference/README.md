# P0 历史测试规格参考（不是验收证据）

这些文件从原电脑历史证据根提取，仅提供冻结用例、影响分析和计划供跨电脑交接。它们没有与 GitHub 分支附带的运行证据，不代表 P0 已通过，也不能用于填充历史缺失结果。

| 文件 | 原始来源 |
|---|---|
| `CASE_MANIFEST.json` | `docs/verification/native-desktop/systematic-acceptance-20260930-01/CASE_MANIFEST.json` |
| `CHANGE_IMPACT.json` | `docs/verification/native-desktop/r2-integrated-20261003-01/CHANGE_IMPACT.json` |
| `PLAN.md` | `docs/verification/native-desktop/r2-integrated-20261003-01/PLAN.md` |

新电脑先基于这些规格建立独立的新轮计划和 CASE_MANIFEST，保留原始冻结用例语义、标明当前电脑路径/工具/约束与证据不可用项，经独立审核后再运行。受影响项必须生成新证据；无当前证据的项目不得继承“通过”。不要直接对本参考目录运行 seal/checker，也不要改写这些参考文件来匹配结果。

提取日期：2026-11-03。最新裁决见 `docs/reviews/native-desktop/P0-r2-integrated-safety-review-20261003-01.md`。
