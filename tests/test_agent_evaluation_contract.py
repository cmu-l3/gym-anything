from __future__ import annotations

import json
import os
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

from agents.evaluation import run_single as run_single_module


class _FakePolicy:
    instances = []

    def __init__(self, *args, **kwargs) -> None:
        self.agent_args = kwargs.get("agent_args", {})
        self.verbose = kwargs.get("verbose", False)
        self.debug = kwargs.get("debug", False)
        self.done = False
        self.step_calls = []
        self.finish_info = None
        type(self).instances.append(self)

    def init(self, task_description, display_resolution, save_path):
        self.task_description = task_description
        self.display_resolution = display_resolution
        self.save_path = save_path

    def step(self, obs, action_outputs):
        self.step_calls.append((obs, list(action_outputs)))
        if len(self.step_calls) == 1:
            return [{"tool_id": "tool-1", "actions": [{"action": "screenshot"}]}]
        self.done = True
        return []

    def finish(self, *args, **kwargs):
        self.finish_info = kwargs.get("info")


class _FakeEnv:
    def __init__(self, episode_dir: Path) -> None:
        self.episode_dir = episode_dir
        self.task_spec = SimpleNamespace(description="demo task")
        self.task_root = None
        self.env_spec = SimpleNamespace(observation=[SimpleNamespace(resolution=(64, 64))])
        self.max_steps = 2
        self.step_calls = []
        self.capture_calls = 0
        self.closed = False

    def reset(self, **kwargs):
        self.reset_kwargs = kwargs
        return {"screen": {"path": "reset.png"}}

    def capture_observation(self):
        self.capture_calls += 1
        return {"screen": {"path": f"capture_{self.capture_calls}.png"}}

    def step(self, actions, mark_done=False, **kwargs):
        self.step_calls.append((actions, mark_done))
        if mark_done:
            return {"screen": {"path": "final.png"}}, 1.0, True, {"verifier": {"passed": True, "score": 100}}
        return {
            "screen": {"path": "synthetic.png"}
        }, 0.0, False, {
            "action_result": {
                "action": "screenshot",
                "output": "synthetic.png",
            }
        }

    def set_episode_limits(self, *, max_steps=None, timeout_sec=None):
        if max_steps is not None:
            self.max_steps = max_steps

    def close(self):
        self.closed = True


class AgentEvaluationContractTests(unittest.TestCase):
    def test_run_single_relays_env_control_action_results_without_special_cases(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            fake_env = _FakeEnv(Path(tmp))
            args = SimpleNamespace(
                env_dir="demo-env",
                seed=42,
                task="demo-task",
                steps=2,
                agent="FakePolicy",
                agent_args=json.dumps({"model": "demo-model"}),
                debug=False,
                debug_low=False,
                verbose=False,
                setup_code="none",
                use_cache=False,
                cache_level="pre_start",
                use_savevm=False,
                vlm_backend="local",
                vlm_base_url="http://localhost:8080/v1",
                vlm_model="demo-model",
                remote_url=None,
                remote_timeout=300,
                remote_worker_reset_policy="core",
            )

            with mock.patch.object(run_single_module, "from_config", return_value=fake_env), \
                 mock.patch.object(run_single_module.agent_registry, "FakePolicy", _FakePolicy, create=True):
                _FakePolicy.instances.clear()
                result = run_single_module.run_single(args)

            self.assertEqual(result, 0)
            self.assertEqual(fake_env.step_calls[0], ([{"action": "screenshot"}], False))
            self.assertEqual(fake_env.step_calls[1], ([], True))
            self.assertTrue(fake_env.closed)

            policy = _FakePolicy.instances[0]
            self.assertEqual(len(policy.step_calls), 2)
            self.assertEqual(
                policy.step_calls[1][1],
                [{"action": "screenshot", "output": "synthetic.png", "tool_id": "tool-1"}],
            )
            self.assertEqual(policy.finish_info["verifier"]["score"], 100)

    def test_run_single_can_delay_and_refresh_model_observations(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            fake_env = _FakeEnv(Path(tmp))
            args = SimpleNamespace(
                env_dir="demo-env",
                seed=42,
                task="demo-task",
                steps=2,
                agent="FakePolicy",
                agent_args=json.dumps({"model": "demo-model"}),
                debug=False,
                debug_low=False,
                verbose=False,
                setup_code="none",
                use_cache=False,
                cache_level="pre_start",
                use_savevm=False,
                fast_io=True,
                disable_thinking=True,
                timing_jsonl=None,
                post_reset_observation_delay=15.0,
                post_step_observation_delay=0.3,
                vlm_backend="local",
                vlm_base_url="http://localhost:8080/v1",
                vlm_model="demo-model",
                remote_url=None,
                remote_timeout=300,
                remote_worker_reset_policy="core",
            )

            with mock.patch.object(run_single_module, "from_config", return_value=fake_env), \
                 mock.patch.object(run_single_module.agent_registry, "FakePolicy", _FakePolicy, create=True), \
                 mock.patch.object(run_single_module.time, "sleep") as sleep:
                _FakePolicy.instances.clear()
                result = run_single_module.run_single(args)

            self.assertEqual(result, 0)
            sleep.assert_any_call(15.0)
            sleep.assert_any_call(0.3)
            self.assertGreaterEqual(fake_env.capture_calls, 2)

            policy = _FakePolicy.instances[0]
            self.assertEqual(policy.step_calls[0][0]["screen"]["path"], "capture_1.png")
            self.assertEqual(policy.step_calls[1][0]["screen"]["path"], "capture_2.png")

            records = [json.loads(line) for line in (Path(tmp) / "timing.jsonl").read_text().splitlines()]
            self.assertTrue(any(record.get("event") == "post_reset_observation_delay" for record in records))
            iteration = next(record for record in records if record.get("event") == "iteration")
            self.assertGreater(iteration["post_step_observation_total_ms"], 0)

    def test_run_single_can_create_remote_environment(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            fake_env = _FakeEnv(Path(tmp))
            args = SimpleNamespace(
                env_dir="demo-env",
                seed=42,
                task="demo-task",
                steps=1,
                agent="FakePolicy",
                agent_args=json.dumps({"model": "demo-model"}),
                debug=False,
                debug_low=False,
                verbose=False,
                setup_code="none",
                use_cache=False,
                cache_level="pre_start",
                use_savevm=False,
                vlm_backend="local",
                vlm_base_url="http://localhost:8080/v1",
                vlm_model="demo-model",
                remote_url="http://127.0.0.1:5800",
                remote_timeout=12,
                remote_worker_reset_policy="baseline_setup",
            )

            with mock.patch.object(run_single_module.RemoteGymEnv, "from_config", return_value=fake_env) as remote_make, \
                 mock.patch.object(run_single_module.agent_registry, "FakePolicy", _FakePolicy, create=True):
                _FakePolicy.instances.clear()
                result = run_single_module.run_single(args)

            self.assertEqual(result, 0)
            remote_make.assert_called_once_with(
                remote_url="http://127.0.0.1:5800",
                env_dir="demo-env",
                task_id="demo-task",
                timeout=12,
                worker_reset_policy="baseline_setup",
                fast_io=False,
            )

    def test_run_single_passes_fast_io_and_writes_timing_log(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            fake_env = _FakeEnv(Path(tmp))
            args = SimpleNamespace(
                env_dir="demo-env",
                seed=42,
                task="demo-task",
                steps=1,
                agent="FakePolicy",
                agent_args=json.dumps({"model": "demo-model"}),
                debug=False,
                debug_low=False,
                verbose=False,
                setup_code="none",
                use_cache=False,
                cache_level="pre_start",
                use_savevm=False,
                fast_io=True,
                disable_thinking=True,
                timing_jsonl=None,
                vlm_backend="local",
                vlm_base_url="http://localhost:8080/v1",
                vlm_model="demo-model",
                remote_url=None,
                remote_timeout=300,
                remote_worker_reset_policy="core",
            )

            with mock.patch.object(run_single_module, "from_config", return_value=fake_env) as make_env, \
                 mock.patch.object(run_single_module.agent_registry, "FakePolicy", _FakePolicy, create=True), \
                 mock.patch.dict("os.environ", {}, clear=True):
                _FakePolicy.instances.clear()
                result = run_single_module.run_single(args)
                self.assertEqual(os.environ["VLM_DISABLE_THINKING"], "1")

            self.assertEqual(result, 0)
            make_env.assert_called_once_with("demo-env", task_id="demo-task", fast_io=True)
            timing_path = Path(tmp) / "timing.jsonl"
            summary_path = Path(tmp) / "timing_summary.json"
            self.assertTrue(timing_path.exists())
            self.assertTrue(summary_path.exists())
            records = [json.loads(line) for line in timing_path.read_text().splitlines()]
            self.assertEqual(records[0]["event"], "setup")
            self.assertTrue(any(record.get("event") == "iteration" for record in records))


if __name__ == "__main__":
    unittest.main()
