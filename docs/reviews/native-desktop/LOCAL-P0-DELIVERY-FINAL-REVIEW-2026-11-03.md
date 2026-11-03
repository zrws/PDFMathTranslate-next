# P0 可交付证据轮独立终审（2026-11-03）

审核者：`independent_p0_review`，未参与实现。只读冻结源码、原根全部输入/原始工件、哈希和 Git；未重跑被审入口、checker、后端、pytest、翻译或下载。唯一写入为本报告。

## 裁决

**冻结提交 0802622 的完整 P0 交付轮通过独立终审，允许提交该轮小体积证据；既有 P1 实施许可继续有效。** 本轮是真实自动总驱动全程退出 0，不是对旧轮混合宿主失败的重新表述。

本结论只覆盖 P0。WPF 产品、交互、DPI/对话框、安装卸载、更新、资源优化与真实翻译质量，仍须后续 P1 独立验收。

## 实际执行身份

- 冻结源码 clone：`D:\student\翻译\p0-frozen-fa97b2e6f9`，HEAD 独立核为 `080262216d6a405519097d30b90f09a1ffdb130a`。
- 实际证据根：`D:\student\翻译\p0-frozen-fa97b2e6f9\docs\verification\native-desktop\p0-delivery-20261103-c72fd7361c`。
- PS7 调用者通过 relay 启动真实 WinPS5.1 整轮；`reports/host-relay.observed.json`：child_pid=11240、开始 `20:22:23.693 +08:00`、actual_exit=0。
- `.local/p0-temp/delivery.observed.json` 外层记录 actual_exit=0，完成 `20:37:05.369 +08:00`，source_commit=0802622。
- 最终 checker 子进程 PID=15512，开始 `20:36:53.388 +08:00`，actual_exit=0、timeout=false、owned process exited。

旧本机大夹具轮的原自动总驱动失败、PS7补充封存，以及本轮自动整轮成功，是三个不同的历史事实；原件全部保留，不能相互覆盖或改写身份。

## 独立核验结果

| 项目 | 结果 |
|---|---|
| 冻结用例 | CASE_MANIFEST 24+4 项全字段/顺序与参考一致，28个唯一覆盖逐案 PASS、实际退出与冻结期望相同 |
| 输入完整性 | 1048 个 INPUT_MANIFEST 输入逐文件 SHA256/大小独立重算，0 缺失/越根/失配 |
| 输入 digest | `3BCD79E48A6FBDEAEDF90590D539E940A07D477C532CBF9327090E1FADEB7374`，独立复算一致 |
| 运行版本 | root/run script-hashes 共202项独立重算，0漂移；以冻结 clone 验证，未对主仓库P1源码误绑定 |
| 日志 | 158份副本哈希一致；119份可访问原件一致；37 copy-only与2 unavailable如实保留有限结论 |
| 完整负矩阵 | 23/23 PASS，recorder实际0，实际负例退出与各自期望一致 |
| checker自测 | clean及Git否定规则clean通过，26/26变异实际拒绝且reason匹配，绑定当前冻结checker |
| 真实后端/pytest | 健康/N04、归因健康/失败与baseline观察符合预期；pytest 100 passed、74 warnings、实际0 |
| 两遍协议 | prior真实0、报告哈希/同根/当前版本绑定；Final真实0，EVIDENCE_CHECK与final报告同哈希 |
| 输出体积 | 1103文件、50,910,014 bytes；最大文件316,075 bytes；没有字体/模型/pyc |
| 凭据初筛 | 高置信OpenAI/GitHub token及私钥头模式无命中，不扩张为对所有敏感信息的保证 |

最终机器状态 PASS，原始计数 expected=945、checked=706、failed=0、unverified=0、not_applicable=37、skipped=0。202个手动哈希检查未计入checked的既有口径保持披露；本审已全部重算，不能简写为“945/945 PASS”。

## 本轮短修的真实闭环

- **宿主编码**：整轮由 WinPS5.1 写入/读取BOM一致的JSON；relay实际0，原混合宿主路径解码失败没有重现。
- **运行窗口**：perprocess健康 started_at=20:24:17.558、ended_at=20:26:01.619，时长104.0616秒；N04为20:26:02.406→20:27:02.815，60.4087秒。均在外层recorder窗口内，result_built_at晚于真实ended_at，writer未再覆盖。这里包含准备/预检/采样/回收，不是纯采样时长或产品启动耗时。
- **夹具体积**：两次 isolation 的损坏缓存均外置 owned TEMP，证据只留owner/source/路径及日志；原大缓存根没有删除，新根没有字体或模型文件。没有靠删除必要字体或关闭功能制造体积下降。

## 固定校验值

| 工件 | SHA256 |
|---|---|
| EVIDENCE_CHECK.json | CB33C1344696CDBF37C4EBC5AADC1D0351AB2F94C5178DD14AC55C53D50BCEF7 |
| INPUT_MANIFEST.json | 5FD1D7FDDBFEF7C5CA76D65BB77F9BE317D2F13CB41149A1163F569391A9F762 |
| runs/checker-prior-pass/report.json | 6393812E145342A0E495837088C3CAE160CDE1690BBD4CB217F1B436BB5DAEC0 |

## 镜像与残余边界

允许逐字节复制这1103个文件到主仓库供提交，**不改任何absolute观测**。原冻结根保留；镜像必须标注实际执行根、冻结commit、镜像时间及逐文件复制核验。ORIGIN说明和外层观察副本可放在封存根之外，避免改变INPUT_MANIFEST或制造未声明输入。

镜像是原运行工件的副本，不是实际执行位置。原checker严格绑定绝对entry-run目录；在镜像路径直接当新根执行可能报路径不一致，不能为通过而重写旧JSON。另一台电脑可重算相对输入清单/哈希、审核原始日志与身份；需要重新运行时，检出冻结源码、准备锁定依赖/离线资产并创建新根，不继承原电脑运行通过。

CSV第17行逗号错列仍保留原件，N01由直接guard/vector证据支持；后续可按新版本修复，不编辑本轮raw CSV。所有P1结果仍需真实测试与独立审核；自有WPF渲染截图应准确标注验证范围，不把它描述成OS输入自动化或对话框/DPI实测。
