from __future__ import annotations

import unittest

from gym_anything.contracts import RunnerRuntimeInfo, SessionInfo


class RunnerRuntimeInfoTests(unittest.TestCase):
    # ------------------------------------------------------------------ basics
    def test_minimal_construction(self) -> None:
        info = RunnerRuntimeInfo(platform_family="linux")
        self.assertEqual(info.platform_family, "linux")
        self.assertIsNone(info.container_name)
        self.assertIsNone(info.instance_name)
        self.assertIsNone(info.vnc_port)
        self.assertIsNone(info.vnc_password)
        self.assertIsNone(info.ssh_port)
        self.assertIsNone(info.ssh_user)
        self.assertIsNone(info.ssh_password)

    def test_full_construction(self) -> None:
        info = RunnerRuntimeInfo(
            platform_family="windows",
            container_name="my_container",
            instance_name="my_instance",
            vnc_port=5900,
            vnc_password="secret",
            ssh_port=22,
            ssh_user="admin",
            ssh_password="pass123",
        )
        self.assertEqual(info.platform_family, "windows")
        self.assertEqual(info.container_name, "my_container")
        self.assertEqual(info.instance_name, "my_instance")
        self.assertEqual(info.vnc_port, 5900)
        self.assertEqual(info.vnc_password, "secret")
        self.assertEqual(info.ssh_port, 22)
        self.assertEqual(info.ssh_user, "admin")
        self.assertEqual(info.ssh_password, "pass123")

    def test_platform_family_android(self) -> None:
        info = RunnerRuntimeInfo(platform_family="android")
        self.assertEqual(info.platform_family, "android")

    def test_platform_family_unknown(self) -> None:
        info = RunnerRuntimeInfo(platform_family="unknown")
        self.assertEqual(info.platform_family, "unknown")

    # ----------------------------------------------------------------- to_dict
    def test_to_dict_minimal(self) -> None:
        info = RunnerRuntimeInfo(platform_family="linux")
        d = info.to_dict()
        self.assertEqual(d["platform_family"], "linux")
        self.assertIsNone(d["container_name"])
        self.assertIsNone(d["vnc_port"])
        self.assertIsNone(d["ssh_user"])

    def test_to_dict_full(self) -> None:
        info = RunnerRuntimeInfo(
            platform_family="windows",
            container_name="c1",
            vnc_port=5901,
            ssh_port=2222,
            ssh_user="user",
        )
        d = info.to_dict()
        self.assertEqual(d["platform_family"], "windows")
        self.assertEqual(d["container_name"], "c1")
        self.assertEqual(d["vnc_port"], 5901)
        self.assertEqual(d["ssh_port"], 2222)
        self.assertEqual(d["ssh_user"], "user")

    def test_to_dict_returns_dict_type(self) -> None:
        info = RunnerRuntimeInfo(platform_family="linux")
        self.assertIsInstance(info.to_dict(), dict)

    # -------------------------------------------------------------- immutability
    def test_is_frozen(self) -> None:
        info = RunnerRuntimeInfo(platform_family="linux")
        with self.assertRaises((AttributeError, TypeError)):
            info.platform_family = "windows"  # type: ignore[misc]


class SessionInfoTests(unittest.TestCase):
    BASE = {
        "env_id": "demo-env",
        "task_id": "demo-task",
        "runner_name": "docker",
        "platform_family": "linux",
    }

    # ------------------------------------------------------------------ basics
    def test_minimal_construction(self) -> None:
        info = SessionInfo(
            env_id="e1",
            task_id=None,
            runner_name="local",
            platform_family="linux",
        )
        self.assertEqual(info.env_id, "e1")
        self.assertIsNone(info.task_id)
        self.assertEqual(info.runner_name, "local")
        self.assertFalse(info.systemd_enabled)

    def test_full_construction(self) -> None:
        info = SessionInfo(
            env_id="e1",
            task_id="t1",
            runner_name="qemu",
            platform_family="linux",
            artifacts_dir="/tmp/artifacts",
            resolution=(1920, 1080),
            fps=30,
            network_enabled=True,
            systemd_enabled=True,
            vnc_port=5900,
            vnc_url="vnc://localhost:5900",
            ssh_port=22,
            ssh_user="ga",
            ssh_password="pw",
        )
        self.assertEqual(info.resolution, (1920, 1080))
        self.assertTrue(info.systemd_enabled)
        self.assertEqual(info.fps, 30)

    # ----------------------------------------------------------------- to_dict
    def test_to_dict_minimal(self) -> None:
        info = SessionInfo(
            env_id="e1",
            task_id=None,
            runner_name="local",
            platform_family="linux",
        )
        d = info.to_dict()
        self.assertEqual(d["env_id"], "e1")
        self.assertIsNone(d["task_id"])
        self.assertIsNone(d["resolution"])

    def test_to_dict_resolution_is_list(self) -> None:
        info = SessionInfo(
            env_id="e1",
            task_id=None,
            runner_name="local",
            platform_family="linux",
            resolution=(1280, 720),
        )
        d = info.to_dict()
        self.assertEqual(d["resolution"], [1280, 720])
        self.assertIsInstance(d["resolution"], list)

    def test_to_dict_resolution_none_stays_none(self) -> None:
        info = SessionInfo(
            env_id="e1",
            task_id=None,
            runner_name="local",
            platform_family="linux",
        )
        d = info.to_dict()
        self.assertIsNone(d["resolution"])

    def test_to_dict_returns_dict_type(self) -> None:
        info = SessionInfo(
            env_id="e1",
            task_id=None,
            runner_name="local",
            platform_family="linux",
        )
        self.assertIsInstance(info.to_dict(), dict)

    # --------------------------------------------------------------- from_dict
    def test_from_dict_minimal(self) -> None:
        info = SessionInfo.from_dict(self.BASE)
        self.assertEqual(info.env_id, "demo-env")
        self.assertEqual(info.task_id, "demo-task")
        self.assertEqual(info.runner_name, "docker")
        self.assertEqual(info.platform_family, "linux")
        self.assertFalse(info.systemd_enabled)

    def test_from_dict_resolution_list(self) -> None:
        data = {**self.BASE, "resolution": [1920, 1080]}
        info = SessionInfo.from_dict(data)
        self.assertEqual(info.resolution, (1920, 1080))

    def test_from_dict_resolution_tuple(self) -> None:
        data = {**self.BASE, "resolution": (800, 600)}
        info = SessionInfo.from_dict(data)
        self.assertEqual(info.resolution, (800, 600))

    def test_from_dict_resolution_none(self) -> None:
        info = SessionInfo.from_dict(self.BASE)
        self.assertIsNone(info.resolution)

    def test_from_dict_resolution_invalid_non_numeric(self) -> None:
        # Non-numeric values → resolution should fall back to None
        data = {**self.BASE, "resolution": ["wide", "tall"]}
        info = SessionInfo.from_dict(data)
        self.assertIsNone(info.resolution)

    def test_from_dict_resolution_wrong_length(self) -> None:
        # Wrong-length list → resolution should fall back to None
        data = {**self.BASE, "resolution": [1920]}
        info = SessionInfo.from_dict(data)
        self.assertIsNone(info.resolution)

    def test_from_dict_invalid_platform_family_defaults_to_unknown(self) -> None:
        data = {**self.BASE, "platform_family": "haiku"}
        info = SessionInfo.from_dict(data)
        self.assertEqual(info.platform_family, "unknown")

    def test_from_dict_platform_family_windows(self) -> None:
        data = {**self.BASE, "platform_family": "windows"}
        info = SessionInfo.from_dict(data)
        self.assertEqual(info.platform_family, "windows")

    def test_from_dict_platform_family_android(self) -> None:
        data = {**self.BASE, "platform_family": "android"}
        info = SessionInfo.from_dict(data)
        self.assertEqual(info.platform_family, "android")

    def test_from_dict_platform_family_unknown(self) -> None:
        data = {**self.BASE, "platform_family": "unknown"}
        info = SessionInfo.from_dict(data)
        self.assertEqual(info.platform_family, "unknown")

    def test_from_dict_missing_env_id_defaults_to_empty_string(self) -> None:
        data = {
            "task_id": "t1",
            "runner_name": "local",
            "platform_family": "linux",
        }
        info = SessionInfo.from_dict(data)
        self.assertEqual(info.env_id, "")

    def test_from_dict_missing_runner_name_defaults_to_empty_string(self) -> None:
        data = {
            "env_id": "e1",
            "task_id": None,
            "platform_family": "linux",
        }
        info = SessionInfo.from_dict(data)
        self.assertEqual(info.runner_name, "")

    def test_from_dict_systemd_enabled_true(self) -> None:
        data = {**self.BASE, "systemd_enabled": True}
        info = SessionInfo.from_dict(data)
        self.assertTrue(info.systemd_enabled)

    def test_from_dict_systemd_enabled_false_by_default(self) -> None:
        info = SessionInfo.from_dict(self.BASE)
        self.assertFalse(info.systemd_enabled)

    def test_from_dict_optional_fields_preserved(self) -> None:
        data = {
            **self.BASE,
            "artifacts_dir": "/artifacts",
            "fps": 60,
            "network_enabled": False,
            "vnc_port": 5900,
            "vnc_url": "vnc://localhost:5900",
            "vnc_password": "pw",
            "ssh_port": 22,
            "ssh_user": "ga",
            "ssh_password": "secret",
            "container_name": "c1",
            "instance_name": "i1",
        }
        info = SessionInfo.from_dict(data)
        self.assertEqual(info.artifacts_dir, "/artifacts")
        self.assertEqual(info.fps, 60)
        self.assertFalse(info.network_enabled)
        self.assertEqual(info.vnc_port, 5900)
        self.assertEqual(info.vnc_url, "vnc://localhost:5900")
        self.assertEqual(info.container_name, "c1")
        self.assertEqual(info.instance_name, "i1")

    # -------------------------------------------- round-trip to_dict/from_dict
    def test_roundtrip_minimal(self) -> None:
        original = SessionInfo(
            env_id="e1",
            task_id=None,
            runner_name="local",
            platform_family="linux",
        )
        restored = SessionInfo.from_dict(original.to_dict())
        self.assertEqual(restored.env_id, original.env_id)
        self.assertEqual(restored.runner_name, original.runner_name)
        self.assertEqual(restored.platform_family, original.platform_family)
        self.assertIsNone(restored.resolution)

    def test_roundtrip_with_resolution(self) -> None:
        original = SessionInfo(
            env_id="e2",
            task_id="t2",
            runner_name="qemu",
            platform_family="linux",
            resolution=(1920, 1080),
            fps=30,
        )
        restored = SessionInfo.from_dict(original.to_dict())
        self.assertEqual(restored.resolution, (1920, 1080))
        self.assertEqual(restored.fps, 30)

    # -------------------------------------------------------------- immutability
    def test_is_frozen(self) -> None:
        info = SessionInfo(
            env_id="e1",
            task_id=None,
            runner_name="local",
            platform_family="linux",
        )
        with self.assertRaises((AttributeError, TypeError)):
            info.env_id = "changed"  # type: ignore[misc]


if __name__ == "__main__":
    unittest.main()
