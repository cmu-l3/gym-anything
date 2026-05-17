"""FastAPI application factory for the expert console.

The factory only wires routers and lifecycle hooks. All business logic
lives in `services/` and `api/`. Settings/secret validation runs once,
synchronously, before the app accepts requests (fail loud).
"""

from __future__ import annotations

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .config import Settings, get_settings
from .db import init_db
from .services.dispatch import (
    DispatchService,
    RealSubprocessLauncher,
    SubprocessLauncher,
)
from .services.memory import MemoryService
from .services.preferences import PreferencesService
from .services.vnc import VNCEnvProvider, VNCService


logger = logging.getLogger("expert_console.app")


def _configure_logging() -> None:
    if logging.getLogger().handlers:
        return
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)-7s %(name)s — %(message)s",
    )


def create_app(
    *,
    settings: Settings | None = None,
    skip_runtime_validation: bool = False,
    subprocess_launcher: SubprocessLauncher | None = None,
    vnc_provider: VNCEnvProvider | None = None,
) -> FastAPI:
    """Build the FastAPI app.

    `skip_runtime_validation` is for unit tests that don't have a
    real claude binary or API key available. Production calls leave
    it False so missing prerequisites fail at start.

    `subprocess_launcher` lets tests inject a stub launcher that doesn't
    actually shell out.
    """
    _configure_logging()
    settings = settings or get_settings()
    if not skip_runtime_validation:
        settings.validate_runtime()
    init_db(settings)

    @asynccontextmanager
    async def lifespan(_app: FastAPI):
        logger.info(
            "Expert console starting on %s:%s (db=%s)",
            settings.host,
            settings.port,
            settings.db_path,
        )
        yield
        logger.info("Expert console stopping")

    app = FastAPI(
        title="Gym-Anything Expert Console",
        version="0.1.0",
        lifespan=lifespan,
        docs_url="/api/docs",
        openapi_url="/api/openapi.json",
    )
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origins,
        allow_credentials=False,
        allow_methods=["*"],
        allow_headers=["*"],
    )
    app.state.settings = settings
    app.state.preferences = PreferencesService(settings)
    app.state.dispatcher = DispatchService(
        settings,
        memory_service=MemoryService(settings),
        subprocess_launcher=subprocess_launcher or RealSubprocessLauncher(),
    )
    app.state.vnc = VNCService(settings, provider=vnc_provider)

    from .api import feedback as feedback_api
    from .api import health as health_api
    from .api import memory as memory_api
    from .api import runs as runs_api
    from .api import sessions as sessions_api
    from .api import settings as settings_api
    from .api import software as software_api
    from .api import summarize as summarize_api
    from .api import vnc as vnc_api

    app.include_router(health_api.router)
    app.include_router(software_api.router)
    app.include_router(summarize_api.router)
    app.include_router(memory_api.router)
    app.include_router(sessions_api.router)
    app.include_router(feedback_api.router)
    app.include_router(runs_api.router)
    app.include_router(vnc_api.router)
    app.include_router(settings_api.router)

    return app
