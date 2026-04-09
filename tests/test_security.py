from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from gym_anything.security import (
    _parse_env_file,
    load_secret_env,
    render_posix_env_prefix,
    wrap_posix_command_with_env,
    wrap_powershell_command_with_env,
)


class ParseEnvFileTests(unittest.TestCase):
    def _write(self, tmp: str, content: str) -> Path:
        p = Path(tmp) / ".env"
        p.write_text(content, encoding="utf-8")
        return p

    def test_parses_simple_key_value(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            p = self._write(tmp, "FOO=bar\n")
            result = _parse_env_file(p)
        self.assertEqual(result, {"FOO": "bar"})

    def test_parses_multiple_pairs(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            p = self._write(tmp, "A=1\nB=2\nC=three\n")
            result = _parse_env_file(p)
        self.assertEqual(result, {"A": "1", "B": "2", "C": "three"})

    def test_skips_blank_lines(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            p = self._write(tmp, "\nFOO=bar\n\n")
            result = _parse_env_file(p)
        self.assertEqual(result, {"FOO": "bar"})

    def test_skips_comment_lines(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            p = self._write(tmp, "# comment\nFOO=bar\n")
            result = _parse_env_file(p)
        self.assertEqual(result, {"FOO": "bar"})

    def test_strips_export_prefix(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            p = self._write(tmp, "export FOO=bar\n")
            result = _parse_env_file(p)
        self.assertEqual(result, {"FOO": "bar"})

    def test_strips_double_quotes(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            p = self._write(tmp, 'FOO="bar baz"\n')
            result = _parse_env_file(p)
        self.assertEqual(result, {"FOO": "bar baz"})

    def test_strips_single_quotes(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            p = self._write(tmp, "FOO='bar baz'\n")
            result = _parse_env_file(p)
        self.assertEqual(result, {"FOO": "bar baz"})

    def test_value_with_equals_sign(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            p = self._write(tmp, "FOO=a=b=c\n")
            result = _parse_env_file(p)
        self.assertEqual(result, {"FOO": "a=b=c"})

    def test_empty_value(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            p = self._write(tmp, "FOO=\n")
            result = _parse_env_file(p)
        self.assertEqual(result, {"FOO": ""})

    def test_raises_on_missing_equals(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            p = self._write(tmp, "NOEQUALS\n")
            with self.assertRaises(ValueError):
                _parse_env_file(p)

    def test_raises_on_empty_key(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            p = self._write(tmp, "=value\n")
            with self.assertRaises(ValueError):
                _parse_env_file(p)

    def test_empty_file_returns_empty_dict(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            p = self._write(tmp, "")
            result = _parse_env_file(p)
        self.assertEqual(result, {})


class LoadSecretEnvTests(unittest.TestCase):
    def test_loads_env_file(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp) / "secrets.env"
            p.write_text("API_KEY=abc123\n", encoding="utf-8")
            result = load_secret_env(str(p))
        self.assertEqual(result, {"API_KEY": "abc123"})

    def test_loads_json_file(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp) / "secrets.json"
            p.write_text(json.dumps({"TOKEN": "xyz", "HOST": "localhost"}), encoding="utf-8")
            result = load_secret_env(str(p))
        self.assertEqual(result, {"TOKEN": "xyz", "HOST": "localhost"})

    def test_resolves_relative_path_with_base_dir(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            (base / "secrets.env").write_text("FOO=bar\n", encoding="utf-8")
            result = load_secret_env("secrets.env", base_dir=base)
        self.assertEqual(result, {"FOO": "bar"})

    def test_raises_file_not_found_for_missing_ref(self) -> None:
        with self.assertRaises(FileNotFoundError):
            load_secret_env("/nonexistent/path/secrets.env")

    def test_raises_on_non_mapping_json(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp) / "bad.json"
            p.write_text(json.dumps(["not", "a", "dict"]), encoding="utf-8")
            with self.assertRaises(ValueError):
                load_secret_env(str(p))

    def test_json_values_coerced_to_str(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp) / "secrets.json"
            p.write_text(json.dumps({"PORT": 8080, "DEBUG": True}), encoding="utf-8")
            result = load_secret_env(str(p))
        self.assertEqual(result["PORT"], "8080")
        self.assertEqual(result["DEBUG"], "True")


class RenderPosixEnvPrefixTests(unittest.TestCase):
    def test_empty_env_returns_empty_string(self) -> None:
        self.assertEqual(render_posix_env_prefix({}), "")

    def test_single_value_no_quoting_needed(self) -> None:
        result = render_posix_env_prefix({"FOO": "bar"})
        self.assertEqual(result, "FOO=bar")

    def test_value_with_spaces_is_quoted(self) -> None:
        result = render_posix_env_prefix({"MSG": "hello world"})
        self.assertIn("MSG=", result)
        self.assertIn("hello world", result)
        # shlex.quote wraps spaces in single quotes
        self.assertIn("'hello world'", result)

    def test_multiple_values_space_separated(self) -> None:
        result = render_posix_env_prefix({"A": "1", "B": "2"})
        self.assertIn("A=1", result)
        self.assertIn("B=2", result)
        # Pairs are joined by a single space
        self.assertRegex(result, r"A=1 B=2|B=2 A=1")

    def test_value_with_special_chars_is_quoted(self) -> None:
        result = render_posix_env_prefix({"X": "a$b"})
        # shlex.quote wraps in single quotes for safety
        self.assertIn("'a$b'", result)


class WrapPosixCommandWithEnvTests(unittest.TestCase):
    def test_empty_env_returns_cmd_unchanged(self) -> None:
        self.assertEqual(wrap_posix_command_with_env("ls -la", {}), "ls -la")

    def test_prepends_env_prefix_by_default(self) -> None:
        result = wrap_posix_command_with_env("myapp", {"KEY": "val"})
        self.assertTrue(result.startswith("env "))
        self.assertIn("myapp", result)
        self.assertIn("KEY=val", result)

    def test_export_mode_uses_export_statements(self) -> None:
        result = wrap_posix_command_with_env("myapp", {"KEY": "val"}, export=True)
        self.assertIn("export KEY=val", result)
        self.assertTrue(result.endswith("; myapp"))

    def test_export_mode_multiple_vars(self) -> None:
        result = wrap_posix_command_with_env("run.sh", {"A": "1", "B": "2"}, export=True)
        self.assertIn("export A=1", result)
        self.assertIn("export B=2", result)
        self.assertTrue(result.endswith("; run.sh"))

    def test_empty_env_export_mode_returns_cmd_unchanged(self) -> None:
        self.assertEqual(wrap_posix_command_with_env("ls", {}, export=True), "ls")


class WrapPowershellCommandWithEnvTests(unittest.TestCase):
    def test_empty_env_returns_cmd_unchanged(self) -> None:
        self.assertEqual(wrap_powershell_command_with_env("myapp.exe", {}), "myapp.exe")

    def test_single_var_prepended(self) -> None:
        result = wrap_powershell_command_with_env("myapp.exe", {"KEY": "val"})
        self.assertIn("$env:KEY='val'", result)
        self.assertTrue(result.endswith("; myapp.exe"))

    def test_multiple_vars_semicolon_separated(self) -> None:
        result = wrap_powershell_command_with_env("run.ps1", {"A": "1", "B": "2"})
        self.assertIn("$env:A='1'", result)
        self.assertIn("$env:B='2'", result)
        self.assertTrue(result.endswith("; run.ps1"))

    def test_single_quotes_in_value_are_escaped(self) -> None:
        # PowerShell escapes ' as ''
        result = wrap_powershell_command_with_env("cmd", {"MSG": "it's here"})
        self.assertIn("$env:MSG='it''s here'", result)

    def test_value_with_spaces(self) -> None:
        result = wrap_powershell_command_with_env("cmd", {"MSG": "hello world"})
        self.assertIn("$env:MSG='hello world'", result)


if __name__ == "__main__":
    unittest.main()
