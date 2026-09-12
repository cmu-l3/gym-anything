from __future__ import annotations

import unittest
from types import SimpleNamespace
from unittest import mock

from gym_anything.runtime.runners.sandweave import SandweaveRunner
from gym_anything.specs import EnvSpec


class SandweaveRunnerTests(unittest.TestCase):
    def make_runner(self, *, target=None, worker_host="local-host"):
        sdk = mock.Mock(__version__="0.2.6")
        sdk.Template.return_value.resolve.return_value = {"name": "gym-ubuntu"}
        sdk.Sandbox.return_value = SimpleNamespace(
            id="sw-example",
            info={
                "worker": {"hostname": worker_host},
                "vnc": {"port": 59017, "url": "vnc://127.0.0.1:59017", "password": "secret"},
            },
            files=mock.Mock(), run=mock.Mock(), terminate=mock.Mock(), close=mock.Mock(),
        )
        spec = EnvSpec.from_dict({
            "id": "moodle_env@0.1", "runner": "sandweave",
            "resources": {"cpu": 2, "mem_gb": 4, "gpu": 0, "net": True},
        })
        with mock.patch.dict("sys.modules", {"sandweave": sdk}), \
             mock.patch.dict("os.environ", {"GYM_ANYTHING_SANDWEAVE_TARGET": target} if target else {}, clear=True), \
             mock.patch("gym_anything.runtime.runners.sandweave.dependency_status", return_value={"available": True}):
            runner = SandweaveRunner(spec)
        return runner, sdk

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


if __name__ == "__main__":
    unittest.main()
