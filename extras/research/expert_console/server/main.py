"""uvicorn entry point for the expert console.

Run directly:
    python -m extras.research.expert_console.server.main

Or via the dispatched method:
    gym-anything-extras research expert_console serve
"""

from __future__ import annotations

import logging

import uvicorn

from .app import create_app
from .config import get_settings


logger = logging.getLogger("expert_console.main")


def serve() -> int:
    settings = get_settings()
    app = create_app(settings=settings)
    uvicorn.run(
        app,
        host=settings.host,
        port=settings.port,
        log_level="info",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(serve())
