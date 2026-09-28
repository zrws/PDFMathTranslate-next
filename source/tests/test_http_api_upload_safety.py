import asyncio
from io import BytesIO

import pytest
from fastapi import HTTPException
from starlette.datastructures import UploadFile


def _api():
    import pdf2zh_next.http_api as http_api

    return http_api


def test_uploaded_file_ids_cannot_escape_upload_directory(monkeypatch, tmp_path):
    api = _api()
    monkeypatch.setattr(api, "UPLOAD_DIR", tmp_path / "uploads")

    with pytest.raises(HTTPException) as exc_info:
        api._resolve_uploaded_file("..\\private.pdf")

    assert exc_info.value.status_code == 404


def test_upload_rejects_non_pdf_content_and_removes_partial_file(monkeypatch, tmp_path):
    api = _api()
    upload_dir = tmp_path / "uploads"
    monkeypatch.setattr(api, "UPLOAD_DIR", upload_dir)
    upload = UploadFile(filename="not-a-pdf.pdf", file=BytesIO(b"not a PDF"))

    with pytest.raises(HTTPException) as exc_info:
        asyncio.run(api.api_upload_file(upload))

    assert exc_info.value.status_code == 400
    assert not list(upload_dir.glob("*"))


def test_upload_rejects_oversized_file_and_removes_partial_file(monkeypatch, tmp_path):
    api = _api()
    upload_dir = tmp_path / "uploads"
    monkeypatch.setattr(api, "UPLOAD_DIR", upload_dir)
    monkeypatch.setattr(api, "MAX_UPLOAD_BYTES", 3)
    upload = UploadFile(filename="large.pdf", file=BytesIO(b"1234"))

    with pytest.raises(HTTPException) as exc_info:
        asyncio.run(api.api_upload_file(upload))

    assert exc_info.value.status_code == 413
    assert not list(upload_dir.glob("*"))
