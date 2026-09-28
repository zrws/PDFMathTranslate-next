from pathlib import Path

from pdf2zh_next.config.cli_env_model import CLIEnvSettingsModel
from pdf2zh_next.config.main import ConfigManager
from pdf2zh_next.high_level import _split_glossary_paths


def test_glossary_paths_accept_legacy_delimiters() -> None:
    assert _split_glossary_paths("one.csv,two.csv; three.csv") == [
        "one.csv",
        "two.csv",
        "three.csv",
    ]
    assert _split_glossary_paths(None) == []


def test_config_manager_writes_to_active_config_path(tmp_path: Path) -> None:
    manager = ConfigManager()
    previous = getattr(manager, "_active_config_file_path", None)
    target = tmp_path / "nested" / "custom.toml"
    try:
        manager._active_config_file_path = target
        manager.write_user_default_config_file(CLIEnvSettingsModel())
        assert target.is_file()
        assert not list(target.parent.glob("*.tmp"))
    finally:
        if previous is None:
            manager.__dict__.pop("_active_config_file_path", None)
        else:
            manager._active_config_file_path = previous
