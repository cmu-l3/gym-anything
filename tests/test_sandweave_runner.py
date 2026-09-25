from __future__ import annotations

import unittest
from types import SimpleNamespace
from unittest import mock

from gym_anything.runtime.runners.sandweave import SandweaveRunner, dependency_status
from gym_anything.specs import EnvSpec


class SandweaveRunnerTests(unittest.TestCase):
    def make_runner(self, *, target=None, worker_host="local-host", runner_options=None):
        sdk = mock.Mock(__version__="0.2.21")
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
            "runner_options": runner_options or {},
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
            with self.subTest(version=version), mock.patch.dict(
                "sys.modules", {"sandweave.releases": SimpleNamespace(host_info=lambda: {})}
            ), mock.patch(
                "gym_anything.runtime.runners.sandweave.importlib.metadata.version",
                return_value=version,
            ):
                status = dependency_status()
                self.assertEqual(status["available"], available)
                if not available:
                    self.assertIn("sandweave>=0.2.21 required", status["reason"])

    @mock.patch("gym_anything.runtime.runners.sandweave.sys.platform", "linux")
    @mock.patch("gym_anything.runtime.runners.sandweave.sys.version_info", (3, 11))
    @mock.patch("gym_anything.runtime.runners.sandweave.importlib.metadata.version", return_value="0.2.21")
    def test_doctor_checks_local_worker_using_installed_sdk(self, _version):
        from gym_anything.doctor import run_doctor
        for error in (None, ValueError("requires Linux 5.4 or newer (found 5.3.0)"),
                      ValueError("Linux x86-64 workers required")):
            with self.subTest(error=error):
                probe = mock.Mock(side_effect=error, return_value={})
                with mock.patch.dict("sys.modules", {"sandweave.releases": SimpleNamespace(host_info=probe)}), \
                     mock.patch.dict("os.environ", {}, clear=True):
                    report = run_doctor(runner="sandweave")
                self.assertEqual(report.ok, error is None)
                probe.assert_called_once_with()
                if error:
                    self.assertIn(str(error), report.checks[-1].detail)

    @mock.patch("gym_anything.runtime.runners.sandweave.sys.platform", "linux")
    @mock.patch("gym_anything.runtime.runners.sandweave.sys.version_info", (3, 11))
    @mock.patch("gym_anything.runtime.runners.sandweave.importlib.metadata.version", return_value="0.2.21")
    def test_remote_target_does_not_check_client_kernel(self, _version):
        for target in ("lab", "ssh://user@worker", "http://worker:8080"):
            with self.subTest(target=target):
                probe = mock.Mock(side_effect=AssertionError("client is not the worker"))
                with mock.patch.dict("sys.modules", {"sandweave.releases": SimpleNamespace(host_info=probe)}), \
                     mock.patch.dict("os.environ", {"GYM_ANYTHING_SANDWEAVE_TARGET": target}, clear=True):
                    self.assertTrue(dependency_status()["available"])
                probe.assert_not_called()

    @mock.patch("gym_anything.runtime.runners.sandweave.sys.platform", "linux")
    @mock.patch("gym_anything.runtime.runners.sandweave.sys.version_info", (3, 11))
    def test_doctor_cli_with_real_sdk_kernel_check(self):
        import contextlib
        import io
        import json
        try:
            from sandweave import releases
        except ImportError:
            self.skipTest("optional Sandweave SDK is not installed")
        from gym_anything.cli import cmd_doctor

        args = SimpleNamespace(runner="sandweave", verification_root=None, json=True)
        supports_linux54 = getattr(releases, "MINIMUM_KERNEL", (5, 6, 0)) <= (5, 4, 0)
        for kernel, target, expected in [("5.3.0-46-generic", "local", 1),
                                          ("5.4.0-216-generic", "local", 0 if supports_linux54 else 1),
                                          ("5.6.0", "local", 0),
                                          ("5.14.0", "local", 0),
                                          ("5.3.0-46-generic", "lab", 0)]:
            with self.subTest(kernel=kernel, target=target), \
                 mock.patch.dict("os.environ", {"GYM_ANYTHING_SANDWEAVE_TARGET": target}, clear=True), \
                 mock.patch.object(releases.platform, "system", return_value="Linux"), \
                 mock.patch.object(releases.platform, "machine", return_value="x86_64"), \
                 mock.patch.object(releases.platform, "release", return_value=kernel), \
                 contextlib.redirect_stdout(io.StringIO()) as output:
                self.assertEqual(cmd_doctor(args), expected)
                report = json.loads(output.getvalue())
                self.assertEqual(report["ok"], expected == 0)
                if expected:
                    self.assertIn("Linux", report["checks"][-1]["detail"])

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


if __name__ == "__main__":
    unittest.main()
