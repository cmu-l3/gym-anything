"""The publishable Harbor adapter package (extras/hubs/harbor/cua_world).

Covers the adapter's task generation against the real benchmark content and
guards the wiring strings against drift from the integrations compiler
(``gym_anything.integrations.harbor.compile``), which remains the internal
dev tool emitting the same runtime contract.
"""

from __future__ import annotations

import json
import stat
import sys
import tempfile
import tomllib
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
ADAPTER_SRC = REPO_ROOT / "extras" / "hubs" / "harbor" / "cua_world" / "src"
sys.path.insert(0, str(ADAPTER_SRC))

from cua_world.adapter import PARITY_TASK_NAMES, CuaWorldAdapter  # noqa: E402


class AdapterEnumerationTests(unittest.TestCase):
    def test_long_split_enumerates_the_full_benchmark(self) -> None:
        adapter = CuaWorldAdapter(Path("/nonexistent"))
        pairs = adapter.iter_tasks()
        self.assertGreaterEqual(len(pairs), 200, "CUA-World-Long is ~201 tasks")
        names = [f"{env}__{tid}" for env, tid in pairs]
        self.assertEqual(len(names), len(set(names)), "task names must be unique")

    def test_limit_and_task_ids_filters(self) -> None:
        adapter = CuaWorldAdapter(Path("/nonexistent"), limit=3)
        self.assertEqual(len(adapter.iter_tasks()), 3)

        env, tid = CuaWorldAdapter(Path("/nonexistent"), limit=1).iter_tasks()[0]
        picked = CuaWorldAdapter(
            Path("/nonexistent"), task_ids=[f"{env}__{tid}"]
        ).iter_tasks()
        self.assertEqual(picked, [(env, tid)])

    def test_parity_split_fails_loudly_until_defined(self) -> None:
        self.assertEqual(PARITY_TASK_NAMES, [])
        adapter = CuaWorldAdapter(Path("/nonexistent"), split="parity")
        with self.assertRaises(SystemExit):
            adapter.iter_tasks()


class AdapterGenerationTests(unittest.TestCase):
    def _generate_one(self, tmp: Path) -> Path:
        adapter = CuaWorldAdapter(tmp, limit=1, overwrite=True)
        return adapter.run()[0]

    def test_generated_task_matches_the_harbor_shape(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            out = self._generate_one(Path(tmp))
            for rel in (
                "task.toml",
                "instruction.md",
                "environment/Dockerfile",
                "environment/docker-compose.yaml",
                "environment/gym-anything.json",
                "solution/solve.sh",
                "tests/test.sh",
            ):
                self.assertTrue((out / rel).is_file(), rel)
            for script in ("solution/solve.sh", "tests/test.sh"):
                self.assertTrue((out / script).stat().st_mode & stat.S_IXUSR, script)

            config = tomllib.loads((out / "task.toml").read_text())
            self.assertEqual(config["schema_version"], "1.0")
            self.assertTrue(config["task"]["name"].startswith("cua-world/"))
            self.assertNotIn("__TASK_NAME__", config["task"]["name"], "no unsubstituted markers")
            self.assertEqual(config["agent"]["timeout_sec"], 21600.0)
            self.assertEqual(config["metadata"]["max_steps"], 500)

            ga = json.loads((out / "environment" / "gym-anything.json").read_text())
            self.assertEqual(ga["benchmark"], "cua_world")
            self.assertEqual(ga["verifier"]["mode"], "vlm_checklist")
            self.assertEqual(ga["verifier"]["vlm_api_key_var"], "GEMINI_API_KEY")
            self.assertIn(
                'GEMINI_API_KEY = "${GEMINI_API_KEY:-}"', (out / "task.toml").read_text()
            )
            self.assertEqual(
                out.name, f"{ga['env_name']}__{ga['task_id']}", "id mapping preserved"
            )

            instruction = (out / "instruction.md").read_text().strip()
            self.assertTrue(instruction and "__" not in instruction)

    def test_no_marker_survives_anywhere(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            out = self._generate_one(Path(tmp))
            for path in out.rglob("*"):
                if path.is_file() and path.suffix != ".md":
                    self.assertNotIn(
                        "__TASK_", path.read_text(), f"unsubstituted marker in {path}"
                    )

    def test_wiring_matches_the_integrations_compiler(self) -> None:
        """Drift guard: the adapter templates and the internal compiler must
        emit the same runtime contract (entrypoint module, finalize command,
        cache volume, port, KVM device)."""
        from gym_anything.integrations.harbor.compile import compile_task

        with tempfile.TemporaryDirectory() as tmp:
            adapter_out = self._generate_one(Path(tmp) / "adapter")
            ga = json.loads((adapter_out / "environment" / "gym-anything.json").read_text())
            compiler_out = compile_task(
                ga["env_name"], ga["task_id"], Path(tmp) / "compiler"
            )

            for marker in (
                "gym_anything.integrations.harbor.container",
                "harbor-gym-anything-cache",
                "GA_HARBOR_PORT=7317",
                "GA_HARBOR_RUNNER=qemu",
            ):
                self.assertIn(
                    marker, (adapter_out / "environment" / "Dockerfile").read_text()
                    + (adapter_out / "environment" / "docker-compose.yaml").read_text(),
                    marker,
                )
            adapter_test = (adapter_out / "tests" / "test.sh").read_text()
            compiler_test = (compiler_out / "tests" / "test.sh").read_text()
            self.assertEqual(adapter_test, compiler_test, "test.sh drifted")

            adapter_ga = json.loads(
                (adapter_out / "environment" / "gym-anything.json").read_text()
            )
            compiler_ga = json.loads(
                (compiler_out / "environment" / "gym-anything.json").read_text()
            )
            self.assertEqual(adapter_ga, compiler_ga, "boot config drifted")


if __name__ == "__main__":
    unittest.main()
