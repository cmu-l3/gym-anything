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

    def test_disk_split_lists_all_task_folders_ignoring_split_file(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            environments_root = root / "benchmarks" / "cua_world" / "environments"
            splits_root = root / "benchmarks" / "cua_world" / "splits"
            env_dir = environments_root / "demo_env"
            # task_orphan exists on disk but is listed in no split.
            for task_id in ("task_a", "task_b", "task_orphan"):
                (env_dir / "tasks" / task_id).mkdir(parents=True)

            _write_json(
                splits_root / "demo_split.json",
                {
                    "env_folder": "benchmarks/cua_world/environments/demo_env",
                    "train_tasks": ["task_a"],
                    "test_tasks": ["task_b"],
                },
            )
            _write_json(
                splits_root / "verified.json",
                {"by_environment": {"demo_env": ["task_a"]}},
            )

            for surface in ("raw", "verified"):
                self.assertEqual(
                    get_tasks_for_environment(
                        "demo_env",
                        split="disk",
                        surface=surface,
                        splits_root=splits_root,
                        environments_root=environments_root,
                    ),
                    ["task_a", "task_b", "task_orphan"],
                    msg=f"disk split should be surface-independent (surface={surface})",
                )

            # 'all' stays curated: union of train+test, no orphan.
            self.assertEqual(
                get_tasks_for_environment(
                    "demo_env",
                    split="all",
                    surface="raw",
                    splits_root=splits_root,
                    environments_root=environments_root,
                ),
                ["task_a", "task_b"],
            )

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


class CoreRegistryContractTests(unittest.TestCase):
    """The benchmark layout contract in core (gym_anything.registry)."""

    def test_resolve_benchmark_root_by_path_and_package(self) -> None:
        from gym_anything.registry import resolve_benchmark_root

        by_name = resolve_benchmark_root("cua_world")
        self.assertTrue((by_name / "environments").is_dir())
        self.assertEqual(resolve_benchmark_root(by_name), by_name)
        with self.assertRaises(ValueError):
            resolve_benchmark_root("not_a_benchmark_anywhere")

    def test_list_environments_from_a_bare_root(self) -> None:
        from gym_anything.registry import get_tasks_for_environment, list_environments

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for env, tasks in {"b_env": ["t1"], "a_env": ["t2", "t3"], "empty_env": []}.items():
                for task in tasks:
                    (root / "environments" / env / "tasks" / task).mkdir(parents=True)
                (root / "environments" / env).mkdir(parents=True, exist_ok=True)
            self.assertEqual(list_environments(root), ["a_env", "b_env"])
            self.assertEqual(get_tasks_for_environment("a_env", root), ["t2", "t3"])

    def test_task_digest_ignores_python_bytecode_caches(self) -> None:
        from gym_anything.registry import compute_task_digest

        with tempfile.TemporaryDirectory() as tmp:
            env_dir = Path(tmp) / "demo_env"
            task_dir = env_dir / "tasks" / "task_a"
            _write_json(task_dir / "task.json", {"instruction": "Do the task"})
            (task_dir / "verifier.py").write_text("VALUE = 1\n", encoding="utf-8")
            original = compute_task_digest(env_dir, "task_a")

            cache_dir = task_dir / "__pycache__"
            cache_dir.mkdir()
            (cache_dir / "verifier.cpython-312.pyc").write_bytes(b"runtime bytecode")
            (task_dir / "stray.pyc").write_bytes(b"runtime bytecode")
            self.assertEqual(compute_task_digest(env_dir, "task_a"), original)

            (task_dir / "verifier.py").write_text("VALUE = 2\n", encoding="utf-8")
            self.assertNotEqual(compute_task_digest(env_dir, "task_a"), original)

    def test_cua_world_registry_is_a_thin_binding(self) -> None:
        # The wrapper and core must agree on the real corpus.
        from benchmarks.cua_world.registry import DEFAULT_ENVIRONMENTS_ROOT, DEFAULT_SPLITS_ROOT
        from gym_anything.registry import load_environment_task_splits as core_splits

        wrapped = load_environment_task_splits(surface="raw")
        direct = core_splits(
            splits_root=DEFAULT_SPLITS_ROOT, environments_root=DEFAULT_ENVIRONMENTS_ROOT
        )
        self.assertEqual(wrapped, direct)


if __name__ == "__main__":
    unittest.main()
