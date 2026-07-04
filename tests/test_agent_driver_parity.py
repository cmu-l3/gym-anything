"""Harness parity: the prime-rl driven loop runs the agent's step() verbatim.

The contract this file pins: for the same agent, environment, and scripted
model completions, the message sequences the model would see and the actions
the environment executes are IDENTICAL between (a) the local evaluation loop
(agents/evaluation/run_single.py) and (b) the driven loop the verifiers
adapter runs (gym_anything.integrations.verifiers._episode_loop + bridge).
The only permitted difference is who performs the sampling.

If this test fails after an agent or adapter change, the two harnesses have
drifted — fix the shared path, do not weaken the assertions.
"""

from __future__ import annotations

import io
import json
import tempfile
import threading
import unittest
from pathlib import Path

from PIL import Image

from agents.agents.qwen3vl import Qwen3VLAgent

try:
    import verifiers  # noqa: F401

    HAS_VERIFIERS = True
except ImportError:
    HAS_VERIFIERS = False


def _png_bytes() -> bytes:
    buf = io.BytesIO()
    Image.new("RGB", (64, 64), color=(120, 40, 200)).save(buf, format="PNG")
    return buf.getvalue()


_PNG_BYTES = _png_bytes()

RESOLUTION = (1920, 1080)

CLICK_RESPONSE = (
    'I will click.</think><tool_call>{"name": "computer_use", '
    '"arguments": {"action": "left_click", "coordinate": [500, 300]}}</tool_call>'
)
TERMINATE_RESPONSE = (
    'Done.</think><tool_call>{"name": "computer_use", '
    '"arguments": {"action": "terminate", "status": "success"}}</tool_call>'
)
SCRIPT = [CLICK_RESPONSE, TERMINATE_RESPONSE]


class _FakeEnv:
    """Minimal env: serves screenshots, records executed actions."""

    def __init__(self, tmp: str):
        self._tmp = Path(tmp)
        self._n = 0
        self.executed = []

    def _obs(self):
        path = self._tmp / f"screen_{self._n}.png"
        path.write_bytes(_PNG_BYTES)
        return {"screen": {"path": str(path), "resolution": RESOLUTION}}

    def capture_observation(self):
        return self._obs()

    def step(self, actions, mark_done=False):
        self.executed.append(json.loads(json.dumps(actions)))
        self._n += 1
        return self._obs(), 0.0, False, {"action_result": {"action": "ok", "output": "done"}}


def _make_agent(tmp: str) -> Qwen3VLAgent:
    agent = Qwen3VLAgent(
        agent_args={"model": "test-model", "exp_name": "parity", "task_name": "t"},
        verbose=False,
        debug=False,
    )
    agent.init(task_description="do the task", display_resolution=RESOLUTION, save_path=tmp)
    return agent


def _strip_images(messages):
    """Copy of messages with image payloads replaced by a stable marker.

    The image *bytes* are identical on both sides (same PNG source); the
    payloads are megabyte-scale, so compare their presence/position plus all
    text exactly, and the raw b64 separately.
    """
    out = []
    images = []
    for msg in messages:
        content = msg.get("content")
        if isinstance(content, list):
            parts = []
            for part in content:
                if isinstance(part, dict) and part.get("type") == "image_url":
                    images.append(part["image_url"]["url"])
                    parts.append({"type": "image_url", "image_url": {"url": "<img>"}})
                else:
                    parts.append(part)
            out.append({**msg, "content": parts})
        else:
            out.append(dict(msg))
    return out, images


def _run_local(tmp: str):
    """The run_single inner loop, with the model call scripted."""
    env = _FakeEnv(tmp)
    agent = _make_agent(tmp)
    captured = []

    def scripted_llm(messages, *args, **kwargs):
        captured.append(json.loads(json.dumps(messages)))
        return SCRIPT[len(captured) - 1]

    agent.llm_call = scripted_llm

    action_outputs = []
    obs = env.capture_observation()
    for _ in range(10):
        actions = agent.step(obs, action_outputs)
        action_outputs = []
        done = False
        for action in actions:
            obs, _reward, done, info = env.step(action["actions"])
            action_result = info.get(
                "action_result", {"action": "other", "output": "Executed the action"}
            )
            action_outputs.append({**action_result, "tool_id": action["tool_id"]})
        if getattr(agent, "done", False) or done:
            break
    return captured, env.executed


def _run_driven(tmp: str):
    """The adapter's episode loop, completions fed through the bridge."""
    from gym_anything.integrations.verifiers import _episode_loop, _StepBridge

    env = _FakeEnv(tmp)
    agent = _make_agent(tmp)
    bridge = _StepBridge()
    agent.llm_call = bridge.llm_call

    thread = threading.Thread(
        target=_episode_loop, args=(env, agent, bridge, env.capture_observation()), daemon=True
    )
    thread.start()

    captured = []
    while True:
        event, payload = bridge.next_request(timeout=30)
        if event == "finished":
            if payload:
                raise AssertionError(f"driven loop errored:\n{payload}")
            break
        captured.append(json.loads(json.dumps(payload)))
        bridge.send_completion(SCRIPT[len(captured) - 1])
    thread.join(timeout=30)
    return captured, env.executed


@unittest.skipUnless(HAS_VERIFIERS, "verifiers not installed")
class HarnessParityTests(unittest.TestCase):
    def test_driven_loop_is_the_local_loop(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_a, tempfile.TemporaryDirectory() as tmp_b:
            local_msgs, local_actions = _run_local(tmp_a)
            driven_msgs, driven_actions = _run_driven(tmp_b)

        self.assertEqual(len(local_msgs), len(SCRIPT))
        self.assertEqual(len(driven_msgs), len(SCRIPT))

        for turn, (lm, dm) in enumerate(zip(local_msgs, driven_msgs)):
            l_stripped, l_imgs = _strip_images(lm)
            d_stripped, d_imgs = _strip_images(dm)
            self.assertEqual(
                l_stripped, d_stripped, f"turn {turn}: message structure/text diverged"
            )
            self.assertEqual(l_imgs, d_imgs, f"turn {turn}: screenshot payloads diverged")

        self.assertEqual(local_actions, driven_actions, "executed env actions diverged")

    def test_driven_run_samples_with_the_agents_own_params(self) -> None:
        """The bridge forwards the agent's sampling params, so a driven run
        samples with exactly what the agent passes to its model call — not the
        endpoint defaults. This is what made local (top_k=20) and driven
        (top_k unset) diverge."""
        from gym_anything.integrations.verifiers import _sampling_args_from_call

        with tempfile.TemporaryDirectory() as tmp:
            _run_driven(tmp)  # exercises the bridge on a real agent's step()
            agent = _make_agent(tmp)

        # What the bridge would capture equals call_llm's mapping of the agent's
        # own (temperature, top_p, top_k) — for Qwen3VL: top_k in extra_body.
        expected = _sampling_args_from_call(
            (agent.model, agent.temperature, agent.top_p, agent.top_k), {}
        )
        self.assertEqual(expected["temperature"], agent.temperature)
        self.assertEqual(expected["top_p"], agent.top_p)
        self.assertEqual(expected["extra_body"]["top_k"], agent.top_k)

    def test_caller_sampling_args_win_per_key(self) -> None:
        """A prime-rl training sampling config overrides the agent's defaults
        per key, so training keeps control while eval gets parity by default."""
        from gym_anything.integrations.verifiers import _sampling_args_from_call

        agent_sa = _sampling_args_from_call(("m", 1.0, 0.95, 20), {})
        caller = {"temperature": 0.6, "extra_body": {"top_k": 50}}
        merged = {**agent_sa, **caller}
        merged["extra_body"] = {**agent_sa.get("extra_body", {}), **caller["extra_body"]}
        self.assertEqual(merged["temperature"], 0.6)          # caller wins
        self.assertEqual(merged["top_p"], 0.95)               # agent fills the rest
        self.assertEqual(merged["extra_body"]["top_k"], 50)   # caller wins

    def test_setup_state_writes_agent_sampling_into_state(self) -> None:
        """End-to-end wiring, no VM: the real setup_state populates
        state['sampling_args'] with the agent's params, which is exactly the
        field verifiers' get_model_response samples with."""
        import asyncio

        from gym_anything.integrations.verifiers import build_agent_env

        rows = [{
            "prompt": [{"role": "user", "content": "do it"}],
            "info": {"env_dir": "/x", "env_name": "e", "task_id": "t", "seed": 0},
            "task": "e/t",
        }]
        env = build_agent_env(rows, agent="Qwen3VLAgent",
                              agent_args={"model": "m", "exp_name": "s", "task_name": "t"},
                              runner=None, env_id="t")

        with tempfile.TemporaryDirectory() as tmp:
            fake = _FakeEnv(tmp)
            fake.episode_dir = tmp
            fake.set_episode_limits = lambda **kw: None
            env._boot = lambda info: (fake, fake.capture_observation())

            state = {"info": rows[0]["info"], "prompt": rows[0]["prompt"],
                     "sampling_args": {"n": 1, "extra_body": {}}}
            asyncio.run(env.setup_state(state))
            sa = state["sampling_args"]

        ref = _make_agent(tmp)
        self.assertEqual(sa["temperature"], ref.temperature)
        self.assertEqual(sa["top_p"], ref.top_p)
        self.assertEqual(sa["extra_body"]["top_k"], ref.top_k)  # the param that was being lost


class GeminiSeamTests(unittest.TestCase):
    """GeminiQwen3Agent honors the drivable contract (no verifiers needed)."""

    def test_gemini_agent_routes_through_the_seam(self) -> None:
        """An injected llm_call receives the model call with call_llm-compatible
        args, and the seam messages are plain OpenAI chat format (the cache
        hint lives in the local default client, not on the messages). This is
        what lets prime-rl drive this agent instead of it silently calling
        gemini itself from inside the worker."""
        from agents.agents.claude_gemini_qwen3 import GeminiQwen3Agent

        with tempfile.TemporaryDirectory() as tmp:
            env = _FakeEnv(tmp)
            agent = GeminiQwen3Agent(
                agent_args={"model": "gemini-test", "exp_name": "parity", "task_name": "t"},
                verbose=False,
                debug=False,
            )
            agent.init(
                task_description="do the task", display_resolution=RESOLUTION, save_path=tmp
            )

            captured = []

            def scripted_llm(messages, *args, **kwargs):
                captured.append((json.loads(json.dumps(messages)), args))
                return SCRIPT[len(captured) - 1]

            agent.llm_call = scripted_llm

            actions = agent.step(env.capture_observation(), [])

        self.assertEqual(len(captured), 1, "step() must make exactly one seam call")
        messages, args = captured[0]
        self.assertTrue(
            all("cache_control" not in m for m in messages),
            "seam messages must be plain OpenAI chat format",
        )
        self.assertEqual(args[:4], ("gemini-test", agent.temperature, agent.top_p, agent.top_k))
        # Coordinates decode with the agent's dynamic display ratio (1920/1000, 1080/1000).
        self.assertEqual(actions[0]["actions"], [{"mouse": {"left_click": [960, 324]}}])


if __name__ == "__main__":
    unittest.main()
