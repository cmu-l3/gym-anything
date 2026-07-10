"""OpenAI Codex CLI as a gym-anything computer-use agent.

Runs the Codex CLI headless inside a throwaway scratch container that can only
reach the action gateway (and the OpenAI API). See
``agents/shared/cli_harness.py`` for the shared machinery and the containment
model.
"""

from __future__ import annotations

import os

from agents.shared.cli_harness import CliHarnessAgent


class CodexCliAgent(CliHarnessAgent):
    image_tag = "gym-anything-cli-harness-codex:latest"
    install_block = "RUN npm install -g @openai/codex"

    def container_env(self) -> dict[str, str]:
        env: dict[str, str] = {
            "OPENAI_API_KEY": os.environ.get("OPENAI_API_KEY", ""),
        }
        base_url = os.environ.get("OPENAI_BASE_URL", "")
        if base_url:
            env["OPENAI_BASE_URL"] = base_url
        return env

    def build_cli_command(self) -> str:
        model = (self.model or "gpt-5.4").split("/")[-1]
        # Codex reads the instruction as a positional arg; feed the rendered
        # prompt file so we don't shell-escape a large multi-line string.
        return (
            "codex exec "
            "--dangerously-bypass-approvals-and-sandbox "
            "--skip-git-repo-check "
            f"--model {model} "
            "--json "
            '-- "$(cat /logs/prompt.txt)"'
        )
