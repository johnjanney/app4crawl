"""Central configuration and constants for the App4Crawl FastAPI server.

No hardcoded ports or paths elsewhere in the server: import from here
(PROJECTBRIEF §13). Paths follow the managed layout under ``~/.app4crawl``
(PROJECTBRIEF §3).
"""

from __future__ import annotations

import os
from pathlib import Path

#: Server/application version. Must match ``CHANGELOG.md`` and the Xcode
#: project's ``CFBundleShortVersionString`` (PROJECTBRIEF §11).
APP_VERSION: str = "0.0.1"

#: Loopback host. The server binds only to ``127.0.0.1`` (PROJECTBRIEF §8).
DEFAULT_HOST: str = "127.0.0.1"

#: Default port for standalone development runs. In production the Swift app
#: chooses a dynamic open port and passes it via ``APP4CRAWL_PORT``.
DEFAULT_PORT: int = int(os.environ.get("APP4CRAWL_PORT", "8000"))

#: Root of the App4Crawl managed environment.
APP_HOME: Path = Path(os.environ.get("APP4CRAWL_HOME", Path.home() / ".app4crawl"))

#: Directories within the managed environment.
CONFIG_DIR: Path = APP_HOME / "config"
LOGS_DIR: Path = APP_HOME / "logs"

#: Server log file (rotated). See ``main.configure_logging``.
SERVER_LOG_FILE: Path = LOGS_DIR / "server.log"

#: Log rotation settings.
LOG_MAX_BYTES: int = 5 * 1024 * 1024  # 5 MiB
LOG_BACKUP_COUNT: int = 5


def ensure_directories() -> None:
    """Create the managed config and log directories if they do not exist."""
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    LOGS_DIR.mkdir(parents=True, exist_ok=True)
