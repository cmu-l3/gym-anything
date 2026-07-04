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


if __name__ == "__main__":
    unittest.main()
