# 最终 P0 总驱动重跑前独立复审 R2（2026-11-03）

审核者：`independent_p0_review`，未参与实现。范围：6c75df3 的归因回收持久化、c950bbc 的点用目录修复、当前四文件增量，以及 case8 原始失败/定向回归。只读 diff、Git、工件、哈希、AST；另执行真实 Git 的只读 ignore 探针，不启动被审 checker/后端/翻译或下载。唯一写入为本报告。

## 裁决

**允许冻结当前修复后，在全新独占根完整重跑 p0_acceptance.ps1。** 本审发现的 Git stdin 末项漏检已修复并得到针对性回归；本次范围未留新的执行阻断。P0 最终通过与 P1 放行仍须新轮完整结果及独立终审。旧失败根必须保留，不能拿单案重跑替代旧全轮失败。

当前代码基线为 c950bbc 加四个待提交文件的审核快照。CHANGE_IMPACT 的初始 HEAD 只能证明轮次创建时的代码；6c75df3 在旧轮归因运行之前追加，各条目的实际运行时哈希才是该入口身份，不能称旧轮全部入口同一 commit。

## 四文件修复

- `p0_paths.ps1`：Start-P0PowerShell 创建子进程时设置 PYTHONDONTWRITEBYTECODE=1，并在 finally 恢复原进程值；与 PSModulePath 相同的短窗口作用域，不改系统/用户环境。阻止通过子驱动启动的 Python 导入在证据树制造被忽略的 pyc；不删除已有失败轮 pyc。
- `p0_baseline.ps1`：run-v3 名加入实际 PID，已有目录即拒绝，避免同秒调用结果碰撞或向空旧目录继续写。c950bbc 在资源预检后、生成样本前，重新创建本轮拥有的 work/logs；没有改变输出语义或访问外部目录。
- `p0_evidence_check.ps1`：JSON 整数同时接受 Int32/Int64，guard_blocked_count 仍要求非负，未放宽到字符串/浮点。Git 校验保留真忽略拒绝、区分 ! 否定规则，并修复下述独立发现的传输问题。
- `p0_seal_round.ps1`：G01/G11 从实际 acceptance matrix 的 frozenId 行映射，要求实际退出与冻结值一致、verdict PASS、frozenExpectedReason 匹配；来源指向该真实矩阵工件，不从预期值凭空补成功。

## 本审新增发现与关闭

初版 Git helper 用 PowerShell 管道传 `--stdin`，末项附 CRLF。独立只读探针证实 Git 可把末尾 CR 当路径字符并 quote 输出，从而使 ignored map 的键不等于原路径，最后一个真实忽略项漏检；不能仅修 ! 规则正则后就宣称 checker 可信。

当前 helper 已改 ProcessStartInfo、显式 RepoRoot CWD、UTF8 无 BOM 字节流与 NUL 输入，使用 `--verbose --non-matching -z --no-index`，双流异步排水并读取实际退出；输出严格按四元组解析，数量必须等于输入，异常输出/子进程失败置败。`--no-index` 让已提交工件同样受 ignore 规则核验。

独立真实 Git 探针（不执行被审 helper）：中文路径 raw.log 返回 ! 例外→不算忽略；末项中文 `__pycache__/last.pyc` 返回原样路径→确认为忽略，无 CR/quote 键错位。

当前 `.local/p0-temp/checker-preflight-r3.json`：clean_pass=true、git_log_exception_clean_pass=true，**26/26** 变异均非零拒绝且 reason 匹配；新增 genuinely-ignored-evidence 为 exit 1、reason=gitignored_evidence。执行方报告该自测实际 exit 0；本审独立核 checker 自身及五个 dependency hash **6/6 与当前一致**，并核 stdout 记录。此前复现为 exit 0 的漏检失败报告不被继承为通过。

## case8 与归因回收

旧全轮 `p0-final-20261103-1825693180a9` matrix 为 **22/23 PASS**；case8 expected=0、actual=1。原 stderr 清楚记录资源 182 项校验通过后，Set-Content 写本轮 logs/gen_pdfs.py 因父路径缺失失败；sentinelUnchanged=True。目录缺失的外部成因不可由这些工件推断。

c950bbc 点用创建目录后，`p0-case8-rerun-b48553ccb8/runs/recorder-case8/entry-run/cases/matrix.csv` 为该单案 **1/1 PASS、actual=0**。它支持局部修复，不改写旧全轮失败。

6c75df3 回收事实持久化正确：健康归因工件包含四 payload、四个 recovery-<label>.json、聚合四 batch，共 12 行身份；每 batch 三行，逐批原件 rows 与聚合对应 rows 独立比较完全一致，all_gone=true。attribution 脚本 SHA256 `17E83833AA050B16635C091C2A1F8A5D31AB0B381FB98B92D8F6ADEC78F69F1D` 当前匹配。

import-fail 模式按源码只运行三个 import payload，不运行 bare_sleep；该失败工件为三 batch、0 身份行，表示捕获时进程已退出的有限记录。不能将它描述为四 payload 或已记录 12 个身份的完整回收证明。

## 冻结快照

| 文件 | SHA256 |
|---|---|
| p0_baseline.ps1 | 63C305568D301B10D36242EAC2374615F09782C621D034AB9D6B2F23E6CDADDD |
| p0_evidence_check.ps1 | 762AFE5CD518D19147B1EE40BBF804A47FFC4AEFEF6E1C535AEA0FA77EEB13C1 |
| p0_paths.ps1 | 3115C8D9C99129AD514842B8E545D47999B9280F8D561F8C5FACF20CC128B269 |
| p0_seal_round.ps1 | 16A91F818AC6E26555A34A12FCFD512688E408E3A3B4A50E4C103096B08AF309 |

32 个 PS 脚本在 5.1.26100.9711 与 7.6.5 AST 均 0 语法错误。新轮须记录上述版本，完整重跑受影响用例、自测及真实两遍 checker；本报告没有宣告这些新轮结果已产生。
