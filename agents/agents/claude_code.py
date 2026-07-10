"""Claude Code as a gym-anything computer-use agent.

Runs the Claude Code CLI headless inside a throwaway, isolated sandbox
(apptainer or docker; see ``agents/shared/agent_sandbox.py``) that can only
reach the action gateway and the Anthropic API. See
``agents/shared/cli_harness.py`` for the shared machinery.
"""

from __future__ import annotations

import os

from agents.shared.cli_harness import CliHarnessAgent


class ClaudeCodeAgent(CliHarnessAgent):
    sandbox_name = "claude"
    sandbox_install = "npm install -g @anthropic-ai/claude-code"

    def container_env(self) -> dict[str, str]:
        env: dict[str, str] = {
            "ANTHROPIC_API_KEY": os.environ.get("ANTHROPIC_API_KEY", ""),
            # Claude Code needs this to permit bypassPermissions as root in a
            # container, and we disable telemetry egress.
            "IS_SANDBOX": "1",
            "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1",
            "CLAUDE_CONFIG_DIR": "/logs/claude-config",
        }
        base_url = os.environ.get("ANTHROPIC_BASE_URL", "")
        if base_url:
            env["ANTHROPIC_BASE_URL"] = base_url
        if self.model:
            # Strip a provider prefix (harbor-style "anthropic/...") for the
            # official API; keep the full name behind a custom base URL.
            env["ANTHROPIC_MODEL"] = self.model if base_url else self.model.split("/")[-1]
        return env

    def build_cli_command(self) -> str:
        return (
            "mkdir -p $CLAUDE_CONFIG_DIR; "
            'cat /logs/prompt.txt | claude --verbose '
            "--output-format=stream-json "
            "--permission-mode=bypassPermissions "
            "--print"
        )
