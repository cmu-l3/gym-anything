"""Smoke tests for the gym-anything-extras dispatcher."""

from __future__ import annotations

import io
import os
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from unittest import mock

from gym_anything import extras_cli


class FindExtrasRootTests(unittest.TestCase):
    def test_finds_extras_in_repo(self):
        root = extras_cli._find_extras_root()
        self.assertIsNotNone(root)
        self.assertTrue(root.is_dir())
        self.assertTrue((root / "research" / "software_as_env" / "creation_audit").is_dir())

    def test_env_var_override(self):
        with tempfile.TemporaryDirectory() as tmp:
            override = Path(tmp) / "extras"
            override.mkdir()
            with mock.patch.dict(os.environ, {"GYM_ANYTHING_EXTRAS_ROOT": str(override)}):
                resolved = extras_cli._find_extras_root()
            self.assertEqual(resolved, override.resolve())


class DispatchTests(unittest.TestCase):
    def _capture(self, argv):
        buf_out, buf_err = io.StringIO(), io.StringIO()
        with redirect_stdout(buf_out), redirect_stderr(buf_err):
            rc = extras_cli.main(argv)
        return rc, buf_out.getvalue(), buf_err.getvalue()

    def test_help_lists_creation_audit(self):
        rc, out, _ = self._capture(["--help"])
        self.assertEqual(rc, 0)
        self.assertIn("research", out)
        self.assertIn("software_as_env", out)
        self.assertIn("creation_audit", out)

    def test_bare_lists_groups(self):
        rc, out, _ = self._capture([])
        self.assertEqual(rc, 0)
        self.assertIn("research", out)

    def test_unknown_group_returns_2(self):
        rc, _, err = self._capture(["nope"])
        self.assertEqual(rc, 2)
        self.assertIn("Unknown group", err)

    def test_unknown_method_returns_2(self):
        rc, _, err = self._capture(["research", "software_as_env", "no_such_method"])
        self.assertEqual(rc, 2)
        self.assertIn("Unknown method", err)

    def test_method_help_dispatched(self):
        # SystemExit from argparse --help inside method is swallowed.
        rc, out, _ = self._capture(
            ["research", "software_as_env", "creation_audit", "--help"]
        )
        self.assertEqual(rc, 0)
        self.assertIn("--software", out)
        self.assertIn("--env-dir", out)

    def test_download_check_method_help_dispatched(self):
        rc, out, _ = self._capture(
            ["utilities", "benchmark_assets", "download_check", "--help"]
        )
        self.assertEqual(rc, 0)
        self.assertIn("--check-links", out)
        self.assertIn("--download", out)


if __name__ == "__main__":
    unittest.main()
