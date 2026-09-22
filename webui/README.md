# webui —— PDFMathTranslate-next Web 界面

桌面版界面源码 + 与后端 REST API 的接线，来自 ardot 设计稿（页面「PDF 翻译工作台 PDFMathTranslate」与「弹窗与提示 Dialogs」）。

## 目录内容

| 路径 | 说明 |
|---|---|
| `index.html` · `styles.css` · `ui.css` · `app.js` | **前端实现**：语义化 HTML + Flexbox/Grid + 设计令牌；`ui.css` 为弹窗/提示与桌面观感样式；`app.js` 含 `ui` 组件层与 API 接线 |
| `design-export/` | ardot 原始导出（5 个页面，绝对定位），仅作像素级视觉参照，勿直接修改；弹窗组件见 ardot 页面「弹窗与提示 Dialogs」 |

## 页面

- **翻译工作台**（`#home`，默认）：拖拽/点击上传 PDF → 页面范围 → 开始翻译（双语/单语/水印/术语提取开关）；右栏为预览、进度（实时轮询）、翻译历史、常用术语
- **设置**（`#settings`）：翻译服务、API Key、API Base URL、模型、自定义提示词、限流模式/QPS/并发线程、译文主字体、界面语言/主题、保存设置
- **任务队列**（`#queue`）：全部任务（状态圆点、进度、下载、打开输出目录）+ 清空记录
- **文档输出**（`#outputs`）：输出文件卡片（双语/单语）+ 全部下载
- **术语表**（`#glossary`）：术语对照表，上传 CSV、删除条目、下载自动提取的术语表

## ui 组件层（`app.js` 内 `ui`）

| 方法 | 用途 |
|---|---|
| `ui.success/error/info(title, desc)` | 右下角 Toast 提示（3.2s / 失败 5.2s 自动消失，可手动关闭） |
| `ui.loading(title, desc)` | 带进度条的常驻 Toast，返回 `{close, update}` |
| `ui.confirm({title, desc, confirmText, cancelText, destructive})` | 遮罩 + 对话框，返回 `Promise<boolean>`；Esc 取消、Enter 确认 |
| `ui.alert(title, desc)` | 单按钮信息对话框 |

已完全替代浏览器原生 `alert` / `confirm`（原生弹窗会暴露"网页"身份）。

## 桌面观感（不让使用者看出是网页）

- 前端：禁止选中界面文字（输入框除外）、禁用图片拖拽、自定义细窄滚动条、去掉点击高亮与焦点虚线、禁用 overscroll 橡皮筋
- 桌面壳（`launcher/MainForm.cs`）：关闭 WebView2 默认右键菜单、开发者工具、状态栏、缩放控制、浏览器快捷键（F5/Ctrl+P 等）、自动填充；下载静默保存到「下载」目录（无浏览器式下载提示）

## 后端 API（`pdf2zh_next/http_api.py`，FastAPI）

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/api/version` | 版本号 |
| GET / PUT | `/api/settings` | 读取 / 保存设置 |
| POST | `/api/files` | 上传 PDF（返回 `file_id` / `size` / `pages`） |
| POST | `/api/tasks` | 提交翻译任务（后台线程执行） |
| GET | `/api/tasks` | 任务列表（含进度、`page_count`、输出路径） |
| GET | `/api/tasks/{id}` | 单个任务状态 |
| POST | `/api/tasks/{id}/cancel` | 取消任务 |
| DELETE | `/api/tasks` | 清空任务记录（不删除输出文件） |
| GET | `/api/tasks/{id}/download?kind=dual\|mono\|glossary` | 下载输出文件（术语表为 `text/csv`） |
| GET / POST | `/api/glossary` | 读取 / 上传术语表（CSV） |
| DELETE | `/api/glossary/{source}?file=xxx.csv` | 删除某条术语 |
| POST | `/api/reveal` | 在系统资源管理器中定位输出文件（限工作目录内） |
| GET | `/api/files/{id}/preview?page=N` | 上传 PDF 的指定页预览（PNG，含 `X-Page-Count` 头） |
| GET | `/api/tasks/{id}/preview?kind=dual\|mono&page=N` | 译文指定页预览（PNG） |
| POST | `/api/tasks/{id}/retry` | 用原文件重新提交翻译 |
| GET / PUT | `/api/prefs` | 界面偏好（`theme` / `auto_update` / `open_output_dir`） |
| GET | `/` | 静态托管本目录 |

任务记录保存在 `pdf2zh_files/tasks.json`（最近 50 条）。

## 启动方式

```powershell
.\PDFMathTranslate.exe                  # 新界面（桌面壳默认）
.\PDFMathTranslate.exe --legacy-gui     # Gradio 旧界面（兼容保留）
python start-webui.py --server-port 7860  # 直接跑后端（开发用）
```

环境变量：`PDF2ZH_WEBUI_DIR`（覆盖静态目录）、`PDF2ZH_HOME`（覆盖便携数据目录，便于测试）。

## 已接入

- **PDF 预览**：PyMuPDF 渲染当前页（PNG），支持上/下翻页与页码；翻译完成后自动切到译文预览
- **深色主题**：跟随系统 / 浅色 / 深色，顶栏按钮与「设置 → 主题」联动，偏好持久化
- **偏好持久化**：`ui-prefs.json`（theme / auto_update / open_output_dir），桌面壳启动时读取 `auto_update` 决定是否自动检查更新
- **顶栏**：GitHub 外链（走系统浏览器）、界面语言切换（持久化到设置）
- **限流模式联动**：QPS / RPM / 并发请求数 切换时显示对应输入框，保存时自动换算（RPM ÷ 60 → QPS）
- **其它**：移除已选文件、失败任务一键重试（`/api/tasks/{id}/retry`）

## 仍未接入

- **界面文案多语言本地化**：切换语言只保存偏好，界面文案仍为中文
- **输出目录自定义**、**一次选择多份文件**

## 配置安全（重要）

`PUT /api/settings` 会先在设置副本上修改、通过 `validate_settings()` 后才写入 `config.v3.toml`；字体族与语言先归一化（界面显示名 → 合法值，如「思源黑体 Source Han Sans」→ `sans-serif`、`English` → `en`），非法值返回 **400 且不落盘**——避免写坏配置导致应用无法启动（此坑已踩过）。
