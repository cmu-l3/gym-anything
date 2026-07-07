from __future__ import annotations

import argparse
import os
import unittest
from unittest import mock

from gym_anything import cli


class BenchmarkCliOptionsTests(unittest.TestCase):
    def _args(self) -> argparse.Namespace:
        return argparse.Namespace(
            env_dir="benchmarks/cua_world/environments/thunderbird_env",
            task="organize_emails_into_folders",
            agent="Qwen35VLAgent",
            model="Qwen/Qwen3.5-2B",
            exp_name="exp",
            steps=3,
            seed=42,
            temperature=1.0,
            split="all",
            parallel=1,
            max_tasks=None,
            surface="raw",
            use_cache=True,
            cache_level="pre_start",
            use_savevm=False,
            fast_io=True,
            disable_thinking=True,
            timing_jsonl=None,
            remote_url=None,
            remote_timeout=300,
            remote_worker_reset_policy="core",
            verbose=False,
            debug=False,
            agent_arg=None,
            verifier_mode=None,
            vlm_checklist_model=None,
            vlm_checklist_backend=None,
            vlm_checklist_base_url=None,
            vlm_checklist_temperature=None,
            vlm_checklist_top_p=None,
            vlm_checklist_max_tokens=None,
            vlm_checklist_max_frames=None,
            vlm_checklist_completion_threshold=None,
            vlm_checklist_integrity_threshold=None,
        )

    def test_benchmark_uses_agent_model_as_default_vlm_model(self) -> None:
        with mock.patch("agents.evaluation.run_single.run_single", return_value=0) as run_single, \
             mock.patch.dict(os.environ, {}, clear=True):
            result = cli.cmd_benchmark(self._args())

        self.assertEqual(result, 0)
        ns = run_single.call_args.args[0]
        self.assertEqual(ns.vlm_model, "Qwen/Qwen3.5-2B")
        self.assertTrue(ns.fast_io)
        self.assertTrue(ns.disable_thinking)

    def test_benchmark_respects_explicit_vlm_model_env(self) -> None:
        with mock.patch("agents.evaluation.run_single.run_single", return_value=0) as run_single, \
             mock.patch.dict(os.environ, {"VLM_MODEL": "custom/verifier-model"}, clear=True):
            result = cli.cmd_benchmark(self._args())

        self.assertEqual(result, 0)
        ns = run_single.call_args.args[0]
        self.assertEqual(ns.vlm_model, "custom/verifier-model")


if __name__ == "__main__":
    unittest.main()
