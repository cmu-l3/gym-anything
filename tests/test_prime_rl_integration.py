import inspect
import json
import tempfile
import unittest
from pathlib import Path

from agents.agents.qwen3vl import Qwen3VLAgent
from agents.shared.qwen_computer_use import qwen_system_prompt
from gym_anything.api import from_config
from gym_anything.integrations.hub import build_task_rows, make_hub_loader

try:
    import verifiers  # noqa: F401

    HAS_VERIFIERS = True
except ImportError:
    HAS_VERIFIERS = False

RES = (1920, 1080)


def _make_benchmark(root: Path, envs: dict) -> Path:
    """Write a minimal benchmark root: environments/<env>/tasks/<task>/task.json."""
    for env_name, task_ids in envs.items():
        for task_id in task_ids:
            task_dir = root / "environments" / env_name / "tasks" / task_id
            task_dir.mkdir(parents=True)
            (task_dir / "task.json").write_text(
                json.dumps({"id": task_id, "description": f"do {task_id}"}), encoding="utf-8"
            )
    return root


def _agent() -> Qwen3VLAgent:
    a = Qwen3VLAgent(
        agent_args={"model": "test-model", "exp_name": "unittest", "task_name": "t"},
        verbose=False,
        debug=False,
    )
    a.init(task_description="do the task", display_resolution=RES, save_path=".")
    return a


def _png_bytes() -> bytes:
    import io

    from PIL import Image

    buf = io.BytesIO()
    Image.new("RGB", (64, 64), color=(120, 40, 200)).save(buf, format="PNG")
    return buf.getvalue()


_PNG_BYTES = _png_bytes()


class AgentDriverSeamTests(unittest.TestCase):
    """step() routes its model call through self.llm_call — the driven seam.

    An external loop (prime-rl) injects its own llm_call and runs the agent's
    real step() verbatim; these tests pin that seam. Full local-vs-driven
    harness parity is pinned in tests/test_agent_driver_parity.py.
    """

    def test_agent_advertises_it_can_be_driven(self) -> None:
        self.assertTrue(getattr(Qwen3VLAgent, "driven", False))

    def test_default_llm_call_is_the_local_client(self) -> None:
        from agents.shared.llm_clients import call_llm

        self.assertIs(Qwen3VLAgent.llm_call, call_llm)

    def test_step_routes_model_call_through_injected_seam(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            screen = Path(tmp) / "s.png"
            screen.write_bytes(_PNG_BYTES)
            a = _agent()
            seen: dict = {}

            def fake_llm(messages, *args, **kwargs):
                seen["messages"] = messages
                return (
                    '<tool_call>{"name":"computer_use","arguments":'
                    '{"action":"left_click","coordinate":[500,500]}}</tool_call>'
                )

            a.llm_call = fake_llm
            groups = a.step({"screen": {"path": str(screen)}}, [])

        # The messages the seam sees are the agent's own build_messages output.
        msgs = seen["messages"]
        self.assertEqual(msgs[0]["role"], "system")
        self.assertEqual(msgs[0]["content"][0]["text"], qwen_system_prompt(RES))
        self.assertTrue(any(p.get("type") == "image_url" for p in msgs[1]["content"]))
        # The returned actions come from the agent's own parser (500/1000 * res).
        self.assertEqual(groups[0]["actions"], [{"mouse": {"left_click": [960, 540]}}])
        self.assertFalse(a.done)

    def test_terminate_completion_marks_agent_done(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            screen = Path(tmp) / "s.png"
            screen.write_bytes(_PNG_BYTES)
            a = _agent()
            a.llm_call = lambda *args, **kwargs: (
                '<tool_call>{"name":"computer_use","arguments":'
                '{"action":"terminate","status":"success"}}</tool_call>'
            )
            groups = a.step({"screen": {"path": str(screen)}}, [])
        self.assertTrue(a.done)
        self.assertEqual(groups[0]["actions"], [])


@unittest.skipUnless(HAS_VERIFIERS, "verifiers not installed")
class AgentSelectionTests(unittest.TestCase):
    def test_make_agent_instantiates_real_class_by_name(self) -> None:
        from gym_anything.integrations.verifiers import _make_agent

        agent = _make_agent("Qwen3VLAgent", {"model": "m", "exp_name": "sel", "task_name": "t"})
        self.assertIsInstance(agent, Qwen3VLAgent)

    def test_provider_native_agent_is_rejected_as_undrivable(self) -> None:
        from gym_anything.integrations.verifiers import _make_agent

        # ClaudeAgent uses the Anthropic native tool; it cannot run over an
        # OpenAI policy endpoint, so it must be rejected clearly.
        with self.assertRaises(ValueError):
            _make_agent("ClaudeAgent", {"exp_name": "sel", "task_name": "t"})

    def test_unknown_agent_name_raises(self) -> None:
        from gym_anything.integrations.verifiers import _make_agent

        with self.assertRaises(ValueError):
            _make_agent("NotARealAgent", {})


class HubRowsTests(unittest.TestCase):
    def test_rows_carry_absolute_env_dir_and_prompt(self) -> None:
        rows = build_task_rows("cua_world", "gimp_env", max_examples=3)
        self.assertTrue(rows)
        for row in rows:
            self.assertTrue(Path(row["info"]["env_dir"]).is_absolute())
            self.assertEqual(row["info"]["env_name"], "gimp_env")
            self.assertTrue(row["prompt"][0]["content"])
            self.assertTrue(row["task"].startswith("gimp_env/"))

    def test_task_id_whitelist_filters(self) -> None:
        all_rows = build_task_rows("cua_world", "gimp_env")
        wanted = all_rows[0]["info"]["task_id"]
        rows = build_task_rows("cua_world", "gimp_env", task_ids=[wanted])
        self.assertEqual([r["info"]["task_id"] for r in rows], [wanted])

    def test_no_matches_raises(self) -> None:
        with self.assertRaises(ValueError):
            build_task_rows("cua_world", "gimp_env", task_ids=["definitely-not-a-task"])

    def test_env_names_all_covers_every_environment(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = _make_benchmark(Path(tmp), {"a_env": ["t1"], "b_env": ["t2", "t3"]})
            rows = build_task_rows(root, "all", seed=7)
            self.assertEqual([r["task"] for r in rows], ["a_env/t1", "b_env/t2", "b_env/t3"])
            self.assertTrue(all(r["info"]["seed"] == 7 for r in rows))


class FromConfigOverridesTests(unittest.TestCase):
    def test_from_config_accepts_overrides(self) -> None:
        self.assertIn("overrides", inspect.signature(from_config).parameters)

    def test_relative_mounts_resolve_against_env_root(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "scripts").mkdir()
            (root / "env.json").write_text(
                json.dumps(
                    {
                        "id": "demo-env",
                        "observation": [{"type": "rgb_screen"}],
                        "action": [{"type": "mouse"}],
                        "runner": "local",
                        "mounts": [
                            {"target": "/workspace/scripts", "source": "scripts", "mode": "ro"},
                            {"target": "/workspace/missing", "source": "does/not/exist", "mode": "ro"},
                        ],
                    }
                ),
                encoding="utf-8",
            )
            env = from_config(root)
            try:
                sources = {m.target: m.source for m in env.env_spec.mounts}
                self.assertEqual(sources["/workspace/scripts"], str((root / "scripts").resolve()))
                self.assertEqual(sources["/workspace/missing"], "does/not/exist")
            finally:
                env.close()


@unittest.skipUnless(HAS_VERIFIERS, "verifiers not installed")
class VerifiersAdapterTests(unittest.TestCase):
    def test_finalize_runs_verifier_once_while_env_alive(self) -> None:
        from gym_anything.integrations.verifiers import _finalize_episode

        class FakeEnv:
            def __init__(self) -> None:
                self.mark_done_calls = 0

            def step(self, actions, mark_done=False):
                assert mark_done
                self.mark_done_calls += 1
                return {}, 1.0, True, {"verifier": {"passed": True, "score": 100}}

        fake = FakeEnv()
        state = {"ga_env": fake}
        _finalize_episode(state)
        self.assertEqual(state["episode_reward"], 1.0)
        self.assertTrue(state["verifier"]["passed"])
        _finalize_episode(state)
        self.assertEqual(fake.mark_done_calls, 1)

    def test_finalize_without_env_surfaces_boot_failure(self) -> None:
        from gym_anything.integrations.verifiers import _finalize_episode

        state = {}
        _finalize_episode(state)
        self.assertEqual(state["episode_reward"], 0.0)
        self.assertIn("error", state["verifier"])

    def test_build_agent_env_constructs_environment(self) -> None:
        import verifiers as vf

        from gym_anything.integrations.verifiers import build_agent_env

        rows = [
            {
                "prompt": [{"role": "user", "content": "do the thing"}],
                "info": {"env_dir": "/nonexistent", "env_name": "e", "task_id": "t", "seed": 0},
                "task": "e/t",
            }
        ]
        env = build_agent_env(rows, agent="Qwen3VLAgent", runner=None, env_id="test-env")
        self.assertIsInstance(env, vf.Environment)

    def test_build_agent_env_requires_a_drivable_agent(self) -> None:
        from gym_anything.integrations.verifiers import build_agent_env

        rows = [
            {
                "prompt": [{"role": "user", "content": "x"}],
                "info": {"env_dir": "/nonexistent", "env_name": "e", "task_id": "t", "seed": 0},
                "task": "e/t",
            }
        ]
        with self.assertRaises(ValueError):
            build_agent_env(rows, agent="", runner=None, env_id="t")  # no agent
        with self.assertRaises(ValueError):
            build_agent_env(rows, agent="ClaudeAgent", runner=None, env_id="t")  # native


@unittest.skipUnless(HAS_VERIFIERS, "verifiers not installed")
class HubLoaderTests(unittest.TestCase):
    """The shell surface: prime-rl workers re-instantiate via load_environment(**env_args)."""

    def test_env_args_reconstruct_the_environment_faithfully(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = _make_benchmark(Path(tmp), {"a_env": ["t1"]})
            load_environment = make_hub_loader(root, env_id="demo", runner=None, agent="Qwen3VLAgent")

            env = load_environment(verifier_mode="vlm_checklist", vlm_model="some/model", max_turns=7)
            args = env.env_args
            self.assertEqual(args["verifier_mode"], "vlm_checklist")
            self.assertEqual(args["vlm_model"], "some/model")
            self.assertEqual(args["max_turns"], 7)
            self.assertEqual(args["benchmark"], str(root))
            self.assertEqual(args["agent"], "Qwen3VLAgent")
            self.assertIn("use_savevm", args)
            # The framework re-instantiates via vf.load_environment(env_id,
            # **env_args); env_args carrying env_id collides at that call.
            self.assertNotIn("env_id", args)

            rebuilt = load_environment(**args)
            self.assertEqual(rebuilt.env_args, args)
            self.assertEqual(rebuilt.max_turns, env.max_turns)

    def test_loader_selects_agent_by_name_like_local(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = _make_benchmark(Path(tmp), {"a_env": ["t1"]})
            load_environment = make_hub_loader(
                root, env_id="demo", runner=None, agent="Qwen3VLAgent",
                agent_args={"model": "m"},
            )
            env = load_environment()
            self.assertEqual(env.agent_name, "Qwen3VLAgent")
            self.assertEqual(env.env_args["agent"], "Qwen3VLAgent")

    def test_loader_requires_an_agent(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = _make_benchmark(Path(tmp), {"a_env": ["t1"]})
            load_environment = make_hub_loader(root, env_id="demo", runner=None)
            with self.assertRaises(ValueError):
                load_environment()  # no agent named


if __name__ == "__main__":
    unittest.main()
