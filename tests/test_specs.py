from __future__ import annotations

import unittest

from gym_anything.specs import (
    ADBSpec,
    ActionSpec,
    ApptainerSpec,
    AVDSpec,
    EnvSpec,
    MountSpec,
    ObservationSpec,
    RecordingSpec,
    RuntimeResources,
    SecuritySpec,
    SSHSpec,
    TaskHooks,
    TaskInitSpec,
    TaskSpec,
    TaskSuccessSpec,
    UserAccount,
    UserPermissions,
    VNCSpec,
)


class TestObservationSpec(unittest.TestCase):
    def test_defaults(self):
        obs = ObservationSpec(type="rgb_screen")
        self.assertEqual(obs.type, "rgb_screen")
        self.assertIsNone(obs.fps)
        self.assertIsNone(obs.resolution)
        self.assertFalse(obs.inline)

    def test_with_fields(self):
        obs = ObservationSpec(type="audio_waveform", sample_rate=16000, channels=1)
        self.assertEqual(obs.sample_rate, 16000)
        self.assertEqual(obs.channels, 1)


class TestActionSpec(unittest.TestCase):
    def test_defaults(self):
        act = ActionSpec(type="mouse")
        self.assertEqual(act.type, "mouse")
        self.assertIsNone(act.events)
        self.assertIsNone(act.encoding)

    def test_with_events(self):
        act = ActionSpec(type="keyboard", events=["keydown", "keyup"])
        self.assertEqual(act.events, ["keydown", "keyup"])


class TestRuntimeResources(unittest.TestCase):
    def test_all_none_by_default(self):
        r = RuntimeResources()
        self.assertIsNone(r.cpu)
        self.assertIsNone(r.mem_gb)
        self.assertIsNone(r.gpu)
        self.assertIsNone(r.net)

    def test_with_values(self):
        r = RuntimeResources(cpu=4.0, mem_gb=8, gpu=1, net=True)
        self.assertEqual(r.cpu, 4.0)
        self.assertEqual(r.mem_gb, 8)
        self.assertEqual(r.gpu, 1)
        self.assertTrue(r.net)


class TestMountSpec(unittest.TestCase):
    def test_default_mode_is_ro(self):
        m = MountSpec(target="/mnt/data", source="/host/data")
        self.assertEqual(m.mode, "ro")

    def test_rw_mode(self):
        m = MountSpec(target="/mnt/out", source="/host/out", mode="rw")
        self.assertEqual(m.mode, "rw")


class TestUserPermissions(unittest.TestCase):
    def test_defaults(self):
        p = UserPermissions()
        self.assertFalse(p.sudo)
        self.assertFalse(p.sudo_nopasswd)
        self.assertEqual(p.shell, "/bin/bash")
        self.assertEqual(p.groups, [])
        self.assertTrue(p.network_access)
        self.assertTrue(p.create_home)

    def test_custom_values(self):
        p = UserPermissions(sudo=True, groups=["docker", "audio"], max_processes=50)
        self.assertTrue(p.sudo)
        self.assertEqual(p.groups, ["docker", "audio"])
        self.assertEqual(p.max_processes, 50)


class TestUserAccount(unittest.TestCase):
    def test_admin_user_factory(self):
        u = UserAccount.admin_user("alice", password="secret")
        self.assertEqual(u.name, "alice")
        self.assertEqual(u.password, "secret")
        self.assertEqual(u.role, "admin")
        self.assertTrue(u.permissions.sudo)
        self.assertTrue(u.permissions.sudo_nopasswd)
        self.assertIn("docker", u.permissions.groups)

    def test_developer_user_factory(self):
        u = UserAccount.developer_user("bob")
        self.assertEqual(u.role, "developer")
        self.assertTrue(u.permissions.sudo)
        self.assertFalse(u.permissions.sudo_nopasswd)
        self.assertIn("docker", u.permissions.groups)

    def test_guest_user_factory(self):
        u = UserAccount.guest_user("carol")
        self.assertEqual(u.role, "guest")
        self.assertFalse(u.permissions.sudo)
        self.assertEqual(u.permissions.max_processes, 50)

    def test_service_user_factory(self):
        u = UserAccount.service_user("svc")
        self.assertEqual(u.role, "service")
        self.assertFalse(u.permissions.sudo)
        self.assertTrue(u.permissions.system_user)
        self.assertFalse(u.permissions.login_shell)
        self.assertFalse(u.permissions.create_home)
        self.assertEqual(u.permissions.shell, "/bin/false")


class TestSecuritySpec(unittest.TestCase):
    def test_defaults(self):
        s = SecuritySpec()
        self.assertEqual(s.user, "1000:1000")
        self.assertEqual(s.cap_drop, ["ALL"])
        self.assertEqual(s.cap_add, [])
        self.assertFalse(s.privileged)

    def test_with_capabilities(self):
        s = SecuritySpec(cap_add=["NET_ADMIN"], privileged=True)
        self.assertIn("NET_ADMIN", s.cap_add)
        self.assertTrue(s.privileged)


class TestRecordingSpec(unittest.TestCase):
    def test_defaults(self):
        r = RecordingSpec()
        self.assertTrue(r.enable)
        self.assertEqual(r.output_dir, "./artifacts")
        self.assertEqual(r.video_fps, 10)
        self.assertEqual(r.video_codec, "libx264")
        self.assertEqual(r.audio_rate, 16000)

    def test_custom_fps(self):
        r = RecordingSpec(video_fps=30, video_crf=18)
        self.assertEqual(r.video_fps, 30)
        self.assertEqual(r.video_crf, 18)


class TestVNCSpec(unittest.TestCase):
    def test_defaults(self):
        v = VNCSpec()
        self.assertFalse(v.enable)
        self.assertEqual(v.host_port, 5901)
        self.assertFalse(v.view_only)

    def test_enabled_with_password(self):
        v = VNCSpec(enable=True, password="pass123")
        self.assertTrue(v.enable)
        self.assertEqual(v.password, "pass123")


class TestSSHSpec(unittest.TestCase):
    def test_defaults(self):
        s = SSHSpec()
        self.assertEqual(s.user, "root")
        self.assertEqual(s.port, 22)
        self.assertEqual(s.shell, "bash")

    def test_custom(self):
        s = SSHSpec(user="ubuntu", port=2222, shell="powershell")
        self.assertEqual(s.user, "ubuntu")
        self.assertEqual(s.port, 2222)
        self.assertEqual(s.shell, "powershell")


class TestADBSpec(unittest.TestCase):
    def test_defaults(self):
        a = ADBSpec()
        self.assertEqual(a.host_port, -1)
        self.assertEqual(a.guest_port, 5555)
        self.assertEqual(a.timeout, 180)


class TestAVDSpec(unittest.TestCase):
    def test_defaults(self):
        a = AVDSpec()
        self.assertEqual(a.api_level, 35)
        self.assertEqual(a.variant, "google_apis_playstore")
        self.assertEqual(a.arch, "x86_64")
        self.assertEqual(a.device, "pixel_6")


class TestEnvSpecFromDict(unittest.TestCase):
    def _minimal(self):
        return {"id": "test_env"}

    def test_minimal_required_fields(self):
        spec = EnvSpec.from_dict(self._minimal())
        self.assertEqual(spec.id, "test_env")
        self.assertEqual(spec.version, "1.0")
        self.assertIsNone(spec.description)
        self.assertIsNone(spec.image)

    def test_observation_parsed(self):
        d = {**self._minimal(), "observation": [{"type": "rgb_screen", "fps": 15}]}
        spec = EnvSpec.from_dict(d)
        self.assertEqual(len(spec.observation), 1)
        self.assertIsInstance(spec.observation[0], ObservationSpec)
        self.assertEqual(spec.observation[0].fps, 15)

    def test_observation_resolution_is_tuple(self):
        d = {**self._minimal(), "observation": [{"type": "rgb_screen", "resolution": [1920, 1080]}]}
        spec = EnvSpec.from_dict(d)
        self.assertEqual(spec.observation[0].resolution, (1920, 1080))

    def test_action_parsed(self):
        d = {**self._minimal(), "action": [{"type": "keyboard", "events": ["keydown"]}]}
        spec = EnvSpec.from_dict(d)
        self.assertEqual(len(spec.action), 1)
        self.assertIsInstance(spec.action[0], ActionSpec)
        self.assertEqual(spec.action[0].events, ["keydown"])

    def test_mounts_parsed(self):
        d = {**self._minimal(), "mounts": [{"target": "/data", "source": "/host/data", "mode": "ro"}]}
        spec = EnvSpec.from_dict(d)
        self.assertEqual(len(spec.mounts), 1)
        self.assertIsInstance(spec.mounts[0], MountSpec)
        self.assertEqual(spec.mounts[0].target, "/data")

    def test_resources_parsed(self):
        d = {**self._minimal(), "resources": {"cpu": 2.0, "mem_gb": 4}}
        spec = EnvSpec.from_dict(d)
        self.assertIsInstance(spec.resources, RuntimeResources)
        self.assertEqual(spec.resources.cpu, 2.0)
        self.assertEqual(spec.resources.mem_gb, 4)

    def test_security_parsed(self):
        d = {**self._minimal(), "security": {"user": "1001:1001", "privileged": True}}
        spec = EnvSpec.from_dict(d)
        self.assertIsInstance(spec.security, SecuritySpec)
        self.assertEqual(spec.security.user, "1001:1001")
        self.assertTrue(spec.security.privileged)

    def test_security_network_allowlist_ignored(self):
        d = {**self._minimal(), "security": {"network_allowlist": ["8.8.8.8"]}}
        spec = EnvSpec.from_dict(d)
        # network_allowlist is moved to ignored_fields, not on SecuritySpec
        self.assertIn("network_allowlist", spec.security.ignored_fields)

    def test_recording_parsed(self):
        d = {**self._minimal(), "recording": {"video_fps": 30, "output_dir": "/tmp/rec"}}
        spec = EnvSpec.from_dict(d)
        self.assertIsInstance(spec.recording, RecordingSpec)
        self.assertEqual(spec.recording.video_fps, 30)

    def test_vnc_parsed(self):
        d = {**self._minimal(), "vnc": {"enable": True, "host_port": 5902}}
        spec = EnvSpec.from_dict(d)
        self.assertIsInstance(spec.vnc, VNCSpec)
        self.assertTrue(spec.vnc.enable)
        self.assertEqual(spec.vnc.host_port, 5902)

    def test_ssh_parsed(self):
        d = {**self._minimal(), "ssh": {"user": "ubuntu", "port": 2222}}
        spec = EnvSpec.from_dict(d)
        self.assertIsInstance(spec.ssh, SSHSpec)
        self.assertEqual(spec.ssh.user, "ubuntu")

    def test_ssh_none_when_absent(self):
        spec = EnvSpec.from_dict(self._minimal())
        self.assertIsNone(spec.ssh)

    def test_adb_parsed(self):
        d = {**self._minimal(), "adb": {"host_port": 5554, "timeout": 120}}
        spec = EnvSpec.from_dict(d)
        self.assertIsInstance(spec.adb, ADBSpec)
        self.assertEqual(spec.adb.host_port, 5554)

    def test_avd_parsed(self):
        d = {**self._minimal(), "avd": {"api_level": 33}}
        spec = EnvSpec.from_dict(d)
        self.assertIsInstance(spec.avd, AVDSpec)
        self.assertEqual(spec.avd.api_level, 33)

    def test_apptainer_parsed(self):
        d = {**self._minimal(), "apptainer": {"image": "docker://ubuntu:22.04"}}
        spec = EnvSpec.from_dict(d)
        self.assertIsInstance(spec.apptainer, ApptainerSpec)
        self.assertEqual(spec.apptainer.image, "docker://ubuntu:22.04")

    def test_apptainer_none_when_absent(self):
        spec = EnvSpec.from_dict(self._minimal())
        self.assertIsNone(spec.apptainer)

    def test_user_accounts_parsed(self):
        d = {
            **self._minimal(),
            "user_accounts": [
                {"name": "alice", "password": "pw", "role": "admin", "permissions": {"sudo": True}},
            ],
        }
        spec = EnvSpec.from_dict(d)
        self.assertEqual(len(spec.user_accounts), 1)
        u = spec.user_accounts[0]
        self.assertIsInstance(u, UserAccount)
        self.assertEqual(u.name, "alice")
        self.assertTrue(u.permissions.sudo)

    def test_hooks_parsed(self):
        d = {**self._minimal(), "hooks": {"pre_start": "echo pre", "post_start": "echo post"}}
        spec = EnvSpec.from_dict(d)
        self.assertEqual(spec.hooks["pre_start"], "echo pre")

    def test_multi_agent_parsed(self):
        d = {**self._minimal(), "multi_agent": {"roles": ["player", "adversary"], "turn_based": True}}
        spec = EnvSpec.from_dict(d)
        self.assertEqual(spec.multi_agent["roles"], ["player", "adversary"])

    def test_metadata_fields(self):
        d = {
            **self._minimal(),
            "description": "Test env",
            "category": ["productivity"],
            "authors": ["Alice"],
            "tags": ["demo"],
            "version": "2.0",
        }
        spec = EnvSpec.from_dict(d)
        self.assertEqual(spec.description, "Test env")
        self.assertEqual(spec.category, ["productivity"])
        self.assertEqual(spec.authors, ["Alice"])
        self.assertEqual(spec.version, "2.0")


class TestTaskSpecFromDict(unittest.TestCase):
    def _minimal(self):
        return {"id": "test_task"}

    def test_minimal(self):
        spec = TaskSpec.from_dict(self._minimal())
        self.assertEqual(spec.id, "test_task")
        self.assertEqual(spec.version, "1.0")
        self.assertIsNone(spec.env_id)
        self.assertIsNone(spec.description)

    def test_init_defaults(self):
        spec = TaskSpec.from_dict(self._minimal())
        self.assertIsInstance(spec.init, TaskInitSpec)
        self.assertEqual(spec.init.timeout_sec, 600)
        self.assertEqual(spec.init.max_steps, 2000)
        self.assertEqual(spec.init.reward_type, "sparse")

    def test_hooks_defaults(self):
        spec = TaskSpec.from_dict(self._minimal())
        self.assertIsInstance(spec.hooks, TaskHooks)
        self.assertIsNone(spec.hooks.pre_task)
        self.assertIsNone(spec.hooks.post_task)
        self.assertEqual(spec.hooks.pre_task_timeout, 600)

    def test_success_defaults(self):
        spec = TaskSpec.from_dict(self._minimal())
        self.assertIsInstance(spec.success, TaskSuccessSpec)
        self.assertEqual(spec.success.mode, "program")

    def test_custom_init(self):
        d = {
            **self._minimal(),
            "init": {"timeout_sec": 300, "max_steps": 500, "reward_type": "dense"},
        }
        spec = TaskSpec.from_dict(d)
        self.assertEqual(spec.init.timeout_sec, 300)
        self.assertEqual(spec.init.max_steps, 500)
        self.assertEqual(spec.init.reward_type, "dense")

    def test_custom_hooks(self):
        d = {
            **self._minimal(),
            "hooks": {"pre_task": "setup.sh", "post_task": "teardown.sh"},
        }
        spec = TaskSpec.from_dict(d)
        self.assertEqual(spec.hooks.pre_task, "setup.sh")
        self.assertEqual(spec.hooks.post_task, "teardown.sh")

    def test_custom_success(self):
        d = {**self._minimal(), "success": {"mode": "image_match", "spec": {"threshold": 0.9}}}
        spec = TaskSpec.from_dict(d)
        self.assertEqual(spec.success.mode, "image_match")
        self.assertEqual(spec.success.spec["threshold"], 0.9)

    def test_extras_captures_unknown_keys(self):
        d = {**self._minimal(), "custom_field": "custom_value", "another": 42}
        spec = TaskSpec.from_dict(d)
        self.assertIn("custom_field", spec.extras)
        self.assertEqual(spec.extras["custom_field"], "custom_value")
        self.assertEqual(spec.extras["another"], 42)

    def test_metadata_field(self):
        d = {**self._minimal(), "metadata": {"source": "benchmark_v1"}}
        spec = TaskSpec.from_dict(d)
        self.assertEqual(spec.metadata["source"], "benchmark_v1")

    def test_natural_language_string(self):
        d = {**self._minimal(), "natural_language": "Click the red button"}
        spec = TaskSpec.from_dict(d)
        self.assertEqual(spec.natural_language, "Click the red button")

    def test_natural_language_dict(self):
        d = {**self._minimal(), "natural_language": {"en": "Click the red button", "zh": "点击红色按钮"}}
        spec = TaskSpec.from_dict(d)
        self.assertEqual(spec.natural_language["en"], "Click the red button")

    def test_difficulty(self):
        for level in ("easy", "medium", "hard"):
            d = {**self._minimal(), "difficulty": level}
            spec = TaskSpec.from_dict(d)
            self.assertEqual(spec.difficulty, level)

    def test_deps_and_tags(self):
        d = {**self._minimal(), "deps": ["dep_task_1"], "tags": ["ui", "web"]}
        spec = TaskSpec.from_dict(d)
        self.assertEqual(spec.deps, ["dep_task_1"])
        self.assertEqual(spec.tags, ["ui", "web"])


if __name__ == "__main__":
    unittest.main()
