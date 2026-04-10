from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from gym_anything.verification.specs import (
    _candidate_source_paths,
    _compose_env_data,
    _extract_script_names,
    _extract_script_refs,
    _mount_value,
    _resolve_mount_path,
    _target_aliases,
    find_env_spec_path,
    find_task_spec_paths,
    verify_env_spec_path,
    verify_task_spec_path,
)


def _write_json(path: Path, data: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data), encoding="utf-8")


_MINIMAL_ENV = {
    "id": "test-env",
    "runner": "local",
    "observation": [{"type": "rgb_screen", "resolution": [640, 480]}],
    "action": [{"type": "mouse"}],
}

_MINIMAL_TASK = {
    "id": "demo",
    "description": "A demo task",
    "success": {"mode": "program", "spec": {"program": "verifier.py::verify"}},
}


class FindEnvSpecPathTests(unittest.TestCase):
    """Tests for find_env_spec_path."""

    def test_finds_yaml(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            yaml_path = root / "env.yaml"
            yaml_path.write_text("id: x\n", encoding="utf-8")
            found = find_env_spec_path(root)
            self.assertEqual(found, yaml_path)

    def test_finds_yml(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            yml_path = root / "env.yml"
            yml_path.write_text("id: x\n", encoding="utf-8")
            found = find_env_spec_path(root)
            self.assertEqual(found, yml_path)

    def test_finds_json(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            json_path = root / "env.json"
            json_path.write_text('{"id":"x"}', encoding="utf-8")
            found = find_env_spec_path(root)
            self.assertEqual(found, json_path)

    def test_prefers_yaml_over_json(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "env.yaml").write_text("id: x\n", encoding="utf-8")
            (root / "env.json").write_text('{"id":"x"}', encoding="utf-8")
            found = find_env_spec_path(root)
            self.assertEqual(found.name, "env.yaml")

    def test_raises_when_missing(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaises(FileNotFoundError):
                find_env_spec_path(Path(tmp))


class FindTaskSpecPathsTests(unittest.TestCase):
    """Tests for find_task_spec_paths."""

    def _setup_tasks(self, root: Path) -> None:
        (root / "tasks" / "task_a").mkdir(parents=True)
        (root / "tasks" / "task_b").mkdir(parents=True)
        (root / "tasks" / "task_a" / "task.json").write_text('{"id":"task_a"}', encoding="utf-8")
        (root / "tasks" / "task_b" / "task.yaml").write_text("id: task_b\n", encoding="utf-8")

    def test_returns_empty_when_no_tasks_dir(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = find_task_spec_paths(Path(tmp))
            self.assertEqual(result, [])

    def test_returns_all_task_specs(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self._setup_tasks(root)
            result = find_task_spec_paths(root)
            names = {p.parent.name for p in result}
            self.assertIn("task_a", names)
            self.assertIn("task_b", names)

    def test_filters_by_task_id(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self._setup_tasks(root)
            result = find_task_spec_paths(root, task_id="task_a")
            self.assertEqual(len(result), 1)
            self.assertEqual(result[0].parent.name, "task_a")

    def test_returns_empty_for_missing_task_id(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self._setup_tasks(root)
            result = find_task_spec_paths(root, task_id="nonexistent")
            self.assertEqual(result, [])


class ExtractScriptNamesTests(unittest.TestCase):
    """Tests for _extract_script_names."""

    def test_extracts_sh_script(self) -> None:
        names = _extract_script_names("/workspace/tasks/demo/setup_task.sh")
        self.assertIn("setup_task.sh", names)

    def test_extracts_ps1_script(self) -> None:
        names = _extract_script_names("powershell -File C:\\tasks\\run.ps1")
        self.assertIn("run.ps1", names)

    def test_extracts_py_script(self) -> None:
        names = _extract_script_names("python verifier.py")
        self.assertIn("verifier.py", names)

    def test_returns_empty_for_none(self) -> None:
        self.assertEqual(_extract_script_names(None), [])

    def test_returns_empty_for_empty_string(self) -> None:
        self.assertEqual(_extract_script_names(""), [])

    def test_returns_empty_for_no_scripts(self) -> None:
        self.assertEqual(_extract_script_names("echo hello world"), [])

    def test_extracts_multiple_scripts(self) -> None:
        names = _extract_script_names("bash setup.sh && python run.py")
        self.assertIn("setup.sh", names)
        self.assertIn("run.py", names)


class ExtractScriptRefsTests(unittest.TestCase):
    """Tests for _extract_script_refs."""

    def test_extracts_full_path_sh(self) -> None:
        refs = _extract_script_refs("/workspace/tasks/demo/setup_task.sh")
        self.assertIn("/workspace/tasks/demo/setup_task.sh", refs)

    def test_extracts_windows_path(self) -> None:
        refs = _extract_script_refs("powershell -File C:\\workspace\\run.ps1")
        self.assertTrue(any("run.ps1" in r for r in refs))

    def test_returns_empty_for_none(self) -> None:
        self.assertEqual(_extract_script_refs(None), [])

    def test_returns_empty_for_no_script(self) -> None:
        self.assertEqual(_extract_script_refs("echo hello"), [])


class TargetAliasesTests(unittest.TestCase):
    """Tests for _target_aliases."""

    def test_empty_target_returns_empty(self) -> None:
        self.assertEqual(_target_aliases(""), [])

    def test_unix_path_adds_windows_alias(self) -> None:
        aliases = _target_aliases("/workspace/tasks")
        self.assertIn("/workspace/tasks", aliases)
        self.assertIn("C:/workspace/tasks", aliases)

    def test_windows_path_adds_unix_alias(self) -> None:
        aliases = _target_aliases("C:/workspace/tasks")
        self.assertIn("C:/workspace/tasks", aliases)
        self.assertIn("/workspace/tasks", aliases)

    def test_trailing_slash_stripped(self) -> None:
        aliases = _target_aliases("/workspace/tasks/")
        for alias in aliases:
            self.assertFalse(alias.endswith("/"))

    def test_backslash_normalized(self) -> None:
        aliases = _target_aliases("C:\\workspace\\tasks")
        # Should be normalized to forward slashes
        for alias in aliases:
            self.assertNotIn("\\", alias)

    def test_sorted_longest_first(self) -> None:
        aliases = _target_aliases("/workspace")
        # Longer aliases should come first (sorted by len, reverse=True)
        for i in range(len(aliases) - 1):
            self.assertGreaterEqual(len(aliases[i]), len(aliases[i + 1]))


class MountValueTests(unittest.TestCase):
    """Tests for _mount_value."""

    def test_reads_from_dict(self) -> None:
        mount = {"source": "scripts", "target": "/workspace/scripts"}
        self.assertEqual(_mount_value(mount, "source"), "scripts")
        self.assertEqual(_mount_value(mount, "target"), "/workspace/scripts")

    def test_missing_key_returns_empty_string(self) -> None:
        self.assertEqual(_mount_value({}, "source"), "")

    def test_reads_from_object(self) -> None:
        class Mount:
            source = "data"
            target = "/mnt/data"

        self.assertEqual(_mount_value(Mount(), "source"), "data")
        self.assertEqual(_mount_value(Mount(), "target"), "/mnt/data")


class ResolveMountPathTests(unittest.TestCase):
    """Tests for _resolve_mount_path."""

    def test_resolves_simple_mount(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            env_root = Path(tmp)
            scripts = env_root / "scripts"
            scripts.mkdir()
            (scripts / "boot.sh").write_text("#!/bin/sh\n", encoding="utf-8")
            mount = {"source": "scripts", "target": "/sdcard/scripts"}
            result = _resolve_mount_path("/sdcard/scripts/boot.sh", env_root, [mount])
            self.assertIsNotNone(result)

    def test_returns_none_when_no_mounts(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = _resolve_mount_path("/workspace/tasks/setup.sh", Path(tmp), [])
            self.assertIsNone(result)

    def test_returns_none_when_no_match(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            env_root = Path(tmp)
            mount = {"source": "scripts", "target": "/other/path"}
            result = _resolve_mount_path("/workspace/tasks/setup.sh", env_root, [mount])
            self.assertIsNone(result)


class VerifyEnvSpecPathTests(unittest.TestCase):
    """Tests for verify_env_spec_path."""

    def test_valid_env_spec_returns_ok_record(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            env_path = Path(tmp) / "env.json"
            _write_json(env_path, _MINIMAL_ENV)
            record = verify_env_spec_path(env_path)
            self.assertTrue(record.ok)
            self.assertEqual(record.spec_id, "test-env")

    def test_parse_error_returns_error_record(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            env_path = Path(tmp) / "env.json"
            env_path.write_text("{ invalid json }", encoding="utf-8")
            record = verify_env_spec_path(env_path)
            self.assertFalse(record.ok)
            codes = [i.code for i in record.issues]
            self.assertIn("parse_error", codes)

    def test_invalid_env_spec_returns_validation_error(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            env_path = Path(tmp) / "env.json"
            _write_json(env_path, {"id": "bad-env", "runner": "local"})
            record = verify_env_spec_path(env_path)
            self.assertFalse(record.ok)

    def test_missing_hook_script_flagged(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            env_dir = Path(tmp)
            env_data = dict(_MINIMAL_ENV)
            env_data["hooks"] = {"post_start": "/workspace/scripts/nonexistent.sh"}
            _write_json(env_dir / "env.json", env_data)
            record = verify_env_spec_path(env_dir / "env.json")
            codes = [i.code for i in record.issues]
            self.assertIn("missing_hook_reference", codes)

    def test_existing_hook_script_ok(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            env_dir = Path(tmp)
            scripts = env_dir / "scripts"
            scripts.mkdir()
            (scripts / "boot.sh").write_text("#!/bin/sh\n", encoding="utf-8")
            env_data = dict(_MINIMAL_ENV)
            env_data["hooks"] = {"post_start": "sh scripts/boot.sh"}
            _write_json(env_dir / "env.json", env_data)
            record = verify_env_spec_path(env_dir / "env.json")
            self.assertTrue(record.ok)


class VerifyTaskSpecPathTests(unittest.TestCase):
    """Tests for verify_task_spec_path."""

    def _write_verifier(self, task_dir: Path) -> None:
        (task_dir / "verifier.py").write_text(
            "def verify(traj, env_info, task_info):\n    return {'passed': True, 'score': 100}\n",
            encoding="utf-8",
        )

    def test_valid_task_returns_ok_record(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            task_dir = Path(tmp)
            self._write_verifier(task_dir)
            task_path = task_dir / "task.json"
            _write_json(task_path, _MINIMAL_TASK)
            record = verify_task_spec_path(task_path)
            self.assertTrue(record.ok)
            self.assertEqual(record.spec_id, "demo")

    def test_parse_error_returns_error_record(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            task_path = Path(tmp) / "task.json"
            task_path.write_text("{ bad json }", encoding="utf-8")
            record = verify_task_spec_path(task_path)
            self.assertFalse(record.ok)
            codes = [i.code for i in record.issues]
            self.assertIn("parse_error", codes)

    def test_image_match_mode_with_missing_target_flagged(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            task_dir = Path(tmp)
            task_path = task_dir / "task.json"
            _write_json(
                task_path,
                {
                    "id": "img-task",
                    "success": {
                        "mode": "image_match",
                        "spec": {"target": "reference.png"},
                    },
                },
            )
            record = verify_task_spec_path(task_path)
            self.assertFalse(record.ok)
            codes = [i.code for i in record.issues]
            self.assertIn("missing_image_target", codes)

    def test_image_match_mode_with_existing_target_ok(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            task_dir = Path(tmp)
            ref = task_dir / "reference.png"
            ref.write_bytes(b"\x89PNG\r\n")
            task_path = task_dir / "task.json"
            _write_json(
                task_path,
                {
                    "id": "img-task",
                    "success": {
                        "mode": "image_match",
                        "spec": {"target": "reference.png"},
                    },
                },
            )
            record = verify_task_spec_path(task_path)
            # No missing_image_target issue
            codes = [i.code for i in record.issues]
            self.assertNotIn("missing_image_target", codes)

    def test_program_mode_missing_verifier_file_flagged(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            task_dir = Path(tmp)
            task_path = task_dir / "task.json"
            _write_json(task_path, _MINIMAL_TASK)
            # No verifier.py created
            record = verify_task_spec_path(task_path)
            self.assertFalse(record.ok)
            codes = [i.code for i in record.issues]
            self.assertIn("invalid_program_verifier", codes)

    def test_program_mode_missing_function_flagged(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            task_dir = Path(tmp)
            (task_dir / "verifier.py").write_text("def wrong_name(): pass\n", encoding="utf-8")
            task_path = task_dir / "task.json"
            _write_json(task_path, _MINIMAL_TASK)
            record = verify_task_spec_path(task_path)
            self.assertFalse(record.ok)
            codes = [i.code for i in record.issues]
            self.assertIn("invalid_program_verifier", codes)

    def test_missing_program_verifier_target_flagged(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            task_dir = Path(tmp)
            task_path = task_dir / "task.json"
            _write_json(
                task_path,
                {
                    "id": "demo",
                    "success": {"mode": "program", "spec": {}},
                },
            )
            record = verify_task_spec_path(task_path)
            self.assertFalse(record.ok)
            codes = [i.code for i in record.issues]
            self.assertIn("missing_program_verifier", codes)


if __name__ == "__main__":
    unittest.main()
