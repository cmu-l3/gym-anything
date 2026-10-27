from __future__ import annotations

import dataclasses
import json
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

from gym_anything.runtime.runners.sandweave import SandweaveRunner, dependency_status
from gym_anything.specs import EnvSpec


@dataclasses.dataclass(frozen=True)
class Memory:
    """The fields of sandweave.Memory that the runner sets (sandweave>=0.2.28)."""
    guest: str
    runtime: str = "512MiB"
    reservation: str | None = None
    experimental: bool = False


class SandweaveRunnerTests(unittest.TestCase):
    def make_runner(self, *, target=None, worker_host="local-host", runner_options=None, template=None,
                    recording=None):
        sdk = mock.Mock(__version__="0.2.21", Memory=Memory)
        sdk.Template.return_value.resolve.return_value = template or {"name": "gym-ubuntu"}
        sdk.Sandbox.return_value = SimpleNamespace(
            id="sw-example",
            info={
                "worker": {"hostname": worker_host},
                "vnc": {"port": 59017, "url": "vnc://127.0.0.1:59017", "password": "secret"},
            },
            files=mock.Mock(), run=mock.Mock(), terminate=mock.Mock(), close=mock.Mock(),
            recording=mock.Mock(),
        )
        spec = EnvSpec.from_dict({
            "id": "moodle_env@0.1", "runner": "sandweave",
            "resources": {"cpu": 2, "mem_gb": 4, "gpu": 0, "net": True},
            "runner_options": runner_options or {},
            **({"recording": recording} if recording is not None else {}),
        })
        with mock.patch.dict("sys.modules", {"sandweave": sdk}), \
             mock.patch.dict("os.environ", {"GYM_ANYTHING_SANDWEAVE_TARGET": target} if target else {}, clear=True), \
             mock.patch("gym_anything.runtime.runners.sandweave.dependency_status", return_value={"available": True}):
            runner = SandweaveRunner(spec)
        return runner, sdk

    @mock.patch("gym_anything.runtime.runners.sandweave.sys.platform", "linux")
    @mock.patch("gym_anything.runtime.runners.sandweave.sys.version_info", (3, 11))
    def test_requires_release_with_loopback_controller_defaults(self):
        for version, available in [("0.2.20", False), ("0.2.21", True)]:
            with self.subTest(version=version), mock.patch(
                "gym_anything.runtime.runners.sandweave.importlib.metadata.version",
                return_value=version,
            ):
                status = dependency_status()
                self.assertEqual(status["available"], available)
                if not available:
                    self.assertIn("sandweave>=0.2.21 required", status["reason"])

    @mock.patch("gym_anything.runtime.runners.sandweave.socket.gethostname", return_value="local-host")
    def test_cluster_placement_controls_vnc_visibility(self, _hostname):
        for worker_host, visible in [("local-host", True), ("remote-host", False), (None, False)]:
            with self.subTest(worker_host=worker_host):
                runner, sdk = self.make_runner(target="lab", worker_host=worker_host)
                runner.start()
                info = runner.get_runtime_info()
                self.assertEqual(info.instance_name, "sw-example")
                self.assertEqual(info.vnc_port, 59017 if visible else None)
                self.assertEqual(info.vnc_url, "vnc://127.0.0.1:59017" if visible else None)
                self.assertEqual(info.vnc_password, "secret")
                self.assertEqual(sdk.Sandbox.call_args.kwargs["target"], "lab")
                runner.stop()

    @mock.patch("gym_anything.runtime.runners.sandweave.socket.gethostname", return_value="local-host")
    def test_remote_vnc_reports_worker_without_exposing_password(self, _hostname):
        runner, sdk = self.make_runner(target="lab")
        sdk.Sandbox.return_value.info["vnc"]["worker_host"] = "remote-host"
        with self.assertLogs("gym_anything.runtime.runners.sandweave", level="INFO") as logs:
            runner.start()
        self.assertIn("remote-host at 127.0.0.1:59017", logs.output[0])
        self.assertNotIn("secret", logs.output[0])
        self.assertIsNone(runner.get_runtime_info().vnc_port)
        self.assertIsNone(runner.get_runtime_info().vnc_url)
        runner.stop()

    def test_local_target_without_worker_metadata_retains_vnc(self):
        for target in (None, "local"):
            with self.subTest(target=target):
                runner, _ = self.make_runner(target=target, worker_host=None)
                runner.start()
                self.assertEqual(runner.get_runtime_info().vnc_port, 59017)
                runner.stop()

    def test_restores_get_unique_names_without_changing_checkpoint_keys(self):
        runner, sdk = self.make_runner(target="lab")
        runner.set_checkpoint_key("post_start", "create_course")
        key = runner._checkpoint_key()
        base_key = runner._base_key
        runner.start()
        initial = sdk.Sandbox.call_args.kwargs
        runner.stop()
        self.assertTrue(runner.start_from_checkpoint())
        restored = sdk.Sandbox.call_args.kwargs
        self.assertTrue(initial["name"].startswith("moodle_env@0.1-"))
        self.assertTrue(restored["name"].startswith("moodle_env@0.1-"))
        self.assertNotEqual(initial["name"], restored["name"])
        self.assertEqual(initial["cache_key"], base_key)
        self.assertEqual(restored["cache"], key)
        self.assertEqual(restored["target"], "lab")
        self.assertEqual(runner._checkpoint_key(), key)
        self.assertEqual(runner._base_key, base_key)
        runner.stop()

    def test_template_options_are_merged_into_the_runner_template(self):
        _, default_sdk = self.make_runner()
        default_template = default_sdk.Template.call_args.args[0]
        runner, sdk = self.make_runner(runner_options={"template": {"runtime_options": {"cgroup": "v1"}}})
        template = sdk.Template.call_args.args[0]
        self.assertEqual(template["runtime_options"], {"cgroup": "v1"})
        self.assertEqual(template["extends"], default_template["extends"])
        self.assertEqual(template["capabilities"], default_template["capabilities"])
        self.assertNotIn("runtime_options", default_template)

    def test_template_options_are_validated(self):
        def errors(options):
            return SandweaveRunner.validate_options(EnvSpec.from_dict({
                "id": "env", "runner": "sandweave", "runner_options": options}))
        self.assertEqual(errors({}), [])
        self.assertEqual(errors({"template": {"runtime_options": {"cgroup": "v1"}}}), [])
        self.assertEqual(len(errors({"template": "v1"})), 1)
        self.assertEqual(len(errors({"template": {"extends": "other.toml"}})), 1)
        self.assertEqual(len(errors({"cgroup": "v1"})), 1)

    def test_service_network_membership_reaches_every_sandbox(self):
        membership = {"id": "net-" + "a" * 32, "aliases": ["mail.example.test"], "networks": ["office"]}
        runner, sdk = self.make_runner(runner_options={"service_network": membership})
        runner.set_checkpoint_key("post_start", None)
        runner.start()
        started = sdk.Sandbox.call_args.kwargs
        runner.stop()
        runner.start_from_checkpoint()
        restored = sdk.Sandbox.call_args.kwargs
        for kwargs in (started, restored):
            self.assertEqual(kwargs["service_network"], membership["id"])
            self.assertEqual(kwargs["aliases"], ["mail.example.test"])
            self.assertEqual(kwargs["networks"], ["office"])
        runner.stop()
        plain, plain_sdk = self.make_runner()
        plain.start()
        self.assertNotIn("service_network", plain_sdk.Sandbox.call_args.kwargs)
        plain.stop()

    def test_checkpoints_do_not_depend_on_the_episode_network(self):
        keys = []
        for network in ("net-" + "a" * 32, "net-" + "b" * 32):
            runner, _ = self.make_runner(runner_options={"service_network": {"id": network, "networks": ["office"]}})
            runner.set_checkpoint_key("post_start", None)
            keys.append(runner._checkpoint_key())
        self.assertEqual(keys[0], keys[1])

    def test_service_network_needs_a_supporting_sdk(self):
        spec = EnvSpec.from_dict({"id": "env", "runner": "sandweave",
                                  "resources": {"cpu": 2, "mem_gb": 4, "gpu": 0, "net": True},
                                  "runner_options": {"service_network": {"id": "net-" + "a" * 32}}})
        old_sdk = mock.Mock(spec=["Template", "Sandbox", "__version__"])
        with mock.patch.dict("sys.modules", {"sandweave": old_sdk}), \
             mock.patch("gym_anything.runtime.runners.sandweave.dependency_status", return_value={"available": True}):
            with self.assertRaisesRegex(RuntimeError, "sandweave>=0.2.24"):
                SandweaveRunner(spec)

    def test_service_network_options_are_validated(self):
        def errors(membership):
            return SandweaveRunner.validate_options(EnvSpec.from_dict({
                "id": "env", "runner": "sandweave", "runner_options": {"service_network": membership}}))
        self.assertEqual(errors({"id": "net-x", "aliases": ["a.test"], "networks": ["office"]}), [])
        self.assertEqual(len(errors({"aliases": ["a.test"]})), 1)
        self.assertEqual(len(errors({"id": "net-x", "aliases": "a.test"})), 1)
        self.assertEqual(len(errors({"id": "net-x", "ports": [80]})), 1)

    def test_memory_reservation_reaches_every_sandbox(self):
        reserved = {"memory": {"reservation": "2GiB", "experimental": True}}
        template = {"name": "gym-ubuntu", "resources": {"runtime_memory": "4GiB"}}
        runner, sdk = self.make_runner(runner_options=reserved, template=template)
        runner.set_checkpoint_key("post_start", None)
        runner.start()
        started = sdk.Sandbox.call_args.kwargs["memory"]
        runner.stop()
        runner.start_from_checkpoint()
        restored = sdk.Sandbox.call_args.kwargs["memory"]
        runner.stop()
        expected = Memory(guest="4GiB", runtime="4GiB", reservation="2GiB", experimental=True)
        self.assertEqual((started, restored), (expected, expected))
        plain, plain_sdk = self.make_runner()
        plain.start()
        self.assertEqual(plain_sdk.Sandbox.call_args.kwargs["memory"], "4GiB")
        plain.stop()

    def test_checkpoints_do_not_depend_on_the_reservation(self):
        keys = []
        for options in ({}, {"memory": {"reservation": "2GiB", "experimental": True}},
                        {"memory": {"reservation": "3GiB", "experimental": True}}):
            runner, _ = self.make_runner(runner_options=options)
            runner.set_checkpoint_key("post_start", None)
            keys.append(runner._checkpoint_key())
        self.assertEqual(len(set(keys)), 1)

    def test_memory_reservation_needs_a_supporting_sdk(self):
        spec = EnvSpec.from_dict({"id": "env", "runner": "sandweave",
                                  "resources": {"cpu": 2, "mem_gb": 4, "gpu": 0, "net": True},
                                  "runner_options": {"memory": {"reservation": "2GiB", "experimental": True}}})

        @dataclasses.dataclass(frozen=True)
        class OldMemory:
            guest: str
            runtime: str = "512MiB"

        old_sdk = mock.Mock(__version__="0.2.26", Memory=OldMemory)
        with mock.patch.dict("sys.modules", {"sandweave": old_sdk}), \
             mock.patch("gym_anything.runtime.runners.sandweave.dependency_status", return_value={"available": True}):
            with self.assertRaisesRegex(RuntimeError, "sandweave>=0.2.28"):
                SandweaveRunner(spec)

    def test_memory_options_are_validated(self):
        def errors(memory):
            return SandweaveRunner.validate_options(EnvSpec.from_dict({
                "id": "env", "runner": "sandweave", "runner_options": {"memory": memory}}))
        self.assertEqual(errors({"reservation": "2GiB", "experimental": True}), [])
        self.assertEqual(errors({"reservation": 2 * 1024**3, "experimental": True}), [])
        self.assertEqual(len(errors({"reservation": "2GiB"})), 1)
        self.assertEqual(len(errors({"reservation": "2GiB", "experimental": False})), 1)
        self.assertEqual(len(errors({"reservation": "2GiB", "experimental": True, "guest": "8GiB"})), 1)
        self.assertEqual(len(errors({"experimental": True})), 1)
        self.assertEqual(len(errors({"reservation": True, "experimental": True})), 1)
        self.assertEqual(len(errors("2GiB")), 1)

    def test_recording_follows_the_recording_spec(self):
        runner, sdk = self.make_runner(recording={"enable": False})
        runner.start()
        self.assertIs(sdk.Sandbox.call_args.kwargs["recording"], False)
        runner.stop()
        runner, sdk = self.make_runner(recording={"enable": True, "video_fps": 10})
        runner.start()
        sdk.Recording.assert_called_once_with(fps=10)
        self.assertIs(sdk.Sandbox.call_args.kwargs["recording"], sdk.Recording.return_value)
        self.assertTrue(runner.supports_native_recording())
        runner.stop()

    def test_native_recording_downloads_before_cleanup(self):
        runner, sdk = self.make_runner(recording={"enable": True, "video_fps": 10})
        sandbox = sdk.Sandbox.return_value
        with tempfile.TemporaryDirectory() as directory:
            episode = Path(directory)
            runner.on_episode_start({"episode_dir": str(episode)})

            def download(destination):
                self.assertFalse(sandbox.terminate.called)
                (destination / "segment").mkdir()
                (destination / "segment" / "video.mp4").write_bytes(b"recorded-video")
                (destination / "recording.json").write_text(json.dumps({"segments": [{"id": "segment"}]}))

            sandbox.recording.download.side_effect = download
            runner.start()
            runner.stop()
            runner.stop()
            self.assertEqual((episode / "recording.mp4").read_bytes(), b"recorded-video")
            self.assertTrue((episode / "sandweave-recording" / "recording.json").is_file())
        sandbox.recording.download.assert_called_once()
        sandbox.terminate.assert_called_once()
        sandbox.close.assert_called_once()

    def test_native_download_failure_is_reported_and_guest_is_released(self):
        runner, sdk = self.make_runner(recording={"enable": True})
        sandbox = sdk.Sandbox.return_value
        with tempfile.TemporaryDirectory() as directory:
            runner.on_episode_start({"episode_dir": directory})
            runner.start()
            sandbox.recording.download.side_effect = IOError("download failed")
            with self.assertRaisesRegex(IOError, "download failed"):
                runner.stop()
        self.assertIsNone(runner._sandbox)
        sandbox.terminate.assert_called_once()
        sandbox.close.assert_called_once()
        sandbox.recording.delete.assert_not_called()

    def test_core_does_not_replace_native_video_with_step_frames(self):
        from gym_anything.env import GymAnythingEnv

        runner, _ = self.make_runner(recording={"enable": True})
        env = GymAnythingEnv.__new__(GymAnythingEnv)
        env._runner = runner
        env.env_spec = runner.spec
        env._recorder = None
        env._rec_handle = None
        with tempfile.TemporaryDirectory() as directory, \
             mock.patch("gym_anything.env.assemble_step_video", side_effect=AssertionError("step-frame fallback")):
            env._episode_dir = Path(directory)
            env._ensure_recording_artifact()
        with self.assertRaisesRegex(NotImplementedError, "sandbox lifecycle"):
            env.pause_recording()
        with self.assertRaisesRegex(NotImplementedError, "sandbox lifecycle"):
            env.resume_recording()


if __name__ == "__main__":
    unittest.main()
