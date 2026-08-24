"""Offline tests for the CLI-harness action gateway.

Covers the testable core (command -> env.step translation, budget
enforcement, display resize + coordinate scaling, prompt) with a fake env.
No docker, no sockets.
"""
import base64
import io
import json
import tempfile
import threading
import time
import unittest
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from unittest import mock

from PIL import Image

from agents.shared.cli_harness import (
    _ACT_SCRIPT,
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


class TimedFakeEnv(FakeEnv):
    def __init__(self, root: Path):
        super().__init__()
        self.root = root

    def _obs(self):
        start_ms = time.time_ns() / 1_000_000
        manifest = self.root / f"manifest-{self._n}.json"
        manifest.write_text(
            json.dumps(
                {
                    "window_started_wall_ms": start_ms,
                    "frames": [{"offset_ms": 0}],
                }
            )
        )
        obs = super()._obs()
        obs["capture_manifest"] = str(manifest)
        return obs


def _gateway(env, resolution=(1920, 1080), temporal_mode="live"):
    return ActionGateway(
        env,
        resolution,
        max_steps=env.max_steps,
        token="tok",
        temporal_mode=temporal_mode,
    )


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

    def test_live_mode_returns_only_the_last_frame(self):
        env = FakeEnv()
        colors = [(200, 0, 0), (0, 200, 0), (0, 0, 200), (100, 100, 0), (0, 100, 100), (100, 0, 100)]
        env._obs = lambda: {
            "frames": [
                {"png_b64": base64.b64encode(_png(color=color)).decode()}
                for color in colors
            ],
            "screen": {"png_b64": base64.b64encode(_png(color=colors[-1])).decode()},
        }
        resp = _gateway(env).step_from_command('{"action": "screenshot"}')

        self.assertEqual(len(resp["screenshots_b64"]), 1)
        image = Image.open(io.BytesIO(base64.b64decode(resp["screenshot_b64"])))
        self.assertEqual(image.size, (1280, 720))
        self.assertEqual(image.getpixel((0, 0)), colors[-1])
        self.assertEqual(resp["screenshot_b64"], resp["screenshots_b64"][-1])

    def test_paused_mode_keeps_the_chronological_frame_window(self):
        env = FakeEnv()
        colors = [(200, 0, 0), (0, 200, 0), (0, 0, 200)]
        env._obs = lambda: {
            "frames": [
                {"png_b64": base64.b64encode(_png(color=color)).decode()}
                for color in colors
            ],
            "screen": {"png_b64": base64.b64encode(_png(color=colors[-1])).decode()},
        }
        resp = _gateway(env, temporal_mode="paused").step_from_command(
            '{"action": "screenshot"}'
        )

        self.assertEqual(len(resp["screenshots_b64"]), 3)
        self.assertEqual(
            [
                Image.open(io.BytesIO(base64.b64decode(encoded))).getpixel((0, 0))
                for encoded in resp["screenshots_b64"]
            ],
            colors,
        )

    def test_remote_frame_paths_are_fetched(self):
        import tempfile

        env = FakeEnv()
        with tempfile.TemporaryDirectory() as tmp:
            local = Path(tmp) / "fetched.png"
            local.write_bytes(_NATIVE_PNG)
            env._obs = lambda: {
                "frames": [{"path": "/remote/turn/frame-000.png"}],
                "screen": {"path": "/remote/turn/frame-000.png", "remote": True},
            }
            env.fetch_path = mock.Mock(return_value=str(local))
            resp = _gateway(env).step_from_command('{"action": "screenshot"}')

        self.assertEqual(len(resp["screenshots_b64"]), 1)
        env.fetch_path.assert_called_once_with("/remote/turn/frame-000.png")


class CommandTranslationTests(unittest.TestCase):
    def test_left_click_scales_display_pixels_to_native(self):
        env = FakeEnv()
        gw = _gateway(env)
        # Model clicks (640, 360) in the 1280x720 display -> (960, 540) native.
        resp = gw.step_from_command('{"action": "left_click", "coordinate": [640, 360]}')
        self.assertEqual(env.calls[-1], [{"mouse": {"left_click": [960, 540]}}])
        self.assertEqual(resp["budget_remaining"], 4)
        self.assertIsNotNone(resp["screenshot_b64"])

    def test_action_injection_defers_settling_and_observation(self):
        env = FakeEnv()
        gw = _gateway(env)
        with mock.patch.object(env, "step", wraps=env.step) as step:
            gw.step_from_command('{"action": "left_click", "coordinate": [640, 360]}')

        step.assert_called_once_with(
            [{"mouse": {"left_click": [960, 540]}}],
            capture_observation=False,
            settle_after_actions=False,
        )

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

    def test_screenshot_captures_without_consuming_action(self):
        env = FakeEnv()
        gw = _gateway(env)
        resp = gw.step_from_command('{"action": "screenshot"}')
        self.assertEqual(env.calls, [])
        self.assertEqual(resp["budget_remaining"], 5)
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


class TemporalModeTests(unittest.TestCase):
    def test_plain_modes_do_not_return_timing(self):
        with tempfile.TemporaryDirectory() as tmp:
            for mode in ("paused", "live"):
                response = _gateway(
                    TimedFakeEnv(Path(tmp)), temporal_mode=mode
                ).step_from_command('{"action": "screenshot"}')
                self.assertNotIn("timing", response)

    def test_timestamped_mode_reports_capture_and_action_latency(self):
        with tempfile.TemporaryDirectory() as tmp:
            gateway = _gateway(
                TimedFakeEnv(Path(tmp)), temporal_mode="live_timestamped"
            )
            first = gateway.step_from_command('{"action": "screenshot"}')
            second = gateway.step_from_command(
                '{"action": "left_click", "coordinate": [640, 360]}'
            )

        self.assertEqual(first["timing"]["frame_captured_at_s"], 0.0)
        self.assertEqual(first["timing"]["screenshot_captured_at_s"], [0.0])
        self.assertGreaterEqual(first["timing"]["current_time_s"], 0.0)
        timing = second["timing"]
        self.assertIn("action_executed_at_s", timing)
        self.assertEqual(
            timing["previous_action_finished_executing_by_s"],
            timing["action_executed_at_s"],
        )
        self.assertGreaterEqual(
            timing["seconds_between_your_last_screenshot_and_that_action_landing"],
            0,
        )
        self.assertEqual(
            timing["your_recent_observe_to_execute_latencies_s"],
            [timing["seconds_between_your_last_screenshot_and_that_action_landing"]],
        )
        self.assertGreaterEqual(
            timing["frame_captured_at_s"], timing["action_executed_at_s"]
        )

    def test_execute_at_is_rejected_outside_execution_mode(self):
        for mode in ("paused", "live", "live_timestamped"):
            env = FakeEnv()
            response = _gateway(env, temporal_mode=mode).step_from_command(
                '{"action": "left_click", "coordinate": [10, 20], "execute_at_s": 4}'
            )
            self.assertIn("live_timestamped_execution", response["error"])
            self.assertEqual(env.calls, [])

    def test_execution_mode_schedules_against_the_observation_clock(self):
        with tempfile.TemporaryDirectory() as tmp:
            env = TimedFakeEnv(Path(tmp))
            gateway = _gateway(
                env, temporal_mode="live_timestamped_execution"
            )
            initial = gateway.step_from_command('{"action": "screenshot"}')
            execute_at_s = initial["timing"]["current_time_s"] + 0.12
            started = time.monotonic()
            response = gateway.step_from_command(
                json.dumps(
                    {
                        "action": "left_click",
                        "coordinate": [640, 360],
                        "execute_at_s": execute_at_s,
                    }
                )
            )

        self.assertGreaterEqual(time.monotonic() - started, 0.09)
        self.assertEqual(
            env.calls[-1], [{"mouse": {"left_click": [960, 540]}}]
        )
        self.assertEqual(
            response["timing"]["previous_action_requested_execute_at_s"],
            execute_at_s,
        )
        self.assertLess(abs(response["timing"]["action_execution_lateness_s"]), 0.05)
        self.assertEqual(
            gateway.transcript[-1]["requested_execute_at_s"], execute_at_s
        )

    def test_current_time_accounts_for_frame_retrieval_delay(self):
        class SlowTimedFakeEnv(TimedFakeEnv):
            def capture_observation(self):
                observation = self._obs()
                time.sleep(0.05)
                return observation

        with tempfile.TemporaryDirectory() as tmp:
            response = _gateway(
                SlowTimedFakeEnv(Path(tmp)),
                temporal_mode="live_timestamped_execution",
            ).step_from_command('{"action": "screenshot"}')

        self.assertEqual(response["timing"]["frame_captured_at_s"], 0.0)
        self.assertGreaterEqual(response["timing"]["current_time_s"], 0.04)

    def test_execution_mode_requires_an_observation_clock_origin(self):
        env = FakeEnv()
        response = _gateway(
            env, temporal_mode="live_timestamped_execution"
        ).step_from_command(
            '{"action": "left_click", "coordinate": [10, 20], "execute_at_s": 4}'
        )
        self.assertEqual(response["error"], "request a screenshot before using execute_at_s")
        self.assertEqual(env.calls, [])


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

    def test_non_string_action_is_a_normal_retryable_error(self):
        env = FakeEnv()
        gw = _gateway(env)
        resp = gw.step_from_command('{"action": {"action": "screenshot"}}')
        self.assertEqual(resp["error"], "the 'action' value must be a string")
        self.assertEqual(resp["budget_remaining"], 5)
        self.assertFalse(resp["done"])
        self.assertIsNotNone(resp["screenshot_b64"])
        self.assertEqual(len(env.calls), 0)


class BudgetTests(unittest.TestCase):
    def test_budget_exhaustion_blocks_further_steps(self):
        env = FakeEnv(max_steps=2)
        gw = _gateway(env)
        gw.step_from_command('{"action": "wait", "time": 0}')
        r2 = gw.step_from_command('{"action": "wait", "time": 0}')
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
        self.assertTrue(gw.transcript[0]["observation_only"])
        # 1 * 1.5 -> int(1.5) == 1
        self.assertEqual(gw.transcript[1]["env_actions"], [{"mouse": {"left_click": [1, 1]}}])


class ConcurrencyTests(unittest.TestCase):
    def test_concurrent_commands_are_serialized_before_touching_env(self):
        class ConcurrentProbeEnv(FakeEnv):
            def __init__(self):
                super().__init__()
                self.active_captures = 0
                self.max_active_captures = 0
                self.guard = threading.Lock()

            def capture_observation(self):
                with self.guard:
                    self.active_captures += 1
                    self.max_active_captures = max(
                        self.max_active_captures, self.active_captures
                    )
                try:
                    time.sleep(0.1)
                    return self._obs()
                finally:
                    with self.guard:
                        self.active_captures -= 1

        env = ConcurrentProbeEnv()
        gateway = _gateway(env)
        callers_ready = threading.Barrier(3)

        def request_screenshot():
            callers_ready.wait()
            return gateway.step_from_command('{"action": "screenshot"}')

        with ThreadPoolExecutor(max_workers=2) as executor:
            futures = [executor.submit(request_screenshot) for _ in range(2)]
            callers_ready.wait()
            responses = [future.result() for future in futures]

        self.assertEqual(env.max_active_captures, 1)
        self.assertEqual(
            sorted(response["observation"] for response in responses), [0, 1]
        )

    def test_scheduled_wait_does_not_block_an_immediate_action(self):
        with tempfile.TemporaryDirectory() as tmp:
            env = TimedFakeEnv(Path(tmp))
            gateway = _gateway(env, temporal_mode="live_timestamped_execution")
            initial = gateway.step_from_command('{"action": "screenshot"}')
            execute_at_s = initial["timing"]["current_time_s"] + 0.25
            with ThreadPoolExecutor(max_workers=2) as executor:
                scheduled = executor.submit(
                    gateway.step_from_command,
                    json.dumps(
                        {
                            "action": "left_click",
                            "coordinate": [100, 100],
                            "execute_at_s": execute_at_s,
                        }
                    ),
                )
                time.sleep(0.03)
                immediate = executor.submit(
                    gateway.step_from_command,
                    '{"action": "left_click", "coordinate": [200, 200]}',
                )
                immediate.result(timeout=1)
                self.assertFalse(scheduled.done())
                scheduled.result(timeout=1)

        self.assertEqual(
            env.calls,
            [
                [{"mouse": {"left_click": [300, 300]}}],
                [{"mouse": {"left_click": [150, 150]}}],
            ],
        )

    def test_action_lane_runs_while_prior_response_captures(self):
        class LaneProbeEnv(FakeEnv):
            def __init__(self):
                super().__init__()
                self.capture_started = threading.Event()
                self.release_capture = threading.Event()

            def capture_observation(self):
                self.capture_started.set()
                self.release_capture.wait(timeout=2)
                return self._obs()

        env = LaneProbeEnv()
        gateway = _gateway(env)
        with ThreadPoolExecutor(max_workers=2) as executor:
            first = executor.submit(
                gateway.step_from_command,
                '{"action": "left_click", "coordinate": [100, 100]}',
            )
            self.assertTrue(env.capture_started.wait(timeout=1))
            second = executor.submit(
                gateway.step_from_command,
                '{"action": "left_click", "coordinate": [200, 200]}',
            )
            deadline = time.monotonic() + 1
            while len(env.calls) < 2 and time.monotonic() < deadline:
                time.sleep(0.005)
            self.assertEqual(len(env.calls), 2)
            env.release_capture.set()
            first.result(timeout=1)
            second.result(timeout=1)


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
    def test_prompt_contains_task_budget_and_http_contract(self):
        # build_harness_prompt is given the display resolution.
        prompt = build_harness_prompt("Fill the background green.", (1280, 720), 40)
        self.assertIn("Fill the background green.", prompt)
        self.assertIn("at most 40 actions", prompt)
        self.assertIn("HTTP action gateway", prompt)
        self.assertIn("GATEWAY_URL", prompt)
        self.assertIn("GATEWAY_TOKEN", prompt)
        self.assertIn("def computer(action):", prompt)
        self.assertIn("Python functions or programs", prompt)
        self.assertIn("loops, OCR", prompt)
        self.assertIn("optional convenience wrapper", prompt)
        self.assertIn("act '{", prompt)
        self.assertIn("PIXELS", prompt)
        self.assertIn("1280x720", prompt)
        self.assertIn("terminate", prompt)
        self.assertIn("Live modes return exactly one instantaneous frame", prompt)
        self.assertNotIn("Your ONLY way to interact with it is", prompt)
        self.assertNotIn("After EVERY `act` call", prompt)

    def test_prompt_exposes_only_the_selected_temporal_contract(self):
        paused = build_harness_prompt("task", (1280, 720), 10, "paused")
        live = build_harness_prompt("task", (1280, 720), 10, "live")
        timestamped = build_harness_prompt(
            "task", (1280, 720), 10, "live_timestamped"
        )
        execution = build_harness_prompt(
            "task", (1280, 720), 10, "live_timestamped_execution"
        )

        self.assertIn("task clock is paused", paused)
        self.assertIn("task freezes on the final returned frame", paused)
        self.assertIn("next action is applied to that final frame's state", paused)
        self.assertNotIn("execute_at_s", paused)
        self.assertNotIn("task freezes on the final returned frame", live)
        self.assertNotIn("task freezes on the final returned frame", timestamped)
        self.assertNotIn("task freezes on the final returned frame", execution)
        self.assertIn("does not provide clock timestamps", live)
        self.assertNotIn("execute_at_s", live)
        self.assertIn("timing.current_time_s", timestamped)
        self.assertNotIn("execute_at_s", timestamped)
        self.assertIn("execute_at_s", execution)

    def test_act_script_writes_every_observation_frame(self):
        self.assertIn('resp.get("screenshots_b64")', _ACT_SCRIPT)
        self.assertIn("chronological frame(s)", _ACT_SCRIPT)
        self.assertIn("observation_", _ACT_SCRIPT)
        self.assertIn('resp.get("timing")', _ACT_SCRIPT)


if __name__ == "__main__":
    unittest.main()
