# 渠道、批量与输出修订：独立复审

审核分支 `codex/channels-batch-output-2026-11-04`，基点 `74d54222b58f8ab8ab104aabe6eba66978cc6290`。本次实现尚未提交，不能把基点当作被测实现提交。审核者未参与实现；本轮只读代码、日志、JSON、截图和本轮自有 PDF 的哈希，没有启动程序、联网、访问真实用户 home、修改产品或执行 Git 暂存。

## 当前结论

C01–C04 及随后发现的两个迁移边界均已关闭。当前产品差异和已提供的真实流程证据没有发现新的功能阻断，可以继续冻结、构建与核验最终包。本报告是阶段性独立复审，**尚未批准最终包或本轮最终提交推送**；待包与最终界面字节核验后补终裁。旧 Ardot 包和运行结论不代替本轮新功能验收。

## 阻断关闭情况

| 项目 | 本轮核实的修复与证据 |
| --- | --- |
| C01 密钥明文落盘 | `http_api.apply_settings` 的 `persist_secrets` 默认仍为 True，CLI/web 默认行为保留；native 明确传 False，写无密钥 clone，仅在内存保留实际配置。ConfigManager 的可选 resolver 在验证前注入 DPAPI 凭据，该路径不输出初始化模型调试 dump。渠道与偏好进入同一设置事务，空偏好变更也持久化渠道，失败恢复两者及内存。 |
| C01 旧配置备份 | 新 native 迁移保存可无损恢复的 DPAPI 原字节归档，带大小/SHA 校验；旧源保持原字节。新 home 内目标配置脱敏，已有本程序明文备份在归档校验和 marker 持久化之后才移除。首次 bootstrap 仅在尚无渠道档案时从归档恢复缺失凭据，之后由渠道档案恢复。 |
| 迁移发布失败 | prepared marker 先于脱敏目标发布；目标以独占临时文件及 Windows 拒绝覆盖 rename 发布。committed marker 失败保留 prepared，重启可恢复；已有不同目标会拒绝覆盖。 |
| 迁移路径归属 | `owned_path` 从 home 逐级 lstat，拒绝文件/祖先重解析点，再核 resolved 归属。原生入口、归档、marker、恢复目标与旧备份删除均调用该检查，不能把 junction 指向的外部根当作本程序拥有目录。 |
| C02 批量渠道漂移 | VM 在循环前捕获 active channel id/revision；API 按明确 profile 构建 service/base/model/key，revision 改变返回 409。请求指纹包含渠道身份；同批首份响应期间切换 active，不会改变剩余文件渠道。 |
| C03 过期探测覆盖草稿 | Service/Base/Model/Name/Key/Clear 和选择变化推进 generation 并取消关联探测；返回前核 generation/取消状态，过期响应不改其它渠道草稿。 |
| C04 慢响应占满探测槽 | 探测使用异步 HTTP、15 秒总 deadline，保留连接/读取限制；请求断连取消操作，finally 释放槽，拒绝 redirect 和过大响应，错误不回显提供方原始正文或密钥。 |

已读取 `channels-backend-tests-f912db548b` 的 actual_exit=0、42 passed，以及 `channels-migration-tests-46a4155f4b` 的 actual_exit=0、15 passed。专项包含 prepared/committed 两时点失败恢复、新迁移与旧 marker 升级、归档恢复原字节、重启凭据注入、新 home 明文哨兵阴性，以及 owned 外部 sentinel/junction 拒绝且外部字节和集合不变。这些是本地夹具测试，不能描述为真实用户配置迁移实测。

## 本轮完整真实流程

`docs/verification/native-desktop/channels-workflow-abc0265562` 外层 actual_exit=0、passed=true、timeout=false、observer_errors=[]、surviving_identities=[]。其 `ui/ui-result.json` 为真实运行中 WPF 的结果，DLL SHA256 `5B5AAAC2AF7712DF23C0D274AC027BBFEFC80B24589E3080DBE41E80D648B0CA`。这轮使用仓库源码 overlay 和旧包的私有运行时，**不是新安装包验收**。provenance 的 10 个 Python 文件与当前字节全部匹配。

- 实际保存两个具名渠道，探测模型、发送回环测试请求、延迟 A 的模型响应后切 B，B 草稿不变；后端重启后渠道、目录与 DPAPI 密钥恢复。提供方记录共 87 次，认证匹配失败为 0；翻译请求 A 为 45 次、B 为 40 次，另外 2 次为探测。
- 三份真实 PDF 为 7/2/1 页，界面实际导入、显示三行，批量创建三个不同任务。首份响应返回前切换 B，三个任务仍均绑定 A，并真实完成。`AllPages=true` 时即使遗留 Pages="1-5" 草稿，提交仍为全部页面；7 页双语产物与另一次 7 页单语产物都存在，pdf-audit 记录末页有中文，界面实际预览第 7/7 页。
- 双语单选时三个任务只有 dual；随后通过真实 ToggleSwitch 改为仅译文，新任务只有 mono。源目录模式每份仅生成一个 `_双语对照.pdf`，直接位于各自源 PDF 旁边。自定义目录按文章文件夹保存 `_译文.pdf`，更改当前保存目录后实际使用新目录，重复保存保留 `_第2版.pdf`。
- 丢保存响应先留下 pending，回放后仅一个文件；后续明确新保存生成版本。三篇文章分组包含四次任务，原 PDF 字节保持；最终重启后默认位置、保存方式、当前渠道与四项历史均恢复。10 份被记录的输出/保存 PDF 合计读取 324,166 字节，审核者逐份核大小/SHA，无不符。

`NativeWorkflowVerification` 的断言读取实际 API 配置、共享 TaskRow、实际产物和目录；失败会抛错，没有把合成列表或仅修改 VM 变量当作真实翻译完成。实际控件绑定的检查使用运行中 ToggleSwitch，批量渠道切换注入位于真实首份 API 响应返回前。全部提供方流量为回环夹具，没有付费服务实测结论。

源目录由上传时实际源文件与上传副本的大小/SHA 匹配后记录；保存接口按 mode 与本次 kinds 处理，禁用输出不会重新混入。旧无 kinds 保存请求的指纹形状保留；已有操作沿用记录文件的父目录，避免旧日期文件夹回放迁移到新文章文件夹。现有共享任务引用、隐藏页不清全局选择、快照脱敏和幂等 outbox 路径未见新增阻断。

## Python 与视觉证据

`channels-full-pytest-fee2387c5d` 记录 actual_exit=0，146 passed、74 warnings，246.71 秒；日志显示 HOME/USERPROFILE/CWD/config 位于 owned 临时隔离根。`source-identity.json` 的 20 个文件逐一与当前 SHA 匹配，不把仅有 HEAD 字段当工作区字节绑定。warnings 为现有依赖/旧界面弃用警告，不是本轮测试失败。

已独立查看 `02-channel-management.png`、`03-three-files-980.png`、`06-translated-page-seven.png`、`07-article-history-and-save-directory.png`、`08-results-dark.png`。渠道列表/编辑与密钥不回显、980 DIP 三行文件/语言和固定提交动作、页七、三文章记录、保存目录与中文版本、浅深色选中项均可读。内容超出高度时由明确滚动区容纳，没有观察到新的相互覆盖。页面继续组合 WPF UI 与 XamlFlair；没有新增 CSS、控件皮肤或手写动画。

本轮上述 DLL 之后，仅有进度卡空态、任务渠道显示和 padding 微调；当前代码静态关系合理，但旧图不能声称已执行这些最终界面字节。DEBUG 独立 home 的验证 mutex 和启动错误记录受编译条件及测试路径检查约束，Release 仍使用全局单实例；这不是通过放宽 Release 行为获得的结果。

| 本轮证据 | SHA256 |
| --- | --- |
| workflow/result.json | `A7D44171691FCE3E5080B14DC039CF9B47F592839C5490A562E1CBB45DA28D46` |
| workflow/provenance.json | `B41B33616F5CD1DAB8B2797309B47EAD654AA26B901B0BE343F03AFA10B433A9` |
| workflow/ui/ui-result.json | `B086270CA1D8D9BFFE1DBF653D3BEE93B014B9D2F508DF27742EB4F1F410B7CC` |
| workflow/pdf-audit.json | `9D05CD7CC68C737740DD3D82329CEAA8C530377FF8077D13D57E4D0B48D46B9C` |
| full-pytest/source-identity.json | `4E8047FA3C1BDFB8E22EADBF609B4BE5D6D0B287F2E54C65EBE5EEE7504FDF51` |

## 最终复核边界

尚待最终源码冻结身份、新 Release/安装包的源码与清单哈希绑定、锁定依赖/许可证及最终包运行记录，以及上述最后界面微调的当前字节截图。之后再核公开交付索引与 Git 候选，不把本地运行环境、模型字体缓存、测试二进制或非本轮进程元数据提交。

图片由真实运行中 WPF VisualTree/RenderTargetBitmap 生成，不是 OS 输入自动化。OS 文件/目录对话框输入、系统拖放、跨屏 DPI 仍未实测；本报告不补写为通过。旧间歇启动/响应超时的风险也不因本轮成功而宣称已经消除。本轮未重做完整性能/安装生命周期矩阵或商业长文档质量验证，不继承这些范围的历史通过；仍不批准 main、force push、tag 或 Release。
