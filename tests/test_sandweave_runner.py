from __future__ import annotations

import sys
import json
from types import ModuleType, SimpleNamespace
from unittest.mock import Mock

import pytest

from gym_anything.compatibility import get_runner_compatibility
from gym_anything.runtime.runners import registry
from gym_anything.runtime.runners import sandweave as runner_module
from gym_anything.runtime.runners.sandweave import SandweaveRunner
from gym_anything.specs import EnvSpec


@pytest.fixture
def sandbox_sdk(monkeypatch):
    sdk = ModuleType("sandweave")
    sdk.__version__ = "0.2.14"
    sdk.Recording = lambda **kwargs: kwargs
    sdk.Template = lambda config: SimpleNamespace(resolve=lambda: config)
    sdk.CacheMiss = type("CacheMiss", (Exception,), {})
    sdk.CacheConflict = type("CacheConflict", (Exception,), {})
    sdk.IncompatibleSnapshot = type("IncompatibleSnapshot", (Exception,), {})
    sandbox = Mock()
    sandbox.id = "test-sandbox"
    sandbox.info = {"vnc": {"port": 5901, "password": "test", "url": "vnc://test"}}
    sandbox.run.return_value = SimpleNamespace(returncode=0, stdout="ok", stderr="")
    sdk.Sandbox = Mock(return_value=sandbox)
    monkeypatch.setitem(sys.modules, "sandweave", sdk)
    monkeypatch.setattr(runner_module, "dependency_status", lambda: {
        "available": True, "reason": None, "deps": {},
    })
    return sdk, sandbox


def spec(**overrides):
    return EnvSpec.from_dict({
        "id": "sandweave-test", "runner": "sandweave", "os_type": "linux",
        "resources": {"cpu": 2, "mem_gb": 4, "gpu": 0, "net": False},
        "observation": [{"type": "rgb_screen", "resolution": [1280, 720]}],
        "action": [{"type": "mouse"}, {"type": "keyboard"}],
        "vnc": {"enable": False, "password": None},
        "recording": {"enable": False},
        **overrides,
    })


def test_runner_uses_registry_and_class_facts(monkeypatch):
    assert registry.resolve_runner_class("sandweave") is SandweaveRunner
    assert registry.resolve_runner_class(
        "gym_anything.runtime.runners.sandweave:SandweaveRunner"
    ) is SandweaveRunner
    monkeypatch.setattr(runner_module, "dependency_status", lambda: {
        "available": False, "reason": "missing SDK", "deps": {},
    })
    assert SandweaveRunner.doctor_status()["available"] is False
    row = get_runner_compatibility("sandweave")
    assert row.checkpoint_caching and row.savevm
    assert row.live_recording
    # Explicit selection must not change another benchmark's default backend.
    assert SandweaveRunner.platform_priority() == 0


def test_start_preserves_resources_environment_mounts_and_resolution(sandbox_sdk, tmp_path):
    sdk, sandbox = sandbox_sdk
    source = tmp_path / "input.txt"
    source.write_text("task input")
    runner = SandweaveRunner(spec(
        security={"resolved_env": {"WEIRD_CAPTCHA_START_PAUSED": "1"}},
        mounts=[{"source": str(source), "target": "/workspace/input.txt", "mode": "ro"}],
    ))
    runner.start()
    kwargs = sdk.Sandbox.call_args.kwargs
    assert kwargs["cpu"] == 2 and kwargs["memory"] == "4GiB"
    assert kwargs["gpu"] is False and kwargs["network"] == "offline"
    assert kwargs["recording"] is False
    assert kwargs["env"]["WEIRD_CAPTCHA_START_PAUSED"] == "1"
    assert kwargs["template"].resolve()["capabilities"]["desktop"]["resolution"] == [1280, 720]
    sandbox.files.upload.assert_called_once_with(str(source), "/workspace/input.txt")
    assert runner.get_runtime_info().instance_name == "test-sandbox"
    runner.stop()
    runner.stop()
    sandbox.terminate.assert_called_once()
    sandbox.close.assert_called_once()


def test_input_holds_releases_and_drag_pass_through(sandbox_sdk):
    _, sandbox = sandbox_sdk
    runner = SandweaveRunner(spec())
    runner.start()
    actions = [
        {"keyboard": {"keys_down": ["CTRL"]}},
        {"mouse": {"move": [10, 20], "buttons": {"left_down": True}}},
        {"mouse": {"move": [30, 40]}},
        {"mouse": {"buttons": {"left_up": True}}},
        {"keyboard": {"keys_up": ["CTRL"]}},
    ]
    for action in actions:
        runner.inject_action(action)
    assert [call.args[0] for call in sandbox.desktop.action.call_args_list] == [
        actions[0], {"mouse": {"move": [10, 20], "buttons": ["left_down"]}},
        actions[2], {"mouse": {"buttons": ["left_up"]}}, actions[4],
    ]
    runner.inject_action({"keyboard": {"text": "typed text"}})
    sandbox.desktop.keyboard.type.assert_called_once_with("typed text")
    assert runner.supports_fast_io() and runner.acks_input_delivery()


def test_native_recording_downloads_before_cleanup(sandbox_sdk, tmp_path):
    sdk, sandbox = sandbox_sdk
    runner = SandweaveRunner(spec(recording={"enable": True, "video_fps": 10}))
    runner.on_episode_start({"episode_dir": str(tmp_path)})

    def download(directory):
        assert not sandbox.terminate.called
        (directory / "segment").mkdir()
        (directory / "segment" / "video.mp4").write_bytes(b"recorded-video")
        (directory / "recording.json").write_text(json.dumps({"segments": [{"id": "segment"}]}))

    sandbox.recording.download.side_effect = download
    runner.start()
    assert sdk.Sandbox.call_args.kwargs["recording"] == {"fps": 10}
    assert runner.supports_native_recording()
    runner.stop()
    runner.stop()
    assert (tmp_path / "recording.mp4").read_bytes() == b"recorded-video"
    assert (tmp_path / "sandweave-recording" / "recording.json").is_file()
    sandbox.recording.download.assert_called_once()
    sandbox.terminate.assert_called_once()


def test_native_download_failure_is_reported_and_guest_is_released(sandbox_sdk, tmp_path):
    _, sandbox = sandbox_sdk
    runner = SandweaveRunner(spec(recording={"enable": True}))
    runner.on_episode_start({"episode_dir": str(tmp_path)})
    runner.start()
    sandbox.recording.download.side_effect = IOError("download failed")
    with pytest.raises(IOError, match="download failed"):
        runner.stop()
    assert runner._sandbox is None
    sandbox.terminate.assert_called_once()
    sandbox.close.assert_called_once()
    sandbox.recording.delete.assert_not_called()


def test_core_does_not_replace_native_video_with_step_frames(sandbox_sdk, tmp_path, monkeypatch):
    from gym_anything.api import make
    import gym_anything.env as env_module

    env = make(spec(recording={"enable": True, "output_dir": str(tmp_path)}))
    monkeypatch.setattr(env_module, "assemble_step_video", lambda **kwargs: pytest.fail("step-frame fallback"))
    env._episode_dir = tmp_path
    env._ensure_recording_artifact()
    with pytest.raises(NotImplementedError, match="sandbox lifecycle"):
        env.pause_recording()
    with pytest.raises(NotImplementedError, match="sandbox lifecycle"):
        env.resume_recording()


def test_files_exec_and_screenshots_use_sdk(sandbox_sdk, tmp_path):
    _, sandbox = sandbox_sdk
    runner = SandweaveRunner(spec())
    runner.start()
    assert runner.exec_capture("command") == "ok"
    assert sandbox.run.call_args.kwargs["check"] is True
    runner.copy_from("/tmp/result.json", str(tmp_path / "result.json"))
    sandbox.files.download.assert_called_once_with("/tmp/result.json", str(tmp_path / "result.json"))
    assert runner.capture_screenshot_image() is sandbox.desktop.screenshot.return_value
    with pytest.raises(NotImplementedError, match="streams"):
        runner.exec_async("record", stdout=object())


def test_checkpoint_keys_separate_tasks_levels_and_memory(sandbox_sdk):
    runner = SandweaveRunner(spec())
    runner.set_checkpoint_key("pre_start", "one")
    pre_start = runner._checkpoint_key()
    runner.set_checkpoint_key("pre_start", "two")
    assert runner._checkpoint_key() == pre_start
    runner.set_checkpoint_key("post_task", "one")
    first = runner._checkpoint_key()
    runner.set_checkpoint_key("post_task", "two")
    assert runner._checkpoint_key() != first
    runner.set_checkpoint_key("post_task", "one", use_savevm=True)
    assert runner._checkpoint_key() != first


def test_checkpoint_miss_falls_back_but_transport_error_propagates(sandbox_sdk):
    sdk, sandbox = sandbox_sdk
    runner = SandweaveRunner(spec())
    runner.set_checkpoint_key("pre_start")
    sdk.Sandbox.side_effect = sdk.CacheMiss("missing")
    assert runner.start_from_checkpoint() is False
    sdk.Sandbox.side_effect = RuntimeError("transport error")
    with pytest.raises(RuntimeError, match="transport error"):
        runner.start_from_checkpoint()


def test_checkpoint_verification_is_required(sandbox_sdk):
    _, sandbox = sandbox_sdk
    runner = SandweaveRunner(spec())
    runner.set_checkpoint_key("pre_start")
    runner.start()
    sandbox.cache.return_value.verify.return_value = {"status": "failed"}
    with pytest.raises(RuntimeError, match="verification failed"):
        runner.create_checkpoint()


def test_gpu_cannot_use_memory_checkpoints(sandbox_sdk):
    runner = SandweaveRunner(spec(resources={"cpu": 2, "mem_gb": 4, "gpu": 1}))
    with pytest.raises(ValueError, match="GPU"):
        runner.set_checkpoint_key("pre_start", use_savevm=True)


@pytest.mark.parametrize("os_type", ["windows", "android", "macos"])
def test_non_linux_spec_rejected(sandbox_sdk, os_type):
    with pytest.raises(ValueError, match="Linux"):
        SandweaveRunner(spec(os_type=os_type))
