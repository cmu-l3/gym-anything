"""Offline tests for the CLI-harness action gateway.

Covers the testable core (command -> env.step translation, budget
enforcement, screenshot extraction, prompt) with a fake env. No docker, no
sockets.
"""
import base64
import unittest
from types import SimpleNamespace

from agents.shared.cli_harness import (
    ActionGateway,
    build_harness_prompt,
    _obs_png_b64,
)


class FakeEnv:
    """Minimal env: records step() calls, returns a distinct fake screenshot."""

    def __init__(self, max_steps=5, done_after=None):
        self.max_steps = max_steps
        self.calls: list[list] = []
        self._n = 0
        self._done_after = done_after

    def _obs(self):
        return {"screen": {"png_b64": base64.b64encode(f"frame{self._n}".encode()).decode()}}

    def step(self, actions, **kwargs):
        self.calls.append(actions)
        self._n += 1
        done = self._done_after is not None and self._n >= self._done_after
        return self._obs(), 0.0, done, {}

    def capture_observation(self):
        return self._obs()


def _gateway(env, resolution=(1920, 1080)):
    return ActionGateway(env, resolution, max_steps=env.max_steps, token="tok")


class CommandTranslationTests(unittest.TestCase):
    def test_left_click_scales_from_0_1000_grid(self):
        env = FakeEnv()
        gw = _gateway(env)
        resp = gw.step_from_command('{"action": "left_click", "coordinate": [500, 500]}')
        # 500/1000 * 1920 = 960 ; 500/1000 * 1080 = 540
        self.assertEqual(env.calls[-1], [{"mouse": {"left_click": [960, 540]}}])
        self.assertEqual(resp["budget_remaining"], 4)
        self.assertIsNotNone(resp["screenshot_b64"])

    def test_type_with_enter_and_clear(self):
        env = FakeEnv()
        gw = _gateway(env)
        gw.step_from_command('{"action": "type", "text": "hi", "clear": true, "enter": true}')
        self.assertEqual(
            env.calls[-1],
            [
                {"keyboard": {"keys": ["ctrl", "a"]}},
                {"keyboard": {"text": "hi"}},
                {"keyboard": {"keys": ["Return"]}},
            ],
        )

    def test_key_chord(self):
        env = FakeEnv()
        gw = _gateway(env)
        gw.step_from_command('{"action": "key", "keys": ["ctrl", "s"]}')
        self.assertEqual(env.calls[-1], [{"keyboard": {"keys": ["ctrl", "s"]}}])

    def test_screenshot_only_still_steps(self):
        env = FakeEnv()
        gw = _gateway(env)
        resp = gw.step_from_command('{"action": "screenshot"}')
        self.assertEqual(env.calls[-1], [{"action": "screenshot"}])
        self.assertFalse(resp["done"])

    def test_wait_maps_to_wait_action(self):
        env = FakeEnv()
        gw = _gateway(env)
        gw.step_from_command('{"action": "wait", "time": 2.5}')
        self.assertEqual(env.calls[-1], [{"action": "wait", "time": 2.5}])

    def test_drag_uses_two_coordinates(self):
        env = FakeEnv()
        gw = _gateway(env)
        gw.step_from_command(
            '{"action": "drag", "coordinate": [0, 0], "coordinate2": [1000, 1000]}'
        )
        self.assertEqual(
            env.calls[-1], [{"mouse": {"left_click_drag": [[0, 0], [1920, 1080]]}}]
        )


class TerminalAndErrorTests(unittest.TestCase):
    def test_terminate_sets_done_without_env_action(self):
        env = FakeEnv()
        gw = _gateway(env)
        resp = gw.step_from_command('{"action": "terminate", "status": "success"}')
        self.assertTrue(resp["done"])
        self.assertEqual(env.calls[-1], [])

    def test_malformed_json_does_not_consume_budget(self):
        env = FakeEnv()
        gw = _gateway(env)
        resp = gw.step_from_command("not json")
        self.assertIn("invalid action JSON", resp["error"])
        self.assertEqual(resp["budget_remaining"], 5)  # unchanged
        self.assertEqual(len(env.calls), 0)  # no env.step
        self.assertIsNotNone(resp["screenshot_b64"])  # still returns a frame

    def test_missing_action_key_is_error(self):
        env = FakeEnv()
        gw = _gateway(env)
        resp = gw.step_from_command('{"coordinate": [1, 2]}')
        self.assertIn("action", resp["error"])
        self.assertEqual(len(env.calls), 0)


class BudgetTests(unittest.TestCase):
    def test_budget_exhaustion_blocks_further_steps(self):
        env = FakeEnv(max_steps=2)
        gw = _gateway(env)
        gw.step_from_command('{"action": "screenshot"}')
        r2 = gw.step_from_command('{"action": "screenshot"}')
        self.assertEqual(r2["budget_remaining"], 0)
        self.assertTrue(r2["done"])
        r3 = gw.step_from_command('{"action": "screenshot"}')
        self.assertEqual(r3["error"], "step budget exhausted")
        self.assertEqual(len(env.calls), 2)  # third was refused

    def test_env_done_propagates(self):
        env = FakeEnv(max_steps=10, done_after=1)
        gw = _gateway(env)
        resp = gw.step_from_command('{"action": "left_click", "coordinate": [1, 1]}')
        self.assertTrue(resp["done"])

    def test_transcript_records_each_action(self):
        env = FakeEnv()
        gw = _gateway(env)
        gw.step_from_command('{"action": "screenshot"}')
        gw.step_from_command('{"action": "left_click", "coordinate": [1, 1]}')
        self.assertEqual(len(gw.transcript), 2)
        self.assertEqual(gw.transcript[1]["env_actions"], [{"mouse": {"left_click": [1, 1]}}])


class ObservationExtractionTests(unittest.TestCase):
    def test_png_b64_from_path(self):
        import tempfile, os
        with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as fh:
            fh.write(b"\x89PNG-fake")
            path = fh.name
        try:
            b64 = _obs_png_b64({"screen": {"path": path}})
            self.assertEqual(base64.b64decode(b64), b"\x89PNG-fake")
        finally:
            os.unlink(path)

    def test_png_b64_from_pil_like_image(self):
        class FakeImage:
            def save(self, buffer, format):  # noqa: A002
                buffer.write(b"pilbytes")

        b64 = _obs_png_b64({"screen": {"image": FakeImage()}})
        self.assertEqual(base64.b64decode(b64), b"pilbytes")

    def test_png_b64_missing_returns_none(self):
        self.assertIsNone(_obs_png_b64({"screen": {}}))
        self.assertIsNone(_obs_png_b64({}))


class PromptTests(unittest.TestCase):
    def test_prompt_contains_task_budget_and_act_usage(self):
        prompt = build_harness_prompt("Fill the background green.", (1920, 1080), 40)
        self.assertIn("Fill the background green.", prompt)
        self.assertIn("at most 40 actions", prompt)
        self.assertIn("act '{", prompt)
        self.assertIn("0-1000 grid", prompt)
        self.assertIn("terminate", prompt)


if __name__ == "__main__":
    unittest.main()
