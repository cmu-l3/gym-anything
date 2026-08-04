"""The runner conformance suite, importable by downstream worlds.

A downstream repo points this at its runner (by locator or registered key)
and gets the behavioral contract checked: start, reset, observation
capture, action injection, task initialization (when a task is supplied),
failure recovery, idempotent shutdown, and — capability-gated on the spec's
own declaration — deterministic replay. Checks that don't apply to a world
skip honestly; nothing is faked.

Usage::

    from gym_anything.testing import build_conformance_case

    IsaacConformance = build_conformance_case(
        "robobench.isaac:IsaacSimRunner",
        env_spec={
            "observation": [{"type": "telemetry"}],
            "action": [{"type": "api_call"}],
            "runner_options": {"usd_stage": "warehouse/scene.usd"},
        },
        actions=[{"action": "step_sim", "steps": 4}],
    )

The returned class is a ``unittest.TestCase``; pytest and unittest both
collect it. The bundled stranger world runs this same suite in CI, so the
suite itself is exercised by a party core has never met (the dogfood rule).
"""

from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path
from typing import Any, Dict, List, Optional

from ..api import make

_DEFAULT_ACTIONS: List[Dict[str, Any]] = [{"action": "conformance_probe"}]


def build_conformance_case(
    runner_ref: str,
    *,
    env_spec: Optional[Dict[str, Any]] = None,
    task_spec: Optional[Dict[str, Any]] = None,
    actions: Optional[List[Dict[str, Any]]] = None,
    class_name: str = "RunnerConformanceCase",
) -> type:
    """Build a TestCase exercising ``runner_ref`` through the episode contract.

    Args:
        runner_ref: registered runner key or ``pkg.mod:ClassName`` locator.
        env_spec: overrides merged over a minimal spec (observation/action
            types, ``runner_options``, ``deterministic`` …). Recording is
            forced into a per-test temporary directory.
        task_spec: optional task dict; when given, reset() exercises task
            initialization too.
        actions: world-meaningful actions injected during the lifecycle
            check (defaults to a generic probe action the world may ignore).
    """
    base_spec: Dict[str, Any] = {
        "id": "conformance_env",
        "runner": runner_ref,
        "observation": [{"type": "telemetry"}],
        "action": [{"type": "api_call"}],
        "synchronous": False,
    }
    base_spec.update(env_spec or {})
    probe_actions = list(actions or _DEFAULT_ACTIONS)

    class _Case(unittest.TestCase):
        maxDiff = None

        def setUp(self):
            self._tmp = tempfile.TemporaryDirectory()
            spec = dict(base_spec)
            recording = dict(spec.get("recording") or {})
            recording.setdefault("enable", False)
            recording["output_dir"] = str(Path(self._tmp.name) / "episodes")
            spec["recording"] = recording
            self.spec = spec

        def tearDown(self):
            self._tmp.cleanup()

        def _make(self):
            return make(self.spec, dict(task_spec) if task_spec else None)

        def test_start_reset_observe_inject_shutdown(self):
            env = self._make()
            try:
                obs = env.reset(seed=1)
                self.assertIsInstance(obs, dict)
                self.assertTrue(obs, "reset produced an empty observation")
                obs, _reward, _done, _info = env.step(probe_actions)
                self.assertIsInstance(obs, dict)
                self.assertIsInstance(env.capture_observation(), dict)
            finally:
                env.close()

        def test_shutdown_is_idempotent(self):
            env = self._make()
            env.reset(seed=2)
            env.close()
            env.close()  # a second close must be a no-op, never an error

        def test_recovers_after_shutdown(self):
            env = self._make()
            env.reset(seed=3)
            env.close()
            fresh = self._make()
            try:
                self.assertTrue(fresh.reset(seed=4), "world did not recover for a fresh episode")
            finally:
                fresh.close()

        def test_deterministic_replay(self):
            if not base_spec.get("deterministic"):
                self.skipTest(
                    "world does not declare deterministic=True; replay is not part of its contract"
                )

            def _stable(obs):
                trimmed = {k: v for k, v in obs.items() if k != "screen"}
                return json.loads(json.dumps(trimmed, default=str))

            env = self._make()
            first = _stable(env.reset(seed=7))
            env.close()
            env = self._make()
            second = _stable(env.reset(seed=7))
            env.close()
            self.assertEqual(first, second)

    _Case.__name__ = class_name
    _Case.__qualname__ = class_name
    return _Case
