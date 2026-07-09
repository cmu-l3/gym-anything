"""Contract tests for the creation_audit method.

These tests verify the wiring (parser, path resolution, prompt assembly)
without invoking the actual agent CLI.
"""

from __future__ import annotations

import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

REPO_ROOT = Path(__file__).resolve().parents[5]
sys.path.insert(0, str(REPO_ROOT))
sys.path.insert(0, str(REPO_ROOT / "src"))

from extras.research.software_as_env.creation_audit import method as ca  # noqa: E402


class PathResolutionTests(unittest.TestCase):
    def test_packaged_memory_dir_exists_and_has_required_files(self):
        prompts = ca._packaged_memory_dir()
        self.assertTrue(prompts.is_dir(), prompts)
        self.assertTrue((prompts / "audit_prompt.md").is_file())
        self.assertTrue((prompts / "env_creation_notes" / "prompt.md").is_file())
        # The 800-line creation prompt should be substantial
        self.assertGreater(
            (prompts / "env_creation_notes" / "prompt.md").stat().st_size, 5000
        )

    def test_default_workspace_finds_repo_root(self):
        ws = ca._default_workspace()
        self.assertTrue((ws / "src" / "gym_anything").is_dir())


class ParserTests(unittest.TestCase):
    def test_required_args(self):
        parser = ca.build_parser()
        with self.assertRaises(SystemExit):
            parser.parse_args([])

    def test_defaults(self):
        args = ca.build_parser().parse_args(
            ["--software", "Demo", "--env-dir", "demo_env"]
        )
        self.assertEqual(args.software, "Demo")
        self.assertEqual(args.env_dir, "demo_env")
        self.assertEqual(args.backend, "cc")
        self.assertEqual(args.blind_nudges, ca.DEFAULT_BLIND_NUDGES)
        self.assertEqual(args.audit_rounds, ca.DEFAULT_AUDIT_ROUNDS)
        self.assertEqual(args.start_idx, 0)
        self.assertEqual(args.timeout_sec, ca.DEFAULT_TIMEOUT_SEC)

    def test_backend_codex(self):
        args = ca.build_parser().parse_args(
            ["--software", "Demo", "--env-dir", "demo_env", "--backend", "codex"]
        )
        self.assertEqual(args.backend, "codex")


class ResolveBinTests(unittest.TestCase):
    def test_explicit_path_must_exist(self):
        with self.assertRaises(RuntimeError):
            ca._resolve_bin("/no/such/binary", "FAKE_VAR", "fake")

    def test_env_var_used_when_explicit_missing(self):
        with tempfile.NamedTemporaryFile(prefix="claude-", delete=False) as fh:
            fake = Path(fh.name)
        try:
            with mock.patch.dict(os.environ, {"CLAUDE_BIN": str(fake)}):
                resolved = ca._resolve_bin(None, "CLAUDE_BIN", "claude")
            self.assertEqual(resolved, fake)
        finally:
            fake.unlink(missing_ok=True)

    def test_path_lookup_used_when_neither_set(self):
        with tempfile.NamedTemporaryFile(prefix="claude-", delete=False) as fh:
            fake = Path(fh.name)
        try:
            with mock.patch.dict(os.environ, {}, clear=False):
                os.environ.pop("CLAUDE_BIN", None)
                with mock.patch.object(ca.shutil, "which", return_value=str(fake)):
                    resolved = ca._resolve_bin(None, "CLAUDE_BIN", "claude")
            self.assertEqual(resolved, fake)
        finally:
            fake.unlink(missing_ok=True)


class PromptAssemblyTests(unittest.TestCase):
    """Prompts must reference files at their real on-disk path, not at the
    workspace root."""

    def test_initial_prompt_uses_real_creation_path(self):
        prompts = ca._packaged_memory_dir()
        text = ca._initial_prompt("Demo", "demo_env", prompts)
        expected = (prompts / "env_creation_notes" / "prompt.md").as_posix()
        self.assertIn(f"@{expected}", text)
        self.assertIn("Demo", text)
        self.assertIn("demo_env", text)

    def test_audit_run_prompt_uses_real_audit_path(self):
        prompts = ca._packaged_memory_dir()
        with tempfile.TemporaryDirectory() as tmp:
            audits = Path(tmp)
            text = ca._audit_run_prompt("demo_env", audits, prompts)
        self.assertIn(f"@{(prompts / 'audit_prompt.md').as_posix()}", text)
        self.assertIn("demo_env", text)

    def test_nudge_prompt_uses_real_creation_path(self):
        prompts = ca._packaged_memory_dir()
        text = ca._nudge_prompt(prompts)
        expected = (prompts / "env_creation_notes" / "prompt.md").as_posix()
        self.assertIn(f"@{expected}", text)


if __name__ == "__main__":
    unittest.main()
