"""REST API + 静态托管 Web UI（webui/ 目录）。

设计要点
--------
- 复用既有配置系统（ConfigManager）读写 ``config.v3.toml``；
- 复用 ``high_level.do_translate_async_stream`` 执行翻译，实时把进度事件
  映射到任务状态；
- 任务在后台线程运行，状态保存在内存并持久化到 ``pdf2zh_files/tasks.json``；
- 静态托管 ``webui/``（新界面），Gradio 旧界面仍可独立启动（见 start-gui-direct.py）。

启动方式见 ``start-webui.py``，或：``python -m pdf2zh_next.http_api --server-port 7860``
"""

from __future__ import annotations

import argparse
import asyncio
import json
import logging
import os
import re
import subprocess
import threading
import time
import uuid
from dataclasses import asdict
from dataclasses import dataclass
from dataclasses import field as dataclass_field
from pathlib import Path
from typing import Any

from fastapi import FastAPI
from fastapi import File
from fastapi import Form
from fastapi import HTTPException
from fastapi import UploadFile
from fastapi.responses import FileResponse
from fastapi.responses import JSONResponse
from fastapi.responses import Response
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

from pdf2zh_next import __version__
from pdf2zh_next.config.main import ConfigManager
from pdf2zh_next.config.translate_engine_model import TRANSLATION_ENGINE_METADATA

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# 目录与常量
# ---------------------------------------------------------------------------
WORK_DIR = Path("pdf2zh_files").resolve()
UPLOAD_DIR = WORK_DIR / "uploads"
OUTPUT_DIR = WORK_DIR / "outputs"
TASKS_FILE = WORK_DIR / "tasks.json"
MAX_HISTORY = 50


def _pdf_page_count(path: Path) -> int | None:
    """用 PyMuPDF 读取页数；失败返回 None。"""
    try:
        import pymupdf

        with pymupdf.open(str(path)) as doc:
            return int(doc.page_count)
    except Exception:
        pass
    try:
        import fitz

        with fitz.open(str(path)) as doc:
            return int(doc.page_count)
    except Exception:
        return None


def _render_page_png(path: Path, page: int, width: int = 900) -> Response:
    """把 PDF 指定页渲染成 PNG（宽度约 width 像素）。"""
    try:
        import pymupdf
    except Exception:  # pragma: no cover - 兼容旧包名
        import fitz as pymupdf

    try:
        with pymupdf.open(str(path)) as doc:
            total = int(doc.page_count)
            index = max(0, min(page - 1, total - 1))
            pdf_page = doc.load_page(index)
            scale = max(0.2, min(3.0, width / max(1.0, float(pdf_page.rect.width))))
            pixmap = pdf_page.get_pixmap(matrix=pymupdf.Matrix(scale, scale), alpha=False)
            return Response(
                content=pixmap.tobytes("png"),
                media_type="image/png",
                headers={
                    "X-Page-Count": str(total),
                    "X-Page-Index": str(index + 1),
                    "Cache-Control": "no-store",
                },
            )
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"页面渲染失败：{exc}") from exc


def resolve_webui_dir() -> Path | None:
    """按 环境变量 → 当前工作目录 → 包内/仓库 的顺序定位 webui 目录。"""
    import os

    candidates: list[Path] = []
    env_dir = os.environ.get("PDF2ZH_WEBUI_DIR")
    if env_dir:
        candidates.append(Path(env_dir))
    candidates.append(Path.cwd() / "webui")
    here = Path(__file__).resolve()
    candidates.append(here.parent / "webui")  # 包内
    candidates.append(here.parent.parent.parent / "webui")  # 仓库根（source/pdf2zh_next/../..）
    for candidate in candidates:
        if (candidate / "index.html").is_file():
            return candidate.resolve()
    return None


# ---------------------------------------------------------------------------
# 任务模型
# ---------------------------------------------------------------------------
@dataclass
class Task:
    id: str
    filename: str
    file_path: str
    lang_in: str
    lang_out: str
    status: str = "queued"  # queued | running | done | failed | cancelled
    progress: float = 0.0  # 0-100
    stage: str = ""
    message: str = ""
    error: str = ""
    pages: str | None = None
    page_count: int | None = None
    created_at: float = dataclass_field(default_factory=time.time)
    finished_at: float | None = None
    duration: float | None = None
    outputs: dict[str, str] = dataclass_field(default_factory=dict)
    cancel_requested: bool = False

    def to_dict(self) -> dict[str, Any]:
        data = asdict(self)
        data.pop("cancel_requested", None)
        data.pop("file_path", None)
        return data


class TaskRegistry:
    """线程安全的任务表（内存 + JSON 持久化）。"""

    def __init__(self) -> None:
        self._lock = threading.RLock()
        self._tasks: dict[str, Task] = {}
        self._load()

    # -- 持久化 ---------------------------------------------------------
    def _load(self) -> None:
        try:
            if TASKS_FILE.is_file():
                raw = json.loads(TASKS_FILE.read_text(encoding="utf-8"))
                for item in raw.get("tasks", []):
                    task = Task(
                        id=item["id"],
                        filename=item["filename"],
                        file_path=item.get("file_path", ""),
                        lang_in=item.get("lang_in", ""),
                        lang_out=item.get("lang_out", ""),
                        status=item.get("status", "done"),
                        progress=item.get("progress", 0.0),
                        stage=item.get("stage", ""),
                        message=item.get("message", ""),
                        error=item.get("error", ""),
                        pages=item.get("pages"),
                        page_count=item.get("page_count"),
                        created_at=item.get("created_at", time.time()),
                        finished_at=item.get("finished_at"),
                        duration=item.get("duration"),
                        outputs=item.get("outputs", {}),
                    )
                    # 上次退出时仍在进行的任务标记为中断
                    if task.status in ("queued", "running"):
                        task.status = "failed"
                        task.error = "任务被中断（应用已重启）"
                    self._tasks[task.id] = task
        except Exception as exc:  # pragma: no cover - 容错
            logger.warning("读取任务历史失败：%s", exc)

    def _save(self) -> None:
        try:
            TASKS_FILE.parent.mkdir(parents=True, exist_ok=True)
            items = [t.to_dict() for t in self._ordered()[:MAX_HISTORY]]
            TASKS_FILE.write_text(
                json.dumps({"tasks": items}, ensure_ascii=False, indent=2),
                encoding="utf-8",
            )
        except Exception as exc:  # pragma: no cover - 容错
            logger.warning("保存任务历史失败：%s", exc)

    def _ordered(self) -> list[Task]:
        return sorted(self._tasks.values(), key=lambda t: t.created_at, reverse=True)

    # -- 接口 -----------------------------------------------------------
    def add(self, task: Task) -> Task:
        with self._lock:
            self._tasks[task.id] = task
            self._save()
        return task

    def get(self, task_id: str) -> Task | None:
        with self._lock:
            return self._tasks.get(task_id)

    def list(self) -> list[Task]:
        with self._lock:
            return self._ordered()

    def update(self, task_id: str, persist: bool = False, **changes: Any) -> Task | None:
        with self._lock:
            task = self._tasks.get(task_id)
            if task is None:
                return None
            for key, value in changes.items():
                setattr(task, key, value)
            if persist:
                self._save()
            return task


REGISTRY = TaskRegistry()


# ---------------------------------------------------------------------------
# 设置读写
# ---------------------------------------------------------------------------
def _config_manager() -> ConfigManager:
    manager = ConfigManager()
    if manager._settings is None:  # noqa: SLF001 - 与 gui.py 相同用法
        manager.initialize_config()
    return manager


def _cli_settings() -> Any:
    """面向界面的设置对象（CLIEnvSettingsModel：含引擎 flag 与详情字段）。"""
    manager = _config_manager()
    cli = manager.config_cli_settings
    if cli is None:
        raise HTTPException(status_code=500, detail="配置未初始化")
    return cli


def _current_engine(settings: Any) -> tuple[str | None, Any]:
    """返回当前翻译引擎类型与其详情模型。

    优先看显式选中的引擎 flag；若都没有（全新配置），回退到配置系统
    已解析出的引擎（默认 SiliconFlowFree）。
    """
    for meta in TRANSLATION_ENGINE_METADATA:
        if getattr(settings, meta.cli_flag_name, False):
            detail = (
                getattr(settings, meta.cli_detail_field_name)
                if meta.cli_detail_field_name
                else None
            )
            return meta.translate_engine_type, detail

    try:
        engine_type = settings.to_settings_model().translate_engine_settings.translate_engine_type
    except Exception:
        engine_type = None
    if engine_type:
        for meta in TRANSLATION_ENGINE_METADATA:
            if meta.translate_engine_type == engine_type:
                detail = (
                    getattr(settings, meta.cli_detail_field_name)
                    if meta.cli_detail_field_name
                    else None
                )
                return engine_type, detail
    return None, None


def _pick_field(detail: Any, *keywords: str) -> str | None:
    """在详情模型里按关键词找字段名（兼容各引擎的命名差异）。"""
    if detail is None:
        return None
    names = list(detail.model_fields.keys())
    for keyword in keywords:
        for name in names:
            if name == keyword or name.endswith(f"_{keyword}"):
                return name
    for keyword in keywords:
        for name in names:
            if keyword in name:
                return name
    return None


def _mask_secret(value: str | None) -> str:
    if not value:
        return ""
    if len(value) <= 8:
        return "••••"
    return f"{value[:3]}••••••••{value[-4:]}"


def settings_payload() -> dict[str, Any]:
    settings = _cli_settings()
    engine, detail = _current_engine(settings)
    api_key_field = _pick_field(detail, "api_key")
    base_url_field = _pick_field(detail, "base_url")
    model_field = _pick_field(detail, "model")
    api_key = getattr(detail, api_key_field, "") if api_key_field else ""
    return {
        "version": __version__,
        "service": engine,
        "services": [meta.translate_engine_type for meta in TRANSLATION_ENGINE_METADATA],
        "api_key_masked": _mask_secret(api_key),
        "api_key_set": bool(api_key),
        "base_url": (getattr(detail, base_url_field, "") if base_url_field else "") or "",
        "model": (getattr(detail, model_field, "") if model_field else "") or "",
        "custom_system_prompt": settings.translation.custom_system_prompt or "",
        "qps": settings.translation.qps,
        "pool_max_workers": settings.translation.pool_max_workers,
        "primary_font_family": settings.translation.primary_font_family or "",
        "ui_lang": settings.gui_settings.ui_lang,
        "lang_in": settings.translation.lang_in,
        "lang_out": settings.translation.lang_out,
        "pages": settings.pdf.pages or "",
        "no_dual": settings.pdf.no_dual,
        "no_mono": settings.pdf.no_mono,
        "watermark_output_mode": settings.pdf.watermark_output_mode,
        "auto_term_extraction": not settings.translation.no_auto_extract_glossary,
        "glossaries": settings.translation.glossaries or "",
    }


_LANG_ALIASES = {
    "english": "en",
    "simplified chinese": "zh-CN",
    "简体中文": "zh-CN",
    "chinese": "zh-CN",
    "traditional chinese - taiwan": "zh-TW",
    "繁體中文": "zh-TW",
    "traditional chinese - hong kong": "zh-HK",
    "japanese": "ja",
    "日本語": "ja",
    "korean": "ko",
    "한국어": "ko",
    "german": "de",
    "deutsch": "de",
    "french": "fr",
    "spanish": "es",
    "russian": "ru",
    "portuguese": "pt",
    "italian": "it",
    "dutch": "nl",
    "polish": "pl",
    "vietnamese": "vi",
    "indonesian": "id",
    "malay": "ms",
    "turkish": "tr",
    "arabic": "ar",
    "auto": "auto",
    "自动检测": "auto",
    "auto detect": "auto",
}

# 译文主字体：仅接受 serif / sans-serif / script（见 config/model.py 校验）
_FONT_ALIASES = {
    "": None,
    "跟随默认": None,
    "默认": None,
    "sans-serif": "sans-serif",
    "serif": "serif",
    "script": "script",
    "思源黑体 source han sans": "sans-serif",
    "思源黑体": "sans-serif",
    "noto sans sc": "sans-serif",
    "微软雅黑 microsoft yahei": "sans-serif",
    "微软雅黑": "sans-serif",
    "宋体 simsun": "serif",
    "宋体": "serif",
    "noto serif cjk sc": "serif",
}


def _normalize_lang(value: str | None) -> str | None:
    """接受语言代码（en / zh-CN）或界面显示名（English / 简体中文）。"""
    if value is None:
        return None
    text = value.strip()
    if not text:
        return None
    return _LANG_ALIASES.get(text.lower(), text)


def _normalize_font(value: str | None) -> str | None:
    if value is None:
        return None
    text = value.strip()
    key = text.lower()
    if key in _FONT_ALIASES:
        return _FONT_ALIASES[key]
    if text in ("serif", "sans-serif", "script"):
        return text
    raise HTTPException(
        status_code=400,
        detail=f"不支持的译文主字体：{text}（可选 serif / sans-serif / script）",
    )


class SettingsUpdate(BaseModel):
    service: str | None = None
    api_key: str | None = None
    base_url: str | None = None
    model: str | None = None
    custom_system_prompt: str | None = None
    qps: int | None = None
    pool_max_workers: int | None = None
    primary_font_family: str | None = None
    ui_lang: str | None = None
    lang_in: str | None = None
    lang_out: str | None = None
    no_dual: bool | None = None
    no_mono: bool | None = None
    auto_term_extraction: bool | None = None


def apply_settings(update: SettingsUpdate) -> dict[str, Any]:
    manager = _config_manager()
    # 在副本上修改，校验通过后再提交，避免写坏配置导致应用无法启动
    settings = _cli_settings().clone()

    if update.service:
        known = {meta.translate_engine_type for meta in TRANSLATION_ENGINE_METADATA}
        if update.service not in known:
            raise HTTPException(status_code=400, detail=f"未知翻译服务：{update.service}")
        for meta in TRANSLATION_ENGINE_METADATA:
            setattr(settings, meta.cli_flag_name, meta.translate_engine_type == update.service)

    engine, detail = _current_engine(settings)
    if detail is not None:
        for keyword, value in (
            ("api_key", update.api_key),
            ("base_url", update.base_url),
            ("model", update.model),
        ):
            if value:
                target = _pick_field(detail, keyword)
                if target:
                    setattr(detail, target, value)

    if update.qps is not None and not (1 <= update.qps <= 1000):
        raise HTTPException(status_code=400, detail="QPS 需在 1–1000 之间")
    if update.pool_max_workers is not None and not (1 <= update.pool_max_workers <= 1024):
        raise HTTPException(status_code=400, detail="并发线程数需在 1–1024 之间")

    if update.custom_system_prompt is not None:
        settings.translation.custom_system_prompt = update.custom_system_prompt
    if update.qps is not None:
        settings.translation.qps = update.qps
    if update.pool_max_workers is not None:
        settings.translation.pool_max_workers = update.pool_max_workers
    if update.primary_font_family is not None:
        settings.translation.primary_font_family = _normalize_font(update.primary_font_family)
    if update.ui_lang is not None:
        settings.gui_settings.ui_lang = update.ui_lang
    if update.lang_in is not None:
        settings.translation.lang_in = _normalize_lang(update.lang_in) or settings.translation.lang_in
    if update.lang_out is not None:
        settings.translation.lang_out = _normalize_lang(update.lang_out) or settings.translation.lang_out
    if update.no_dual is not None:
        settings.pdf.no_dual = update.no_dual
    if update.no_mono is not None:
        settings.pdf.no_mono = update.no_mono
    if update.auto_term_extraction is not None:
        settings.translation.no_auto_extract_glossary = not update.auto_term_extraction

    try:
        settings.validate_settings()
    except Exception as exc:
        logger.warning("设置校验失败，未保存：%s", exc)
        raise HTTPException(status_code=400, detail=f"设置无效，未保存：{exc}") from exc

    manager.write_user_default_config_file(settings=settings)
    manager.config_cli_settings = settings
    try:
        manager._settings = settings.to_settings_model()  # noqa: SLF001
    except Exception as exc:  # pragma: no cover - 容错
        logger.warning("刷新内存设置失败：%s", exc)
    logger.info("设置已保存（引擎：%s）", engine)
    return settings_payload()


# ---------------------------------------------------------------------------
# 翻译任务执行
# ---------------------------------------------------------------------------
def _run_task(task_id: str, base_settings: Any, file_path: Path) -> None:
    from pdf2zh_next.high_level import do_translate_async_stream

    task = REGISTRY.get(task_id)
    if task is None:
        return

    REGISTRY.update(
        task_id,
        status="running",
        progress=0.0,
        stage="启动翻译引擎",
        message="正在启动翻译引擎…",
        persist=True,
    )
    started = time.time()

    async def consume(stream) -> None:
        async for event in stream:
            current = REGISTRY.get(task_id)
            if current is None or current.cancel_requested:
                break

            kind = event.get("type")
            if kind in ("progress_start", "progress_update", "progress_end"):
                stage = event.get("stage", "")
                overall = float(event.get("overall_progress") or 0.0)
                part_index = event.get("part_index")
                total_parts = event.get("total_parts")
                stage_current = event.get("stage_current")
                stage_total = event.get("stage_total")
                message = f"{stage}"
                if part_index and total_parts:
                    message += f" · 第 {part_index}/{total_parts} 部分"
                if stage_current and stage_total:
                    message += f"（{stage_current}/{stage_total}）"
                REGISTRY.update(
                    task_id,
                    progress=overall,
                    stage=stage,
                    message=message,
                )
            elif kind == "finish":
                result = event["translate_result"]
                outputs: dict[str, str] = {}
                for key, value in (
                    ("dual", getattr(result, "dual_pdf_path", None)),
                    ("mono", getattr(result, "mono_pdf_path", None)),
                    ("glossary", getattr(result, "auto_extracted_glossary_path", None)),
                ):
                    if value:
                        outputs[key] = str(value)
                REGISTRY.update(
                    task_id,
                    status="done",
                    progress=100.0,
                    stage="完成",
                    message="翻译完成",
                    outputs=outputs,
                    finished_at=time.time(),
                    duration=time.time() - started,
                    persist=True,
                )
                break
            elif kind == "error":
                REGISTRY.update(
                    task_id,
                    status="failed",
                    error=str(event.get("error") or "未知错误"),
                    message="翻译失败",
                    finished_at=time.time(),
                    duration=time.time() - started,
                    persist=True,
                )
                break

    async def run() -> None:
        stream = do_translate_async_stream(base_settings, file_path)
        consumer = asyncio.ensure_future(consume(stream))
        try:
            # 每秒检查一次取消标志：翻译引擎预热期间没有进度事件，
            # 不能只在事件到达时才响应取消
            while not consumer.done():
                current = REGISTRY.get(task_id)
                if current is None or current.cancel_requested:
                    consumer.cancel()
                    break
                await asyncio.wait({consumer}, timeout=1.0)
        finally:
            if not consumer.done():
                consumer.cancel()
            try:
                await consumer
            except (asyncio.CancelledError, Exception):
                pass
            try:
                # 显式关闭事件流，确保取消/结束时子进程被回收
                await stream.aclose()
            except Exception:
                pass

    try:
        asyncio.run(run())
    except Exception as exc:  # pragma: no cover - 兜底
        logger.exception("任务执行异常：%s", exc)
        REGISTRY.update(
            task_id,
            status="failed",
            error=str(exc),
            message="翻译失败",
            finished_at=time.time(),
            duration=time.time() - started,
            persist=True,
        )
    finally:
        current = REGISTRY.get(task_id)
        if current is not None and current.status in ("queued", "running"):
            if current.cancel_requested:
                REGISTRY.update(
                    task_id,
                    status="cancelled",
                    message="已取消",
                    finished_at=time.time(),
                    persist=True,
                )
            else:
                REGISTRY.update(
                    task_id,
                    status="failed",
                    error=current.error or "翻译未正常结束",
                    message="翻译失败",
                    finished_at=time.time(),
                    persist=True,
                )


class TaskCreate(BaseModel):
    file_id: str
    lang_in: str | None = None
    lang_out: str | None = None
    pages: str | None = None
    no_dual: bool | None = None
    no_mono: bool | None = None
    auto_term_extraction: bool | None = None


def create_task(payload: TaskCreate) -> Task:
    upload = UPLOAD_DIR / payload.file_id
    if not upload.is_file():
        raise HTTPException(status_code=404, detail="文件不存在，请重新上传")

    if payload.no_dual and payload.no_mono:
        raise HTTPException(
            status_code=400, detail="「双语对照输出」与「单语纯净输出」至少保留一项"
        )
    if payload.pages:
        pages = payload.pages.strip()
        if not re.fullmatch(r"[0-9,\-\s]+", pages):
            raise HTTPException(
                status_code=400,
                detail=f"页码范围格式无效：{payload.pages}（示例 1,3,5-10,-5）",
            )
        payload.pages = pages

    manager = _config_manager()
    settings = _cli_settings().clone()

    if payload.lang_in:
        settings.translation.lang_in = payload.lang_in
    if payload.lang_out:
        settings.translation.lang_out = payload.lang_out
    settings.pdf.pages = payload.pages or None
    if payload.no_dual is not None:
        settings.pdf.no_dual = payload.no_dual
    if payload.no_mono is not None:
        settings.pdf.no_mono = payload.no_mono
    if payload.auto_term_extraction is not None:
        settings.translation.no_auto_extract_glossary = not payload.auto_term_extraction

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    settings.translation.output = str(OUTPUT_DIR)

    translate_settings = settings.to_settings_model()
    translate_settings.basic.input_files = set()

    task = Task(
        id=uuid.uuid4().hex[:12],
        filename=payload.file_id.split("__", 1)[-1] if "__" in payload.file_id else payload.file_id,
        file_path=str(upload),
        lang_in=translate_settings.translation.lang_in,
        lang_out=translate_settings.translation.lang_out,
        pages=payload.pages,
        page_count=_pdf_page_count(upload),
        status="queued",
        message="排队中",
    )
    REGISTRY.add(task)
    threading.Thread(
        target=_run_task,
        args=(task.id, translate_settings, upload),
        name=f"translate-{task.id}",
        daemon=True,
    ).start()
    return task


# ---------------------------------------------------------------------------
# 术语表
# ---------------------------------------------------------------------------
def _glossary_files(settings: Any) -> list[Path]:
    raw = settings.translation.glossaries or ""
    return [Path(p) for p in raw.split(";") if p.strip()]


def _read_glossary_rows(path: Path) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    try:
        text = path.read_text(encoding="utf-8-sig", errors="replace")
    except Exception:
        return rows
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = [p.strip() for p in line.replace("\t", ",").split(",")]
        if len(parts) < 2:
            continue
        rows.append({"source": parts[0], "target": parts[1], "file": path.name})
    return rows


def list_glossary() -> list[dict[str, str]]:
    settings = _cli_settings()
    rows: list[dict[str, str]] = []
    for path in _glossary_files(settings):
        if path.is_file():
            rows.extend(_read_glossary_rows(path))
    return rows


# ---------------------------------------------------------------------------
# FastAPI 应用
# ---------------------------------------------------------------------------
app = FastAPI(title="PDFMathTranslate API", version=__version__)


@app.get("/api/version")
def api_version() -> dict[str, str]:
    return {"version": __version__}


@app.get("/api/settings")
def api_get_settings() -> dict[str, Any]:
    return settings_payload()


@app.put("/api/settings")
def api_put_settings(update: SettingsUpdate) -> dict[str, Any]:
    return apply_settings(update)


@app.post("/api/files")
async def api_upload_file(file: UploadFile = File(...)) -> dict[str, Any]:
    if not (file.filename or "").lower().endswith(".pdf"):
        raise HTTPException(status_code=400, detail="仅支持 PDF 文件")
    UPLOAD_DIR.mkdir(parents=True, exist_ok=True)
    safe_name = Path(file.filename or "document.pdf").name
    file_id = f"{uuid.uuid4().hex[:8]}__{safe_name}"
    target = UPLOAD_DIR / file_id
    size = 0
    with target.open("wb") as handle:
        while chunk := await file.read(1024 * 1024):
            handle.write(chunk)
            size += len(chunk)

    pages = _pdf_page_count(target)

    return {
        "file_id": file_id,
        "filename": safe_name,
        "size": size,
        "pages": pages,
    }


@app.get("/api/files/{file_id}/preview")
def api_file_preview(file_id: str, page: int = 1, width: int = 900) -> Response:
    """上传 PDF 的指定页预览。"""
    path = UPLOAD_DIR / file_id
    if not path.is_file():
        raise HTTPException(status_code=404, detail="文件不存在，请重新上传")
    return _render_page_png(path, page, width)


@app.get("/api/tasks/{task_id}/preview")
def api_task_preview(task_id: str, kind: str = "dual", page: int = 1, width: int = 900) -> Response:
    """翻译输出文件（dual / mono）的指定页预览。"""
    task = REGISTRY.get(task_id)
    if task is None:
        raise HTTPException(status_code=404, detail="任务不存在")
    target = task.outputs.get(kind)
    if not target or not Path(target).is_file():
        raise HTTPException(status_code=404, detail=f"暂无 {kind} 输出文件")
    return _render_page_png(Path(target), page, width)


@app.post("/api/tasks")
def api_create_task(payload: TaskCreate) -> dict[str, Any]:
    return create_task(payload).to_dict()


@app.get("/api/tasks")
def api_list_tasks() -> list[dict[str, Any]]:
    return [task.to_dict() for task in REGISTRY.list()]


@app.get("/api/tasks/{task_id}")
def api_get_task(task_id: str) -> dict[str, Any]:
    task = REGISTRY.get(task_id)
    if task is None:
        raise HTTPException(status_code=404, detail="任务不存在")
    return task.to_dict()


@app.post("/api/tasks/{task_id}/cancel")
def api_cancel_task(task_id: str) -> dict[str, Any]:
    task = REGISTRY.update(task_id, cancel_requested=True, message="正在取消…")
    if task is None:
        raise HTTPException(status_code=404, detail="任务不存在")
    return task.to_dict()


@app.post("/api/tasks/{task_id}/retry")
def api_retry_task(task_id: str) -> dict[str, Any]:
    """用原文件重新提交一次翻译。"""
    task = REGISTRY.get(task_id)
    if task is None:
        raise HTTPException(status_code=404, detail="任务不存在")
    source = Path(task.file_path)
    if not source.is_file():
        raise HTTPException(status_code=404, detail="源文件已被删除，请重新上传")
    payload = TaskCreate(
        file_id=source.name,
        lang_in=task.lang_in,
        lang_out=task.lang_out,
        pages=task.pages,
    )
    return create_task(payload).to_dict()


@app.get("/api/tasks/{task_id}/download")
def api_download(task_id: str, kind: str = "dual") -> FileResponse:
    task = REGISTRY.get(task_id)
    if task is None:
        raise HTTPException(status_code=404, detail="任务不存在")
    path = task.outputs.get(kind)
    if not path or not Path(path).is_file():
        raise HTTPException(status_code=404, detail=f"暂无 {kind} 输出文件")
    media = "text/csv" if kind == "glossary" else "application/pdf"
    return FileResponse(path, filename=Path(path).name, media_type=media)


class RevealRequest(BaseModel):
    path: str


@app.delete("/api/tasks")
def api_clear_tasks() -> dict[str, Any]:
    """清空任务记录（已生成的输出文件不会被删除）。"""
    with REGISTRY._lock:  # noqa: SLF001
        REGISTRY._tasks.clear()
        REGISTRY._save()
    return {"cleared": True}


@app.post("/api/reveal")
def api_reveal(payload: RevealRequest) -> dict[str, Any]:
    """在系统资源管理器中定位输出文件（仅允许工作目录内的路径）。"""
    target = Path(payload.path).resolve()
    work = WORK_DIR.resolve()
    if target != work and work not in target.parents:
        raise HTTPException(status_code=400, detail="路径不在允许范围内")
    if not target.exists():
        raise HTTPException(status_code=404, detail="文件不存在")
    if os.name == "nt":
        subprocess.Popen(["explorer", "/select,", str(target)])
    else:
        subprocess.Popen(["xdg-open", str(target.parent)])
    return {"revealed": str(target)}


def _prefs_path() -> Path:
    manager = _config_manager()
    return Path(manager._default_config_file_path).parent / "ui-prefs.json"  # noqa: SLF001


def read_prefs() -> dict[str, Any]:
    try:
        path = _prefs_path()
        if path.is_file():
            return json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        logger.warning("读取界面偏好失败：%s", exc)
    return {}


def write_prefs(data: dict[str, Any]) -> dict[str, Any]:
    prefs = read_prefs()
    prefs.update({k: v for k, v in data.items() if v is not None})
    try:
        path = _prefs_path()
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(prefs, ensure_ascii=False, indent=2), encoding="utf-8")
    except Exception as exc:
        logger.warning("保存界面偏好失败：%s", exc)
    return prefs


class PrefsUpdate(BaseModel):
    theme: str | None = None
    auto_update: bool | None = None
    open_output_dir: bool | None = None


@app.get("/api/prefs")
def api_get_prefs() -> dict[str, Any]:
    return read_prefs()


@app.put("/api/prefs")
def api_put_prefs(update: PrefsUpdate) -> dict[str, Any]:
    return write_prefs(update.model_dump())


@app.get("/api/glossary")
def api_list_glossary() -> list[dict[str, str]]:
    return list_glossary()


@app.post("/api/glossary")
async def api_upload_glossary(file: UploadFile = File(...)) -> list[dict[str, str]]:
    manager = _config_manager()
    settings = _cli_settings()
    glossary_dir = Path(settings.translation.glossaries or "").parent
    if not str(glossary_dir).strip() or not glossary_dir.is_absolute():
        glossary_dir = Path(manager._default_config_file_path).parent / "glossaries"  # noqa: SLF001
    glossary_dir.mkdir(parents=True, exist_ok=True)

    safe_name = Path(file.filename or "glossary.csv").name
    target = glossary_dir / safe_name
    with target.open("wb") as handle:
        while chunk := await file.read(1024 * 1024):
            handle.write(chunk)

    existing = [p for p in _glossary_files(settings) if p != target]
    existing.append(target)
    settings.translation.glossaries = ";".join(str(p) for p in existing)
    manager.write_user_default_config_file(settings=settings.clone())
    return list_glossary()


@app.delete("/api/glossary/{source}")
def api_delete_glossary(source: str, file: str | None = None) -> list[dict[str, str]]:
    settings = _cli_settings()
    for path in _glossary_files(settings):
        if file and path.name != file:
            continue
        if not path.is_file():
            continue
        lines = path.read_text(encoding="utf-8-sig", errors="replace").splitlines()
        kept = [
            line
            for line in lines
            if not line.strip() or line.split(",")[0].strip() != source
        ]
        path.write_text("\n".join(kept) + "\n", encoding="utf-8")
    return list_glossary()


@app.exception_handler(Exception)
async def unhandled_exception_handler(request, exc):  # pragma: no cover - 兜底
    logger.exception("未处理异常：%s", exc)
    return JSONResponse(status_code=500, content={"detail": str(exc)})


# 静态资源（放在最后，避免抢占 /api/*）
_webui_dir = resolve_webui_dir()
if _webui_dir is not None:
    app.mount("/", StaticFiles(directory=str(_webui_dir), html=True), name="webui")
else:  # pragma: no cover - 部署异常提示
    logger.warning("未找到 webui 目录，界面将无法加载（可设置 PDF2ZH_WEBUI_DIR）")

    @app.get("/")
    def _missing_webui() -> JSONResponse:
        return JSONResponse(
            status_code=500,
            content={"detail": "未找到 webui 目录，请设置环境变量 PDF2ZH_WEBUI_DIR"},
        )


# ---------------------------------------------------------------------------
# 启动
# ---------------------------------------------------------------------------
def run_server(port: int = 7860, host: str = "127.0.0.1") -> None:
    import uvicorn

    _config_manager()  # 提前初始化配置
    WORK_DIR.mkdir(parents=True, exist_ok=True)
    print(f"WebUI dir: {_webui_dir}", flush=True)
    print(f"WebUI ready: http://{host}:{port}", flush=True)
    uvicorn.run(app, host=host, port=port, log_level="info")


def main() -> int:
    parser = argparse.ArgumentParser(description="PDFMathTranslate Web UI 服务")
    parser.add_argument("--server-port", "--port", dest="port", type=int, default=7860)
    parser.add_argument("--host", default="127.0.0.1")
    args = parser.parse_args()
    run_server(port=args.port, host=args.host)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
