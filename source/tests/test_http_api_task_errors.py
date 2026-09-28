from pdf2zh_next.http_api import _friendly_task_error


def test_provider_server_error_is_actionable_and_localized():
    message = _friendly_task_error(
        "Translation subprocess initialization error: RetryError[HTTPStatusError]",
        "httpx.HTTPStatusError: Server error '500 Internal Server Error'",
    )

    assert message == (
        "翻译服务暂时不可用（HTTP 500）。请稍后重试；如果持续发生，请在设置中更换翻译服务。"
    )


def test_provider_auth_error_suggests_checking_credentials():
    message = _friendly_task_error(
        "HTTPStatusError: Client error '401 Unauthorized'",
    )

    assert "HTTP 401" in message
    assert "API Key" in message


def test_retry_error_without_http_status_is_actionable():
    message = _friendly_task_error("RetryError: request timed out")

    assert "多次重试" in message
    assert "检查网络" in message


def test_rate_limit_error_reports_busy_service():
    message = _friendly_task_error("HTTPStatusError: 429 Too Many Requests")

    assert "请求过多" in message
    assert "稍后重试" in message
