from __future__ import annotations

import base64
import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from gym_anything.api import from_config
from gym_anything.env import GymAnythingEnv
from gym_anything.config.validators import validate_env_spec
from gym_anything.runtime.recording.frames import assemble_step_video
from gym_anything.specs import EnvSpec, TaskSpec


_PNG_BYTES = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9p2X2xkAAAAASUVORK5CYII="
)


class _FakeRunner:
    def __init__(self) -> None:
        self.start_calls = 0
        self.stop_calls = 0
        self.exec_commands = []
        self.injected_actions = []

    def start(self, seed=None) -> None:
        self.start_calls += 1

    def stop(self) -> None:
        self.stop_calls += 1

    def run_reset(self, reset_script: str, seed=None) -> None:
        return None

    def run_task_init(self, init_script: str) -> None:
        return None

    def inject_action(self, action) -> None:
        self.injected_actions.append(action)
        return None

    def capture_observation(self):
        return {"screen": {"path": "synthetic.png"}}

    def supports_live_recording(self) -> bool:
        return False

    def exec(self, command: str, **kwargs) -> int:
        self.exec_commands.append(command)
        return 0

    def exec_capture(self, command: str) -> str:
        return ""

    def exec_capture_bytes(self, command: str) -> bytes:
        return b""

    def capture_screenshot(self, host_path) -> bool:
        Path(host_path).write_bytes(_PNG_BYTES)
        return True

    def capture_audio_raw(self, duration_sec: float, rate: int, channels: int) -> bytes:
        return b""

    def copy_to(self, host_src: str, container_dst: str) -> None:
        return None

    def copy_from(self, container_src: str, host_dst: str) -> None:
        return None

    def put_file(self, host_path) -> str:
        return str(host_path)

    def set_checkpoint_key(self, cache_level: str, task_id=None, use_savevm: bool = False) -> None:
        return None

    def checkpoint_exists(self) -> bool:
        return False

    def create_checkpoint(self) -> bool:
        return False

    def start_from_checkpoint(self, seed=None) -> bool:
        return False


class _FakeVerifier:
    def evaluate(self, **kwargs):
        return {"passed": True, "score": 100}


class _PartialScoreVerifier:
    def __init__(self, score: float) -> None:
        self.score = score

    def evaluate(self, **kwargs):
        return {"passed": self.score > 0, "score": self.score}


def _make_env_spec(output_dir: str, *, runner: str | None = None, recording: bool = False) -> EnvSpec:
    data = {
        "id": "demo-env",
        "observation": [{"type": "rgb_screen", "fps": 1, "resolution": [64, 64]}],
        "action": [{"type": "mouse"}],
        "recording": {"enable": recording, "output_dir": output_dir, "video_fps": 4},
    }
    if runner is not None:
        data["runner"] = runner
    return EnvSpec.from_dict(data)


class RuntimeBehaviorTests(unittest.TestCase):
    def test_step_handles_wait_control_action_inside_env(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            runner = _FakeRunner()
            with mock.patch.object(GymAnythingEnv, "_select_runner", return_value=runner):
                env = GymAnythingEnv(_make_env_spec(tmp), None)

            try:
                env.reset(seed=1)
                with mock.patch("gym_anything.env.time.sleep") as sleep_mock:
                    obs, reward, done, info = env.step([{"action": "wait", "time": 1.5}])

                self.assertTrue(Path(obs["screen"]["path"]).exists())
                self.assertEqual(reward, 0.0)
                self.assertFalse(done)
                self.assertEqual(info["action_result"]["action"], "wait")
                self.assertEqual(info["action_result"]["output"], "Waited for 1.5 seconds")
                self.assertEqual(runner.injected_actions, [])
                sleep_mock.assert_called_once_with(1.5)
            finally:
                env.close()

    def test_step_handles_screenshot_control_action_inside_env(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            runner = _FakeRunner()
            with mock.patch.object(GymAnythingEnv, "_select_runner", return_value=runner):
                env = GymAnythingEnv(_make_env_spec(tmp), None)

            try:
                env.reset(seed=1)
                obs, reward, done, info = env.step([{"action": "screenshot"}])

                self.assertTrue(Path(obs["screen"]["path"]).exists())
                self.assertEqual(reward, 0.0)
                self.assertFalse(done)
                self.assertEqual(info["action_result"]["action"], "screenshot")
                self.assertEqual(info["action_result"]["output"], obs["screen"]["path"])
                self.assertEqual(runner.injected_actions, [])
            finally:
                env.close()

    def test_close_runs_post_task_hook_for_unfinished_episode(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            runner = _FakeRunner()
            task_spec = TaskSpec.from_dict(
                {
                    "id": "demo-task",
                    "hooks": {"post_task": "echo exported"},
                    "success": {"mode": "program", "spec": {"program": "verifier.py::verify"}},
                }
            )
            with mock.patch.object(GymAnythingEnv, "_select_runner", return_value=runner):
                env = GymAnythingEnv(_make_env_spec(tmp), task_spec)
            env._verifier = _FakeVerifier()

            env.reset(seed=1)
            env.close()

            self.assertIn(
                "bash -lc echo exported > /home/ga/task_post_task.log 2>&1",
                runner.exec_commands,
            )
            self.assertEqual(runner.stop_calls, 1)

    def test_close_without_post_task_hook_does_not_sleep(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            runner = _FakeRunner()
            with mock.patch.object(GymAnythingEnv, "_select_runner", return_value=runner):
                env = GymAnythingEnv(_make_env_spec(tmp), None)
            env._verifier = _FakeVerifier()

            env.reset(seed=1)
            with mock.patch("gym_anything.env.time.sleep") as sleep_mock:
                env.close()

            sleep_mock.assert_not_called()
            self.assertEqual(runner.stop_calls, 1)

    def test_reset_reuses_env_by_closing_previous_episode_first(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            runner = _FakeRunner()
            with mock.patch.object(GymAnythingEnv, "_select_runner", return_value=runner):
                env = GymAnythingEnv(_make_env_spec(tmp), None)
            env._verifier = _FakeVerifier()

            env.reset(seed=1)
            first_episode_dir = env.episode_dir
            env.reset(seed=2)
            second_episode_dir = env.episode_dir
            env.close()

            self.assertEqual(runner.start_calls, 2)
            self.assertEqual(runner.stop_calls, 2)
            self.assertNotEqual(first_episode_dir, second_episode_dir)

    def test_public_session_info_is_populated_after_reset(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            env = GymAnythingEnv(_make_env_spec(tmp, runner="local"), None)

            try:
                env.reset(seed=1)
                session = env.get_session_info()
                self.assertIsNotNone(session)
                self.assertEqual(session.runner_name, "LocalRunner")
                self.assertEqual(session.platform_family, "linux")
                self.assertEqual(session.resolution, (64, 64))
                self.assertEqual(session.artifacts_dir, str(env.episode_dir))
            finally:
                env.close()

    def test_frame_video_assembly_uses_ffmpeg_when_available(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            episode_dir = Path(tmp)
            for idx in range(2):
                (episode_dir / f"frame_{idx:05d}.png").write_bytes(_PNG_BYTES)

            def _run_side_effect(cmd, capture_output, text):
                Path(cmd[-1]).write_bytes(b"mp4")
                completed = mock.Mock()
                completed.returncode = 0
                completed.stdout = ""
                completed.stderr = ""
                return completed

            with mock.patch("gym_anything.runtime.recording.frames.shutil.which", return_value="/usr/bin/ffmpeg"), \
                 mock.patch("gym_anything.runtime.recording.frames.subprocess.run", side_effect=_run_side_effect) as run_mock:
                out_path = assemble_step_video(episode_dir, fps=4)

            self.assertEqual(out_path, episode_dir / "recording.mp4")
            self.assertEqual(run_mock.call_args.args[0][0], "/usr/bin/ffmpeg")
            self.assertTrue(any(arg.endswith("frame_%05d.png") for arg in run_mock.call_args.args[0]))

    def test_network_allowlist_is_ignored_for_backward_compat(self) -> None:
        spec = EnvSpec.from_dict(
            {
                "id": "demo-env",
                "observation": [{"type": "rgb_screen"}],
                "action": [{"type": "mouse"}],
                "security": {"network_allowlist": ["example.com"]},
            }
        )

        validate_env_spec(spec)
        self.assertEqual(spec.security.ignored_fields["network_allowlist"], ["example.com"])

    def test_secrets_ref_loads_into_runtime_security_env(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "secrets.env").write_text("API_TOKEN=secret-token\n", encoding="utf-8")
            (root / "env.json").write_text(
                json.dumps(
                    {
                        "id": "demo-env",
                        "observation": [{"type": "rgb_screen"}],
                        "action": [{"type": "mouse"}],
                        "security": {"secrets_ref": "secrets.env"},
                    }
                ),
                encoding="utf-8",
            )

            env = from_config(root)
            try:
                self.assertEqual(env.env_spec.security.resolved_env["API_TOKEN"], "secret-token")
            finally:
                env.close()

    def test_partial_reward_uses_verifier_score(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            runner = _FakeRunner()
            task_spec = TaskSpec.from_dict(
                {
                    "id": "demo-task",
                    "init": {"reward_type": "partial"},
                    "success": {"mode": "program", "spec": {"program": "verifier.py::verify"}},
                }
            )
            with mock.patch.object(GymAnythingEnv, "_select_runner", return_value=runner):
                env = GymAnythingEnv(_make_env_spec(tmp), task_spec)
            env._verifier = _PartialScoreVerifier(37)

            try:
                env.reset(seed=1)
                _, reward, done, info = env.step([], mark_done=True)
                self.assertTrue(done)
                self.assertEqual(reward, 37.0)
                self.assertEqual(info["verifier"]["score"], 37)
            finally:
                env.close()

    def test_continuous_reward_normalizes_verifier_score(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            runner = _FakeRunner()
            task_spec = TaskSpec.from_dict(
                {
                    "id": "demo-task",
                    "init": {"reward_type": "continuous"},
                    "success": {"mode": "program", "spec": {"program": "verifier.py::verify"}},
                }
            )
            with mock.patch.object(GymAnythingEnv, "_select_runner", return_value=runner):
                env = GymAnythingEnv(_make_env_spec(tmp), task_spec)
            env._verifier = _PartialScoreVerifier(37)

            try:
                env.reset(seed=1)
                _, reward, done, _ = env.step([], mark_done=True)
                self.assertTrue(done)
                self.assertAlmostEqual(reward, 0.37)
            finally:
                env.close()

    def test_local_runner_rejects_checkpoint_caching(self) -> None:
        env = GymAnythingEnv(_make_env_spec("./artifacts", runner="local"), None)

        with self.assertRaisesRegex(ValueError, "does not support checkpoint caching"):
            env.reset(use_cache=True)


if __name__ == "__main__":
    unittest.main()
