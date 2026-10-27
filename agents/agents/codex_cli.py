"""OpenAI Codex CLI as a gym-anything computer-use agent.

Runs the Codex CLI headless inside a throwaway, isolated sandbox (apptainer or
docker; see ``agents/shared/agent_sandbox.py``). The host login file is copied
into the container's private writable filesystem for the run; the host Codex
home is never mounted. See ``agents/shared/cli_harness.py`` for the shared
machinery.
"""

from __future__ import annotations

import json
import os
import shlex
from pathlib import Path

from agents.shared.agent_sandbox import AgentSandbox
from agents.shared.cli_harness import CliHarnessAgent


_CONTAINER_CODEX_HOME = "/gym-agent-private/codex-home"


class CodexCliAgent(CliHarnessAgent):
    sandbox_name = "codex"
    sandbox_install = "npm install -g @openai/codex@0.149.1"

    def _host_auth_path(self) -> Path:
        configured = self.agent_args.get("codex_auth_path")
        if configured:
            return Path(configured).expanduser()
        host_codex_home = Path(
            os.environ.get("CODEX_HOME", str(Path.home() / ".codex"))
        ).expanduser()
        return host_codex_home / "auth.json"

    def container_env(self) -> dict[str, str]:
        return {"CODEX_HOME": _CONTAINER_CODEX_HOME}

    def prepare_sandbox(self, sandbox: AgentSandbox) -> None:
        auth_path = self._host_auth_path()
        if not auth_path.is_file():
            raise RuntimeError(
                f"Codex login file not found at {auth_path}. Run `codex login` on "
                "the host or pass agent_args.codex_auth_path."
            )
        sandbox.copy_file(
            auth_path,
            f"{_CONTAINER_CODEX_HOME}/auth.json",
            mode=0o600,
        )

    def collect_sandbox_artifacts(self, sandbox: AgentSandbox) -> None:
        if not self.agent_args.get("persist_session") or not self.save_path:
            return
        destination = Path(self.save_path) / "cli_harness" / "codex_home" / "sessions"
        sandbox.copy_directory_from(
            f"{_CONTAINER_CODEX_HOME}/sessions",
            destination,
        )
        self._validate_persisted_sessions(destination)

    @staticmethod
    def _validate_persisted_sessions(sessions_dir: Path) -> None:
        session_files = sorted(sessions_dir.rglob("*.jsonl"))
        if not session_files:
            raise RuntimeError("Codex session export contained no JSONL files")
        for session_file in session_files:
            record_count = 0
            with session_file.open("rb") as handle:
                for line_number, line in enumerate(handle, start=1):
                    if b"\0" in line:
                        raise RuntimeError(
                            f"Codex session export contains NUL bytes in "
                            f"{session_file.name}:{line_number}"
                        )
                    if not line.strip():
                        raise RuntimeError(
                            f"Codex session export contains an empty record in "
                            f"{session_file.name}:{line_number}"
                        )
                    try:
                        json.loads(line)
                    except json.JSONDecodeError as exc:
                        raise RuntimeError(
                            f"Codex session export contains invalid JSON in "
                            f"{session_file.name}:{line_number}: {exc}"
                        ) from exc
                    record_count += 1
            if record_count == 0:
                raise RuntimeError(f"Codex session export is empty: {session_file.name}")

    def build_cli_command(self) -> str:
        model_arg = ""
        if self.model:
            model = self.model.split("/")[-1]
            model_arg = f"--model {shlex.quote(model)} "
        reasoning_arg = ""
        reasoning_effort = self.agent_args.get("reasoning_effort")
        if reasoning_effort:
            config = f"model_reasoning_effort={json.dumps(str(reasoning_effort))}"
            reasoning_arg = f"--config {shlex.quote(config)} "
        persistence_arg = "" if self.agent_args.get("persist_session") else "--ephemeral "
        return (
            "codex exec "
            "--dangerously-bypass-approvals-and-sandbox "
            "--skip-git-repo-check "
            f"{persistence_arg}"
            f"{model_arg}"
            f"{reasoning_arg}"
            "--json "
            '-- "$(cat /logs/prompt.txt)"'
        )
