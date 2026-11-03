# 跨电脑交接（2026-11-03）

仓库：`https://github.com/zrws/PDFMathTranslate-next.git`

交接分支：`codex/native-desktop-2026-09-28`

原产品基线：`b504906769f15a3b048e2336755a2d563b0cb1ae`。本次仅提交跨电脑所需的 P0 测试代码、BabelDOC 补丁、接口契约、最新审核/整改报告、历史测试规格参考及完整执行提示词；没有实现新的 WPF 产品功能，也没有宣告 P0 通过。

## 另一台电脑从这里开始

新目录克隆（按项目约定先尝试经本机 11178 端口访问 GitHub；代理不可用时先报告，不要悄悄绕过代理）：

```powershell
git -c http.proxy=http://127.0.0.1:11178 clone --branch codex/native-desktop-2026-09-28 --single-branch https://github.com/zrws/PDFMathTranslate-next.git
Set-Location PDFMathTranslate-next
git status --short --untracked-files=all
git rev-parse HEAD
```

已有克隆且有本地改动时先保存改动并确认范围，不能直接 pull/reset/覆盖。获取该远端分支后，从交接提交创建 `codex/native-desktop-implementation-<日期>` 工作分支。

**完整执行提示词**：`docs/reviews/native-desktop/REMOTE-WPF-MODERNIZATION-WORK-ORDER-2026-11-03.md`。将它交给执行 AI，并要求先完整阅读后实施。

## 状态与交付边界

- P0 尚处于 BLOCKED：最新安全门在 `docs/reviews/native-desktop/P0-r2-integrated-safety-review-20261003-01.md`，先修 B1/B2/M1–M5 并独立复审，再进入原生桌面实施。
- 历史用例/影响分析/计划参考位于 `docs/specifications/native-desktop/p0-reference/`，仅是规格，不是运行证据。
- `docs/verification/native-desktop/**` 的本机运行证据和隔离缓存没有纳入此交接。约 4.2 GiB 的未跟踪内容仍保留在原电脑，主要是重复测试缓存。不得声称在新电脑核验过这些证据；需按影响范围生成新的隔离证据。
- 原电脑的 Python 安装、字体、ONNX 模型和虚拟环境不随 Git 分发。脚本现有绝对路径必须适配新电脑，不得认为原电脑路径必然存在。
- 本次推送仅新增功能分支，不更改 `main`、基线备份分支、tag、GitHub Releases 或线上 `latest.json`；更新器当前从 GitHub Releases 取清单。本次没有调用发布脚本。
- 本轮独立复核已确认暂存区没有运行证据/缓存/大文件，常见高置信凭据模式无命中。测试脚本已有少量尾部空白警告保持原状，未为格式改写历史脚本，也未执行被审脚本/后端/真实翻译；这不是产品测试通过声明。

后续产品升级目标：WPF + .NET 10 LTS + WPF UI + CommunityToolkit.Mvvm，保留 Python/BabelDOC；同时完成进度同步、明确语言选择、默认保存目录/按 PDF 日期分组/版本不覆盖、资源占用与包体治理、中文安装路径选择、卸载登记及更新链隔离。
