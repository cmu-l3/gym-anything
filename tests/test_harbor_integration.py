"""Harbor integration: task compilation and the environment backend contract.

The compiler tests run everywhere (the module imports only the registry).
Backend tests need the ``harbor`` package and skip where it is not installed,
mirroring how the verifiers-adapter tests gate on ``verifiers``.
"""

from __future__ import annotations

import json
import os
import stat
import tempfile
import tomllib
import unittest
from pathlib import Path

from gym_anything.integrations.harbor_compile import compile_environment, compile_task

try:
    import harbor  # noqa: F401

    HAS_HARBOR = True
except ImportError:
    HAS_HARBOR = False

REPO_ROOT = Path(__file__).resolve().parents[1]
GIMP_ENV_DIR = REPO_ROOT / "benchmarks" / "cua_world" / "environments" / "gimp_env_all_fast"


class HarborCompileTests(unittest.TestCase):
    def _compile_add_border(self, out_root: Path) -> Path:
        return compile_task(
            "gimp_env_all_fast",
            "add_border",
            out_root,
            env_dir=GIMP_ENV_DIR,
        )

    def test_compiled_task_has_the_harbor_shape(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            out_dir = self._compile_add_border(Path(tmp))

            self.assertEqual(out_dir.name, "gimp_env_all_fast__add_border")
            self.assertTrue((out_dir / "instruction.md").is_file())
            self.assertTrue((out_dir / "task.toml").is_file())
            self.assertTrue((out_dir / "environment" / "gym-anything.json").is_file())
            test_path = out_dir / "tests" / "test.sh"
            self.assertTrue(test_path.is_file())
            self.assertTrue(test_path.stat().st_mode & stat.S_IXUSR, "test.sh must be executable")

            instruction = (out_dir / "instruction.md").read_text()
            self.assertIn("border", instruction.lower())

    def test_task_toml_parses_and_carries_identity(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            out_dir = self._compile_add_border(Path(tmp))
            config = tomllib.loads((out_dir / "task.toml").read_text())

        self.assertEqual(config["schema_version"], "1.3")
        self.assertEqual(config["task"]["name"], "cua-world/gimp_env_all_fast__add_border")
        self.assertEqual(config["metadata"]["gym_anything"]["env_name"], "gimp_env_all_fast")
        self.assertEqual(config["metadata"]["gym_anything"]["task_id"], "add_border")
        self.assertGreaterEqual(config["environment"]["build_timeout_sec"], 600)
        self.assertIn("timeout_sec", config["agent"])
        self.assertIn("timeout_sec", config["verifier"])

    def test_boot_config_matches_the_backend_contract(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            out_dir = self._compile_add_border(Path(tmp))
            ga = json.loads((out_dir / "environment" / "gym-anything.json").read_text())

        self.assertEqual(ga["benchmark"], "cua_world")
        self.assertEqual(ga["env_name"], "gimp_env_all_fast")
        self.assertEqual(ga["task_id"], "add_border")
        self.assertEqual(ga["cache_level"], "post_start")
        self.assertTrue(ga["use_cache"])
        self.assertEqual(ga["seed"], 0)

    def test_compile_environment_covers_selected_tasks(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            out_dirs = compile_environment(
                "gimp_env_all_fast",
                tmp,
                task_ids=["add_border"],
                env_dir=GIMP_ENV_DIR,
            )
        self.assertEqual(len(out_dirs), 1)
        self.assertEqual(out_dirs[0].name, "gimp_env_all_fast__add_border")


@unittest.skipUnless(HAS_HARBOR, "harbor not installed")
class HarborBackendTests(unittest.TestCase):
    def test_verifier_invocation_discrimination(self) -> None:
        """The exec intercept fires for the Verifier's test-script run and for
        nothing else Harbor execs around it (chmod, agent commands)."""
        from gym_anything.integrations.harbor import _is_verifier_invocation

        self.assertTrue(
            _is_verifier_invocation(
                "bash /tests/test.sh > /logs/verifier/test-stdout.txt 2>&1"
            )
        )
        self.assertFalse(_is_verifier_invocation("chmod +x '/tests/test.sh'"))
        self.assertFalse(_is_verifier_invocation("xdotool click 1"))
        self.assertFalse(_is_verifier_invocation("cat /logs/verifier/reward.json"))

    def test_backend_is_loadable_by_import_path(self) -> None:
        """Harbor loads custom environments via ``module:Class`` import paths;
        the class must be importable and subclass BaseEnvironment."""
        from harbor.environments.base import BaseEnvironment

        from gym_anything.integrations.harbor import GymAnythingEnvironment

        self.assertTrue(issubclass(GymAnythingEnvironment, BaseEnvironment))
        self.assertEqual(GymAnythingEnvironment.type(), "gym-anything")


if __name__ == "__main__":
    unittest.main()
