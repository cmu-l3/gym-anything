"""The stranger test: a synthetic third-party exercises the public door.

A toy world with an alien clock and alien modalities (no screen capture, no
shell), a toy benchmark folder, and a toy program verifier — none known to
core — run a full local episode wired only through public mechanisms:
locator references, the runner registry, `EnvSpec.runner_options`, and the
benchmark-layout contract. If the stranger passes, any downstream passes.

Enforces the design laws (docs/design/modularity.md): L1 one door, L2
forward-don't-interpret, L3 context symmetry, L4 queried capabilities.
"""

from __future__ import annotations

import importlib
import json
import sys
import time
import unittest
from dataclasses import asdict
from pathlib import Path
from tempfile import TemporaryDirectory

from gym_anything.api import from_config, make
from gym_anything.config.validators import validate_env_spec
from gym_anything.runtime.runners import registry as runner_registry
from gym_anything.runtime.runners.base import BaseRunner
from gym_anything.specs import EnvSpec

STRANGER_LOCATOR = "tests.test_stranger_party:StrangerRunner"


class StrangerRunner(BaseRunner):
    """A world core knows nothing about: sim-stepped clock, no shell,
    telemetry + frame-sequence observations."""

    def __init__(self, spec):
        super().__init__(spec)
        self._ticks = 0
        self._context = None

    # --- class-level facts (L1/L4) ---

    @classmethod
    def validate_options(cls, spec):
        allowed = {"tick_hz"}
        return [
            f"unknown runner_options key: {key!r}"
            for key in spec.runner_options
            if key not in allowed
        ]

    @classmethod
    def doctor_status(cls):
        return {"available": True, "reason": None,
                "deps": {"stranger-engine": {"installed": True, "path": None}}}

    # --- episode participation (L3) ---

    def on_episode_start(self, context):
        self._ticks = 0
        self._context = dict(context)
        self._write_manifest()

    def _write_manifest(self):
        if not self._context:
            return
        manifest = Path(self._context["episode_dir"]) / "stranger_manifest.json"
        manifest.write_text(json.dumps(
            {"task_id": self._context.get("task_id"), "ticks": self._ticks}
        ))

    # --- required world surface ---

    def start(self, seed=None):
        self.booted = True

    def stop(self):
        self.booted = False

    def run_reset(self, reset_script, seed=None):
        raise AssertionError("this world has no shell")

    def run_task_init(self, init_script):
        raise AssertionError("this world has no shell")

    def inject_action(self, action):
        if action.get("action") == "wait":
            # Sim time, not wall time: the world owns its clock (L2).
            self._ticks += int(action.get("time", 1))
        else:
            self._ticks += 1
        self._write_manifest()

    def capture_observation(self):
        return {
            "telemetry": {"ticks": self._ticks, "position": [1.0, 2.0, 0.5]},
            "frames": [{"png_b64": "not-really-a-png", "tick": self._ticks}],
        }

    # --- queried capabilities (L4) ---

    def acks_input_delivery(self):
        return True

    def supports_time_control(self):
        return True


class StrangerAgent:
    """Minimal policy for locator resolution; not registered anywhere."""

    def __init__(self, agent_args=None, verbose=False, debug=False):
        self.done = False


_VERIFIER = '''\
import json
from pathlib import Path


def verify(traj, env_info, task_info):
    episode_dir = Path(traj["episode_dir"])
    manifest = episode_dir / "stranger_manifest.json"
    if not manifest.exists():
        return {"passed": False, "score": 0,
                "feedback": "world never received episode context"}
    data = json.loads(manifest.read_text())
    ok = data.get("task_id") == task_info["task_id"] and data.get("ticks", 0) >= 5
    return {"passed": bool(ok), "score": 100 if ok else 0,
            "feedback": f"ticks={data.get('ticks')}"}
'''


def build_stranger_benchmark(root: Path, episodes_dir: Path) -> Path:
    """A benchmark-layout-contract folder for a world core has never met."""
    env_dir = root / "environments" / "stranger_env"
    task_dir = env_dir / "tasks" / "deliver_t1"
    task_dir.mkdir(parents=True)
    (root / "splits").mkdir()

    (env_dir / "env.json").write_text(json.dumps({
        "id": "stranger_env",
        "runner": STRANGER_LOCATOR,
        "observation": [{"type": "rgb_screen"}, {"type": "telemetry"}],
        "action": [{"type": "api_call"}],
        "synchronous": False,
        "runner_options": {"tick_hz": 8},
        "recording": {"enable": False, "output_dir": str(episodes_dir)},
        "world_flavor": "stranger",
    }))
    (task_dir / "task.json").write_text(json.dumps({
        "id": "deliver_t1",
        "description": "Deliver the parcel in the stranger world.",
        "init": {"timeout_sec": 3600, "max_steps": 20},
        "success": {"mode": "program", "spec": {"program": "verifier.py::verify"}},
    }))
    (task_dir / "verifier.py").write_text(_VERIFIER)
    (root / "splits" / "stranger_env_split.json").write_text(json.dumps({
        "env_folder": "environments/stranger_env",
        "train_tasks": ["deliver_t1"],
        "test_tasks": [],
    }))
    return env_dir


class StrangerEpisodeTest(unittest.TestCase):
    """Full local episode through the public door (Phase 1 gate)."""

    def setUp(self):
        self._tmp = TemporaryDirectory()
        tmp = Path(self._tmp.name)
        self.episodes = tmp / "episodes"
        self.episodes.mkdir()
        self.env_dir = build_stranger_benchmark(tmp / "stranger_bench", self.episodes)

    def tearDown(self):
        self._tmp.cleanup()

    def test_full_local_episode(self):
        env = from_config(self.env_dir, task_id="deliver_t1")
        self.assertIsInstance(env.runner, StrangerRunner)
        # runner_options reached the world intact (L2 forwarding).
        self.assertEqual(env.env_spec.runner_options, {"tick_hz": 8})

        obs = env.reset(seed=7)
        # Unknown modalities are delegated and merged, not dropped, even
        # with rgb_screen declared alongside (the L2 regression).
        self.assertIn("telemetry", obs)
        self.assertIn("frames", obs)
        self.assertNotIn("screen", obs)  # this world has no screen capture

        # The world received the episode context (L3).
        manifest = Path(env.episode_dir) / "stranger_manifest.json"
        self.assertTrue(manifest.exists())
        self.assertEqual(json.loads(manifest.read_text())["task_id"], "deliver_t1")

        # `wait` is forwarded to a time-controlling world: 5 sim ticks pass,
        # ~0 wall seconds (L2: wall-clock sleep is a declinable convenience).
        t0 = time.monotonic()
        obs, _, done, info = env.step([{"action": "wait", "time": 5}])
        self.assertLess(time.monotonic() - t0, 1.0)
        self.assertFalse(done)
        self.assertEqual(obs["telemetry"]["ticks"], 5)

        obs, _, done, _ = env.step([{"action": "deliver", "target": "parcel"}])
        self.assertEqual(obs["telemetry"]["ticks"], 6)

        # Natural completion: verifier (the judge) reads the world's
        # ground-truth state through the episode artifacts.
        obs, reward, done, info = env.step([], mark_done=True)
        self.assertTrue(done)
        verifier = info.get("verifier") or {}
        self.assertTrue(verifier.get("passed"), msg=f"verifier said: {verifier}")

        episode_dir = env.episode_dir
        env.close()
        summary = json.loads((Path(episode_dir) / "summary.json").read_text())
        self.assertTrue(summary["verifier"]["passed"])

    def test_bad_runner_options_fail_at_spec_load(self):
        spec = json.loads((self.env_dir / "env.json").read_text())
        spec["runner_options"] = {"tick_hzz": 1}
        with self.assertRaisesRegex(ValueError, "tick_hzz"):
            make(spec)


class RunnerDoorTest(unittest.TestCase):
    """L1: the registry door — locators, short names, collision semantics."""

    def tearDown(self):
        runner_registry._table.pop("stranger", None)

    def test_locator_resolves_without_registration(self):
        cls = runner_registry.resolve_runner_class(STRANGER_LOCATOR)
        self.assertIs(cls, StrangerRunner)

    def test_locator_typo_raises_not_silently_falls_back(self):
        with self.assertRaises(runner_registry.RunnerRegistryError):
            runner_registry.resolve_runner_class("tests.test_stranger_party:NoSuchRunner")

    def test_locator_must_be_a_runner(self):
        with self.assertRaises(runner_registry.RunnerRegistryError):
            runner_registry.resolve_runner_class("tests.test_stranger_party:StrangerAgent")

    def test_short_name_registration_and_collisions(self):
        runner_registry.register_runner("stranger", StrangerRunner)
        self.assertIs(runner_registry.resolve_runner_class("stranger"), StrangerRunner)
        self.assertIn("stranger", runner_registry.list_runner_keys())
        with self.assertRaises(runner_registry.RunnerRegistryError):
            runner_registry.register_runner("stranger", StrangerRunner)
        runner_registry.register_runner("stranger", StrangerRunner, replace=True)

    def test_builtin_keys_are_reserved(self):
        with self.assertRaises(runner_registry.RunnerRegistryError):
            runner_registry.register_runner("qemu", StrangerRunner)

    def test_registered_runner_appears_in_doctor(self):
        from gym_anything.doctor import get_runner_status
        runner_registry.register_runner("stranger", StrangerRunner)
        status = get_runner_status()
        self.assertTrue(status["stranger"]["available"])
        self.assertIn("stranger-engine", status["stranger"]["deps"])

    def test_validator_accepts_locators_and_rejects_unknown_keys(self):
        base = {
            "id": "x",
            "observation": [{"type": "telemetry"}],
            "action": [{"type": "api_call"}],
        }
        validate_env_spec(EnvSpec.from_dict({**base, "runner": STRANGER_LOCATOR}))
        with self.assertRaisesRegex(ValueError, "not a registered runner key"):
            validate_env_spec(EnvSpec.from_dict({**base, "runner": "unreal"}))


class SpecToleranceTest(unittest.TestCase):
    """L2 applied to the spec: unknown fields survive, options round-trip."""

    def test_unknown_fields_are_preserved_not_dropped(self):
        spec = EnvSpec.from_dict({
            "id": "x",
            "observation": [{"type": "telemetry"}],
            "action": [{"type": "api_call"}],
            "world_flavor": "stranger",
            "runner_options": {"tick_hz": 8},
        })
        self.assertEqual(spec.extras["world_flavor"], "stranger")
        wire = asdict(spec)
        rehydrated = EnvSpec.from_dict(wire)
        self.assertEqual(rehydrated.runner_options, {"tick_hz": 8})
        self.assertEqual(rehydrated.extras["world_flavor"], "stranger")


class BenchmarkDoorTest(unittest.TestCase):
    """The benchmark-layout contract resolves strangers by path and by
    package name — the same door cua_world uses."""

    def setUp(self):
        self._tmp = TemporaryDirectory()
        self.tmp = Path(self._tmp.name)

    def tearDown(self):
        sys.path.remove(str(self.tmp / "pkgs"))
        sys.modules.pop("stranger_world", None)
        self._tmp.cleanup()

    def test_package_name_resolution(self):
        from gym_anything.registry import (
            get_tasks_for_environment,
            list_environments,
            resolve_benchmark_root,
        )
        pkg = self.tmp / "pkgs" / "stranger_world"
        pkg.mkdir(parents=True)
        (pkg / "__init__.py").write_text("")
        episodes = self.tmp / "episodes"
        episodes.mkdir()
        build_stranger_benchmark(pkg, episodes)

        sys.path.insert(0, str(self.tmp / "pkgs"))
        importlib.invalidate_caches()

        root = resolve_benchmark_root("stranger_world")
        self.assertEqual(root, pkg.resolve())
        self.assertEqual(list_environments("stranger_world"), ["stranger_env"])
        self.assertEqual(
            get_tasks_for_environment("stranger_env", "stranger_world", split="train"),
            ["deliver_t1"],
        )


class AgentDoorTest(unittest.TestCase):
    """L1 for policies: a locator resolves an agent core never heard of."""

    def test_agent_locator(self):
        try:
            from agents.evaluation.run_single import _resolve_agent_class
        except ImportError as exc:  # minimal core install without [agents] deps
            self.skipTest(f"agents extra not installed: {exc}")

        cls = _resolve_agent_class("tests.test_stranger_party:StrangerAgent")
        self.assertIs(cls, StrangerAgent)


if __name__ == "__main__":
    unittest.main()


# The stranger also runs the importable conformance suite — the dogfood rule:
# the export downstream repos consume is exercised by a party core has never
# met, in the same CI run.
from gym_anything.testing import build_conformance_case  # noqa: E402

StrangerConformance = build_conformance_case(
    STRANGER_LOCATOR,
    env_spec={"runner_options": {"tick_hz": 8}},
    actions=[{"action": "deliver", "target": "parcel"}],
    class_name="StrangerConformance",
)


class StrangerFactsSurfaceTest(unittest.TestCase):
    """Doctor and compatibility accept a runner core has never met."""

    def test_generic_compatibility_row_for_undeclared_runner(self):
        from gym_anything.compatibility import get_runner_compatibility

        row = get_runner_compatibility(STRANGER_LOCATOR)
        self.assertEqual(row.runner, STRANGER_LOCATOR)
        self.assertEqual(row.user_accounts_mode, "unsupported")
        self.assertFalse(row.savevm)

    def test_doctor_accepts_locator_runner(self):
        from gym_anything.doctor import run_doctor

        report = run_doctor(runner=STRANGER_LOCATOR)
        self.assertTrue(report.ok)
        names = [check.name for check in report.checks]
        self.assertIn(f"{STRANGER_LOCATOR}_runner", names)
        self.assertIn("stranger-engine", names)
