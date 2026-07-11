"""OpenAI Codex CLI as a gym-anything computer-use agent.

Runs the Codex CLI headless inside a throwaway, isolated sandbox (apptainer or
docker; see ``agents/shared/agent_sandbox.py``) that can only reach the action
gateway and the OpenAI API. See ``agents/shared/cli_harness.py`` for the shared
machinery.
"""

from __future__ import annotations

import os

from agents.shared.cli_harness import CliHarnessAgent


class CodexCliAgent(CliHarnessAgent):
    sandbox_name = "codex"
    sandbox_install = "npm install -g @openai/codex"

    def container_env(self) -> dict[str, str]:
        env: dict[str, str] = {
            "OPENAI_API_KEY": os.environ.get("OPENAI_API_KEY", ""),
        }
        base_url = os.environ.get("OPENAI_BASE_URL", "")
        if base_url:
            env["OPENAI_BASE_URL"] = base_url
        return env

    def build_cli_command(self) -> str:
        model = (self.model or "gpt-5.1").split("/")[-1]
        # Codex authenticates from $CODEX_HOME/auth.json, not the OPENAI_API_KEY
        # env var alone; without it codex falls back to ChatGPT-account mode
        # (gates models and needs a login). Write the API-key auth.json first,
        # into a writable dir under the bound /logs. Codex reads the instruction
        # as a positional arg; feed the rendered prompt file so we don't
        # shell-escape a large multi-line string.
        return (
            "export CODEX_HOME=/logs/codex-home && mkdir -p $CODEX_HOME && "
            'printf \'{"OPENAI_API_KEY": "%s"}\' "$OPENAI_API_KEY" > $CODEX_HOME/auth.json && '
            "codex exec "
            "--dangerously-bypass-approvals-and-sandbox "
            "--skip-git-repo-check "
            f"--model {model} "
            "--json "
            '-- "$(cat /logs/prompt.txt)"'
        )
