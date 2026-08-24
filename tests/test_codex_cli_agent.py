from __future__ import annotations

import tempfile
import unittest
from pathlib import Path
from unittest import mock

from agents.agents.codex_cli import CodexCliAgent


class _RecordingSandbox:
    def __init__(self) -> None:
        self.copies: list[tuple[Path, str, int]] = []
        self.directory_copies: list[tuple[str, Path]] = []

    def copy_file(self, source: Path, destination: str, mode: int = 0o600) -> None:
        self.copies.append((source, destination, mode))

    def copy_directory_from(self, source: str, destination: Path) -> None:
        self.directory_copies.append((source, destination))
        session_dir = destination / "2026" / "08" / "24"
        session_dir.mkdir(parents=True, exist_ok=True)
        (session_dir / "rollout-test.jsonl").write_text('{"type":"session_meta"}\n')


class CodexAuthenticationTests(unittest.TestCase):
    def test_copies_only_configured_auth_file_to_private_codex_home(self):
        with tempfile.TemporaryDirectory() as tmp:
            auth_path = Path(tmp) / "auth.json"
            auth_path.write_text('{"tokens": {}}')
            sandbox = _RecordingSandbox()
            agent = CodexCliAgent(agent_args={"codex_auth_path": str(auth_path)})

            agent.prepare_sandbox(sandbox)

        self.assertEqual(
            sandbox.copies,
            [(auth_path, "/gym-agent-private/codex-home/auth.json", 0o600)],
        )
        self.assertEqual(
            agent.container_env(),
            {"CODEX_HOME": "/gym-agent-private/codex-home"},
        )

    def test_defaults_to_auth_json_under_host_codex_home(self):
        with tempfile.TemporaryDirectory() as tmp, \
             mock.patch.dict("os.environ", {"CODEX_HOME": tmp}):
            auth_path = Path(tmp) / "auth.json"
            auth_path.write_text('{"tokens": {}}')
            sandbox = _RecordingSandbox()
            CodexCliAgent().prepare_sandbox(sandbox)

        self.assertEqual(sandbox.copies[0][0], auth_path)

    def test_missing_login_file_fails_before_cli_execution(self):
        agent = CodexCliAgent(agent_args={"codex_auth_path": "/does/not/exist/auth.json"})
        with self.assertRaisesRegex(RuntimeError, "codex login"):
            agent.prepare_sandbox(_RecordingSandbox())


class CodexCommandTests(unittest.TestCase):
    def test_uses_ephemeral_account_defaults_without_api_key_or_forced_model(self):
        command = CodexCliAgent().build_cli_command()
        self.assertIn("codex exec", command)
        self.assertIn("--ephemeral", command)
        self.assertNotIn("--model", command)
        self.assertNotIn("OPENAI_API_KEY", command)
        self.assertNotIn("/logs/codex-home", command)

    def test_explicit_model_is_forwarded_without_provider_prefix(self):
        command = CodexCliAgent(agent_args={"model": "openai/gpt-5.4"}).build_cli_command()
        self.assertIn("--model gpt-5.4", command)

    def test_reasoning_effort_is_forwarded_as_codex_config(self):
        command = CodexCliAgent(
            agent_args={"model": "gpt-5.6-terra", "reasoning_effort": "xhigh"}
        ).build_cli_command()
        self.assertIn("--model gpt-5.6-terra", command)
        self.assertIn("model_reasoning_effort=\"xhigh\"", command)

    def test_persistent_session_omits_ephemeral_flag(self):
        command = CodexCliAgent(agent_args={"persist_session": True}).build_cli_command()
        self.assertNotIn("--ephemeral", command)

    def test_persistent_session_exports_only_session_directory(self):
        with tempfile.TemporaryDirectory() as tmp:
            sandbox = _RecordingSandbox()
            agent = CodexCliAgent(agent_args={"persist_session": True})
            agent.save_path = tmp

            agent.collect_sandbox_artifacts(sandbox)

            self.assertEqual(
                sandbox.directory_copies,
                [
                    (
                        "/gym-agent-private/codex-home/sessions",
                        Path(tmp) / "cli_harness" / "codex_home" / "sessions",
                    )
                ],
            )

    def test_persistent_session_rejects_sparse_nul_holes(self):
        with tempfile.TemporaryDirectory() as tmp:
            session = Path(tmp) / "rollout.jsonl"
            session.write_bytes(b'{"type":"session_meta"}\n\0\0\0')

            with self.assertRaisesRegex(RuntimeError, "contains NUL bytes"):
                CodexCliAgent._validate_persisted_sessions(Path(tmp))

    def test_persistent_session_rejects_invalid_json(self):
        with tempfile.TemporaryDirectory() as tmp:
            session = Path(tmp) / "rollout.jsonl"
            session.write_text('{"type":"session_meta"}\n{"truncated":')

            with self.assertRaisesRegex(RuntimeError, "contains invalid JSON"):
                CodexCliAgent._validate_persisted_sessions(Path(tmp))

    def test_cli_version_is_pinned_for_reproducible_image_cache(self):
        self.assertEqual(
            CodexCliAgent.sandbox_install,
            "npm install -g @openai/codex@0.149.1",
        )


if __name__ == "__main__":
    unittest.main()
