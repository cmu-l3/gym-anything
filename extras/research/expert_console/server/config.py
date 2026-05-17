"""Expert console runtime configuration.

All paths and required-at-startup secrets resolve here. Anything missing
raises at construction time (fail loud — see feedback_fail_loud rule).
"""

from __future__ import annotations

import os
import shutil
from functools import lru_cache
from pathlib import Path

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


def _detect_repo_root() -> Path:
    """The gym-anything repo root, derived from this file's location.

    Layout: <repo>/extras/research/expert_console/server/config.py
    """
    here = Path(__file__).resolve()
    repo = here.parents[4]
    marker = repo / "src" / "gym_anything" / "__init__.py"
    if not marker.is_file():
        raise RuntimeError(
            f"Could not locate gym-anything repo root from {here}. "
            f"Expected marker at {marker}."
        )
    return repo


class Settings(BaseSettings):
    """Process-wide settings.

    All bools/paths are validated at construction. Required external
    binaries and API keys are checked in `validate()`, which the app
    factory calls before serving the first request.
    """

    model_config = SettingsConfigDict(
        env_prefix="EXPERT_CONSOLE_",
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    # Filesystem ---------------------------------------------------------
    repo_root: Path = Field(default_factory=_detect_repo_root)
    state_dir: Path | None = None
    db_path: Path | None = None
    artifacts_dir: Path | None = None

    # Server -------------------------------------------------------------
    host: str = "127.0.0.1"
    port: int = 8765
    cors_origins: list[str] = Field(default_factory=lambda: ["http://localhost:3456"])

    # Summarization (GPT-5.4 reasoning medium) ---------------------------
    summarize_model: str = "gpt-5.4"
    summarize_reasoning_effort: str = "medium"
    summarize_timeout_sec: int = 120

    # Pipeline dispatch --------------------------------------------------
    claude_bin: str | None = None  # falls back to $CLAUDE_BIN or PATH
    codex_bin: str | None = None
    pipeline_timeout_sec: int = 7200

    # VNC ---------------------------------------------------------------
    vnc_websocket_path: str = "/api/vnc/ws"

    # Frontend ----------------------------------------------------------
    frontend_origin: str = "http://localhost:3456"

    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        if self.state_dir is None:
            self.state_dir = (
                Path(__file__).resolve().parents[1] / "state"
            )
        if self.db_path is None:
            self.db_path = self.state_dir / "expert_console.sqlite3"
        if self.artifacts_dir is None:
            self.artifacts_dir = self.state_dir / "runs"
        self.state_dir.mkdir(parents=True, exist_ok=True)
        self.artifacts_dir.mkdir(parents=True, exist_ok=True)

    # ------------------------------------------------------------------
    # Path helpers
    # ------------------------------------------------------------------

    @property
    def environments_dir(self) -> Path:
        return self.repo_root / "benchmarks" / "cua_world" / "environments"

    @property
    def splits_dir(self) -> Path:
        return self.repo_root / "benchmarks" / "cua_world" / "splits"

    @property
    def creation_audit_memory_dir(self) -> Path:
        return (
            self.repo_root
            / "extras"
            / "research"
            / "software_as_env"
            / "creation_audit"
            / "memory"
        )

    @property
    def propose_amplify_memory_dir(self) -> Path:
        return (
            self.repo_root
            / "extras"
            / "research"
            / "task_generation"
            / "propose_and_amplify"
            / "memory"
        )

    @property
    def expert_feedback_creation_path(self) -> Path:
        return (
            self.creation_audit_memory_dir
            / "env_creation_notes"
            / "expert_feedback.md"
        )

    @property
    def expert_feedback_audit_path(self) -> Path:
        return self.creation_audit_memory_dir / "audit_expert_feedback.md"

    @property
    def expert_feedback_propose_path(self) -> Path:
        return (
            self.propose_amplify_memory_dir
            / "task_creation_notes"
            / "expert_feedback.md"
        )

    @property
    def audit_prompt_path(self) -> Path:
        return self.creation_audit_memory_dir / "audit_prompt.md"

    @property
    def env_creation_prompt_path(self) -> Path:
        return self.creation_audit_memory_dir / "env_creation_notes" / "prompt.md"

    @property
    def audits_dir(self) -> Path:
        return self.repo_root / "audits"

    @property
    def creation_audit_logs_dir(self) -> Path:
        return self.repo_root / "creation_audit_logs"

    def memory_paths_to_watch(self) -> list[Path]:
        """Paths whose `git diff HEAD` we surface as the Memory Diffs panel."""
        return [
            self.creation_audit_memory_dir,
            self.propose_amplify_memory_dir,
        ]

    # ------------------------------------------------------------------
    # Validation — fail loud
    # ------------------------------------------------------------------

    def validate_runtime(self) -> None:
        """Validate required external resources. Call at app startup.

        Raises RuntimeError with a clear message if anything is missing.
        Never returns a partial / fallback state.
        """
        missing: list[str] = []

        if not os.environ.get("OPENAI_API_KEY"):
            missing.append(
                "OPENAI_API_KEY is not set — required for GPT-5.4 "
                "summarization. Export it before starting the console."
            )

        claude_path = (
            self.claude_bin
            or os.environ.get("CLAUDE_BIN")
            or shutil.which("claude")
        )
        if not claude_path:
            missing.append(
                "claude CLI is not on PATH and CLAUDE_BIN is not set. "
                "Install Claude Code and rerun."
            )
        elif not Path(claude_path).is_file():
            missing.append(f"claude binary not found at {claude_path}.")

        if not self.environments_dir.is_dir():
            missing.append(
                f"Environments directory missing: {self.environments_dir}"
            )

        for path in (
            self.expert_feedback_creation_path,
            self.expert_feedback_audit_path,
            self.expert_feedback_propose_path,
        ):
            if not path.is_file():
                missing.append(
                    f"Expert feedback memory file missing: {path}. "
                    f"Run the Stage 1 wiring before serving."
                )

        if missing:
            joined = "\n  - ".join(missing)
            raise RuntimeError(
                "Expert console cannot start. Resolve these issues:\n  - "
                + joined
            )


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings()


__all__ = ["Settings", "get_settings"]
