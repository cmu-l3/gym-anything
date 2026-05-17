"""SQLAlchemy engine, session factory, and schema bootstrap."""

from __future__ import annotations

from contextlib import contextmanager
from pathlib import Path
from typing import Iterator

from sqlalchemy import create_engine, event, inspect as sa_inspect
from sqlalchemy.engine import Engine
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker

from .config import Settings, get_settings


class Base(DeclarativeBase):
    """Declarative base for all expert-console ORM models."""


_engine: Engine | None = None
_SessionLocal: sessionmaker[Session] | None = None


def _build_engine(settings: Settings) -> Engine:
    url = f"sqlite:///{settings.db_path}"
    engine = create_engine(
        url,
        future=True,
        echo=False,
        connect_args={"check_same_thread": False, "timeout": 30},
    )

    @event.listens_for(engine, "connect")
    def _set_sqlite_pragma(dbapi_connection, _conn_record):  # noqa: ANN001
        cursor = dbapi_connection.cursor()
        cursor.execute("PRAGMA journal_mode=WAL")
        cursor.execute("PRAGMA foreign_keys=ON")
        cursor.execute("PRAGMA synchronous=NORMAL")
        cursor.close()

    return engine


class SchemaMismatchError(RuntimeError):
    """An existing SQLite file has a schema that doesn't match our ORM."""


def _check_schema_compatibility(engine: Engine, db_path: Path) -> None:
    """Verify each existing table contains the columns our ORM expects.

    SQLAlchemy's `create_all` only creates *missing* tables — it won't
    alter an existing table. A stale `state/expert_console.sqlite3`
    from an older build will therefore silently keep the old columns
    and queries against new columns will fail at runtime.

    Fail loud at startup instead, with a clear remediation hint.
    """
    inspector = sa_inspect(engine)
    existing_tables = set(inspector.get_table_names())
    problems: list[str] = []
    for table in Base.metadata.tables.values():
        if table.name not in existing_tables:
            continue
        existing_cols = {col["name"] for col in inspector.get_columns(table.name)}
        expected_cols = {col.name for col in table.columns}
        missing = expected_cols - existing_cols
        if missing:
            problems.append(
                f"  table `{table.name}` is missing columns: {sorted(missing)}"
            )
    if problems:
        joined = "\n".join(problems)
        raise SchemaMismatchError(
            "Existing SQLite database has an outdated schema:\n"
            f"{joined}\n\n"
            f"Delete the stale state and restart:\n"
            f"  rm {db_path} {db_path}-shm {db_path}-wal\n"
        )


def init_db(settings: Settings | None = None) -> Engine:
    """Build the engine and create the schema if it doesn't exist.

    Idempotent — safe to call multiple times. Fails loud if the parent
    state dir is unwritable, or if an existing DB file has a schema
    older than what our ORM expects (see `SchemaMismatchError`).
    """
    global _engine, _SessionLocal
    settings = settings or get_settings()
    settings.state_dir.mkdir(parents=True, exist_ok=True)
    expected_url = f"sqlite:///{settings.db_path}"
    if _engine is not None and str(_engine.url) != expected_url:
        # Settings changed (typical in tests). Dispose the stale engine
        # so we don't leak connections to a deleted temp DB.
        _engine.dispose()
        _engine = None
        _SessionLocal = None
    if _engine is None:
        _engine = _build_engine(settings)
        _SessionLocal = sessionmaker(
            bind=_engine, autoflush=False, autocommit=False, expire_on_commit=False
        )
    # Ensures all model classes have been imported and registered with Base.
    from . import models  # noqa: F401  (import for side effect: metadata)

    _check_schema_compatibility(_engine, Path(str(settings.db_path)))
    Base.metadata.create_all(bind=_engine)
    return _engine


def get_engine() -> Engine:
    if _engine is None:
        return init_db()
    return _engine


def get_sessionmaker() -> sessionmaker[Session]:
    if _SessionLocal is None:
        init_db()
    assert _SessionLocal is not None
    return _SessionLocal


@contextmanager
def session_scope() -> Iterator[Session]:
    """Transactional session — commits on success, rolls back on error."""
    SessionFactory = get_sessionmaker()
    session = SessionFactory()
    try:
        yield session
        session.commit()
    except Exception:
        session.rollback()
        raise
    finally:
        session.close()


def get_db() -> Iterator[Session]:
    """FastAPI dependency. Provides a request-scoped session.

    Commits at the end of the request unless the handler raised.
    """
    SessionFactory = get_sessionmaker()
    session = SessionFactory()
    try:
        yield session
        session.commit()
    except Exception:
        session.rollback()
        raise
    finally:
        session.close()


def reset_engine_for_tests(settings: Settings) -> Engine:
    """Drop the cached engine so tests can rebuild against a fresh DB.

    Tests should pass a Settings pointing at a tmp_path-backed db_path.
    """
    global _engine, _SessionLocal
    if _engine is not None:
        try:
            _engine.dispose()
        except Exception:
            pass
    _engine = None
    _SessionLocal = None
    return init_db(settings)


__all__ = [
    "Base",
    "init_db",
    "get_engine",
    "get_sessionmaker",
    "session_scope",
    "get_db",
    "reset_engine_for_tests",
    "SchemaMismatchError",
]
