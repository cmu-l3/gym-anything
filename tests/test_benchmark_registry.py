from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from benchmarks.cua_world.registry import (
    get_tasks_for_environment,
    load_environment_task_splits,
    resolve_environment_dir,
    resolve_environment_key,
)


def _write_json(path: Path, data) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2), encoding="utf-8")


class BenchmarkRegistryTests(unittest.TestCase):
    def test_loader_preserves_explicit_all_tasks_and_additional_splits(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            environments_root = root / "benchmarks" / "cua_world" / "environments"
            splits_root = root / "benchmarks" / "cua_world" / "splits"
            env_dir = environments_root / "demo_env"
            for task_id in ("task_a", "task_b", "task_c"):
                (env_dir / "tasks" / task_id).mkdir(parents=True)

            _write_json(
                splits_root / "demo_split.json",
                {
                    "env_folder": "benchmarks/cua_world/environments/demo_env",
                    "train_tasks": ["task_c"],
                    "test_tasks": ["task_b"],
                    "all_tasks": ["task_a", "task_b", "task_c"],
                    "additional_splits": {"long_horizon": ["task_a"]},
                },
            )
            _write_json(
                splits_root / "verified.json",
                {
                    "by_environment": {"demo_env": ["task_b", "task_c"]},
                },
            )

            raw = load_environment_task_splits(
                surface="raw",
                splits_root=splits_root,
                environments_root=environments_root,
            )
            verified = load_environment_task_splits(
                surface="verified",
                splits_root=splits_root,
                environments_root=environments_root,
            )

            self.assertEqual(raw["demo_env"]["all"], ["task_a", "task_b", "task_c"])
            self.assertEqual(raw["demo_env"]["long_horizon"], ["task_a"])
            self.assertEqual(raw["demo_env"]["verified"], ["task_b", "task_c"])
            self.assertEqual(verified["demo_env"]["all"], ["task_b", "task_c"])
            self.assertEqual(verified["demo_env"]["train"], ["task_c"])
            self.assertEqual(verified["demo_env"]["test"], ["task_b"])

    def test_loader_discovers_missing_split_files_from_environment_dirs(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            environments_root = root / "benchmarks" / "cua_world" / "environments"
            splits_root = root / "benchmarks" / "cua_world" / "splits"
            env_dir = environments_root / "demo_env"
            for task_id in ("task_a", "task_b"):
                (env_dir / "tasks" / task_id).mkdir(parents=True)
            splits_root.mkdir(parents=True)

            registry = load_environment_task_splits(
                surface="raw",
                splits_root=splits_root,
                environments_root=environments_root,
            )

            self.assertEqual(registry["demo_env"]["all"], ["task_a", "task_b"])
            self.assertEqual(registry["demo_env"]["train"], ["task_a", "task_b"])
            self.assertEqual(registry["demo_env"]["test"], [])

    def test_environment_resolution_helpers_accept_keys_and_paths(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            environments_root = root / "benchmarks" / "cua_world" / "environments"
            env_dir = environments_root / "demo_env"
            env_dir.mkdir(parents=True)

            self.assertEqual(resolve_environment_key("demo_env"), "demo_env")
            self.assertEqual(resolve_environment_key(env_dir), "demo_env")
            self.assertEqual(resolve_environment_dir("demo_env", environments_root), env_dir.resolve())
            self.assertEqual(resolve_environment_dir(env_dir, environments_root), env_dir.resolve())

    def test_get_tasks_for_environment_reads_verified_surface(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            environments_root = root / "benchmarks" / "cua_world" / "environments"
            splits_root = root / "benchmarks" / "cua_world" / "splits"
            env_dir = environments_root / "demo_env"
            for task_id in ("task_a", "task_b"):
                (env_dir / "tasks" / task_id).mkdir(parents=True)

            _write_json(
                splits_root / "demo_split.json",
                {
                    "env_folder": "benchmarks/cua_world/environments/demo_env",
                    "train_tasks": ["task_a", "task_b"],
                    "test_tasks": [],
                    "all_tasks": ["task_a", "task_b"],
                },
            )
            _write_json(
                splits_root / "verified.json",
                {
                    "by_environment": {"demo_env": ["task_b"]},
                },
            )

            self.assertEqual(
                get_tasks_for_environment(
                    "demo_env",
                    split="all",
                    surface="verified",
                    splits_root=splits_root,
                    environments_root=environments_root,
                ),
                ["task_b"],
            )


if __name__ == "__main__":
    unittest.main()
