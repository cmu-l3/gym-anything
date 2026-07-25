"""Offline tests for the CLI-harness action gateway.

Covers the testable core (command -> env.step translation, budget
enforcement, display resize + coordinate scaling, prompt) with a fake env.
No docker, no sockets.
"""
import base64
import io
import unittest

from PIL import Image

from agents.shared.cli_harness import (
    ActionGateway,
    build_harness_prompt,
    _obs_png_bytes,
)


def _png(width=1920, height=1080, color=(20, 30, 40)) -> bytes:
    buf = io.BytesIO()
    Image.new("RGB", (width, height), color).save(buf, format="PNG")
    return buf.getvalue()


_NATIVE_PNG = _png(1920, 1080)


class FakeEnv:
    """Minimal env: records step() calls, returns a real native-res PNG frame."""

    def __init__(self, max_steps=5, done_after=None):
        self.max_steps = max_steps
        self.calls: list[list] = []
        self._n = 0
        self._done_after = done_after

    def _obs(self):
        return {"screen": {"png_b64": base64.b64encode(_NATIVE_PNG).decode()}}

    def step(self, actions, **kwargs):
        self.calls.append(actions)
        self._n += 1
        done = self._done_after is not None and self._n >= self._done_after
        return self._obs(), 0.0, done, {}

    def capture_observation(self):
        return self._obs()


def _gateway(env, resolution=(1920, 1080)):
    return ActionGateway(env, resolution, max_steps=env.max_steps, token="tok")


class DisplayScalingTests(unittest.TestCase):
    def test_gateway_computes_display_and_ratio(self):
        gw = _gateway(FakeEnv())
        # 1920x1080 downscaled to a 1280 long side -> 1280x720, ratio 1.5.
        self.assertEqual((gw.display_w, gw.display_h), (1280, 720))
        self.assertAlmostEqual(gw.ratio_x, 1.5)
        self.assertAlmostEqual(gw.ratio_y, 1.5)

    def test_small_env_is_not_upscaled(self):
        gw = _gateway(FakeEnv(), resolution=(800, 600))
        self.assertEqual((gw.display_w, gw.display_h), (800, 600))
        self.assertAlmostEqual(gw.ratio_x, 1.0)

    def test_served_screenshot_is_resized_to_display(self):
        gw = _gateway(FakeEnv())
        resp = gw.step_from_command('{"action": "screenshot"}')
        img = Image.open(io.BytesIO(base64.b64decode(resp["screenshot_b64"])))
        self.assertEqual(img.size, (1280, 720))


class CommandTranslationTests(unittest.TestCase):
    def test_left_click_scales_display_pixels_to_native(self):
        env = FakeEnv()
        gw = _gateway(env)
        # Model clicks (640, 360) in the 1280x720 display -> (960, 540) native.
        resp = gw.step_from_command('{"action": "left_click", "coordinate": [640, 360]}')
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

    def test_drag_scales_both_coordinates(self):
        env = FakeEnv()
        gw = _gateway(env)
        gw.step_from_command(
            '{"action": "drag", "coordinate": [100, 200], "coordinate2": [600, 400]}'
        )
        # each display coord * 1.5 -> native
        self.assertEqual(
            env.calls[-1], [{"mouse": {"left_click_drag": [[150, 300], [900, 600]]}}]
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
        # 1 * 1.5 -> int(1.5) == 1
        self.assertEqual(gw.transcript[1]["env_actions"], [{"mouse": {"left_click": [1, 1]}}])


class ObservationExtractionTests(unittest.TestCase):
    def test_png_bytes_from_path(self):
        import tempfile, os
        with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as fh:
            fh.write(_NATIVE_PNG)
            path = fh.name
        try:
            self.assertEqual(_obs_png_bytes({"screen": {"path": path}}), _NATIVE_PNG)
        finally:
            os.unlink(path)

    def test_png_bytes_from_b64(self):
        b64 = base64.b64encode(_NATIVE_PNG).decode()
        self.assertEqual(_obs_png_bytes({"screen": {"png_b64": b64}}), _NATIVE_PNG)

    def test_png_bytes_from_pil_like_image(self):
        class FakeImage:
            def save(self, buffer, format):  # noqa: A002
                buffer.write(b"pilbytes")

        self.assertEqual(_obs_png_bytes({"screen": {"image": FakeImage()}}), b"pilbytes")

    def test_png_bytes_missing_returns_none(self):
        self.assertIsNone(_obs_png_bytes({"screen": {}}))
        self.assertIsNone(_obs_png_bytes({}))


class PromptTests(unittest.TestCase):
    def test_prompt_contains_task_budget_and_act_usage(self):
        # build_harness_prompt is given the display resolution.
        prompt = build_harness_prompt("Fill the background green.", (1280, 720), 40)
        self.assertIn("Fill the background green.", prompt)
        self.assertIn("at most 40 actions", prompt)
        self.assertIn("act '{", prompt)
        self.assertIn("PIXELS", prompt)
        self.assertIn("1280x720", prompt)
        self.assertIn("terminate", prompt)


if __name__ == "__main__":
    unittest.main()
