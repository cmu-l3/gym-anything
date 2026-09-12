"""Linux GNOME runner using sandweave[desktop]>=0.2.14 (Python 3.11+).

Sandweave owns provisioning, desktop I/O and checkpoint storage. Set
SANDWEAVE_HOME for its assets/cache and GYM_ANYTHING_SANDWEAVE_TARGET for an
optional SDK worker target; the default target is local. The worker must have
the shared image declared by sandweave_ubuntu.toml imported from its QEMU Ubuntu base.
"""

from __future__ import annotations

import dataclasses
import hashlib
import importlib.metadata
import json
import math
import os
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import uuid
from pathlib import Path
from typing import Any, Dict, Optional

from ...config.presets import is_android_preset, is_windows_preset
from ...contracts import RunnerRuntimeInfo
from ...specs import EnvSpec
from .base import BaseRunner


def dependency_status() -> Dict[str, Any]:
    reason = None
    if sys.version_info < (3, 11) or sys.platform != "linux":
        reason = "Sandweave requires Python 3.11+ on Linux"
    else:
        try:
            version = importlib.metadata.version("sandweave")
            if tuple(map(int, re.findall(r"\d+", version)[:3])) < (0, 2, 14):
                reason = f"sandweave>=0.2.14 required (found {version})"
        except importlib.metadata.PackageNotFoundError:
            reason = "sandweave is not installed; pip install 'gym-anything[sandweave]'"
    return {"available": reason is None, "reason": reason, "deps": {}}


class SandweaveRunner(BaseRunner):
    @classmethod
    def doctor_status(cls):
        return dependency_status()

    @classmethod
    def compatibility(cls):
        from gym_anything.compatibility import RunnerCompatibility

        return RunnerCompatibility(
            runner="sandweave",
            display_name="SandweaveRunner",
            live_recording=True,
            screenshot_video_assembly=True,
            checkpoint_caching=True,
            savevm=True,
            user_accounts_mode="preprovisioned_accounts",
            notes=[
                "Linux GNOME desktops through Sandweave; requires Python 3.11+ and sandweave[desktop]>=0.2.14.",
                "Opt-in native recording spans sandbox startup to teardown and retains timestamped segments. Separate recording pause/resume is unavailable.",
                "Filesystem restores boot fresh processes. GPU desktops cannot use savevm.",
                "The ga desktop account is preprovisioned; user_accounts remains credential metadata.",
                "VNC URLs are local to the Sandweave worker; remote targets require forwarding.",
            ],
        )

    def __init__(self, spec: EnvSpec):
        super().__init__(spec)
        base = spec.base or ""
        if ((spec.os_type or "linux").lower() != "linux"
                or is_android_preset(base) or is_windows_preset(base)
                or "macos" in base.lower() or spec.apks or spec.avd):
            raise ValueError("SandweaveRunner supports Linux environments only")
        if spec.resources.gpu not in (0, 1):
            raise ValueError("SandweaveRunner supports at most one GPU")
        status = dependency_status()
        if not status["available"]:
            raise RuntimeError(status["reason"])
        import sandweave

        self._sdk = sandweave
        self._sandbox = None
        self.target = os.environ.get("GYM_ANYTHING_SANDWEAVE_TARGET")
        self._screen = next((o for o in spec.observation if o.type == "rgb_screen"), None)
        self.resolution = tuple(
            self._screen.resolution if self._screen and self._screen.resolution else (1920, 1080)
        )
        self._template = sandweave.Template({
            "extends": str(Path(__file__).with_name("sandweave_ubuntu.toml")),
            "capabilities": {"desktop": {"resolution": list(self.resolution)}},
        })
        preparation = {"resources": dataclasses.asdict(spec.resources),
                       "resolution": self.resolution, "env": self.default_exec_env(),
                       "template": self._template.resolve()}
        self._base_key = "gym-anything:ubuntu:" + hashlib.sha256(
            json.dumps(preparation, sort_keys=True).encode()
        ).hexdigest()
        self._runtime_info = RunnerRuntimeInfo(platform_family="linux")
        self._cache_level = None
        self._task_id = None
        self._cache_state = "filesystem"
        self._episode_dir = None

    def on_episode_start(self, context: Dict[str, Any]) -> None:
        directory = context.get("episode_dir")
        self._episode_dir = Path(directory) if directory else None

    def supports_native_recording(self) -> bool:
        return True

    def supports_fast_io(self) -> bool:
        return True

    def acks_input_delivery(self) -> bool:
        return True

    def supports_checkpoint_caching(self) -> bool:
        return True

    def supports_savevm(self) -> bool:
        return not self.spec.resources.gpu

    def get_runtime_info(self) -> RunnerRuntimeInfo:
        return self._runtime_info

    def _active(self):
        if self._sandbox is None:
            raise RuntimeError("SandweaveRunner is not started")
        return self._sandbox

    def _start(self, cache=None) -> None:
        if self._sandbox is not None:
            raise RuntimeError("SandweaveRunner already has an active sandbox")
        source = {"cache": cache} if cache is not None else {
            "template": self._template,
            "cache_key": self._base_key,
        }
        self._report_start("sandweave", "restoring checkpoint" if cache else "starting GNOME")
        try:
            self._sandbox = self._sdk.Sandbox(
                **source, target=self.target, startup_timeout=3600,
                cpu=math.ceil(self.spec.resources.cpu),
                memory=f"{self.spec.resources.mem_gb}GiB",
                gpu=bool(self.spec.resources.gpu),
                network="internet" if self.spec.resources.net else "offline",
                env=self.default_exec_env(),
                recording=(self._sdk.Recording(fps=self.spec.recording.video_fps)
                           if self.spec.recording.enable else False),
            )
            if cache is None:
                for mount in sorted(self.spec.mounts, key=lambda m: len(Path(m.target).parts)):
                    source_path = Path(mount.source).expanduser()
                    if not source_path.exists():
                        self._report_log(f"Sandweave mount source does not exist: {source_path}")
                        continue
                    self.copy_to(str(source_path), mount.target)
            if self.spec.vnc.password:
                self._sandbox.files.write_bytes(
                    "/etc/sandweave-vnc-password", (self.spec.vnc.password + "\n").encode()
                )
                self._run(
                    "tigervncpasswd -f < /etc/sandweave-vnc-password > /home/ga/.vnc/passwd "
                    "&& chown ga:ga /home/ga/.vnc/passwd "
                    "&& chmod 600 /etc/sandweave-vnc-password /home/ga/.vnc/passwd", check=True,
                )
            info = self._sandbox.info
            vnc = info.get("vnc") or {}
            self._runtime_info = RunnerRuntimeInfo(
                platform_family="linux", instance_name=self._sandbox.id,
                vnc_port=vnc.get("port"), vnc_password=vnc.get("password"),
                vnc_url=vnc.get("url"),
            )
            self._report_done("sandweave", self._sandbox.id)
        except BaseException:
            self.stop()
            raise

    def start(self, seed: Optional[int] = None) -> None:
        if self._sandbox is None:
            self._start()

    def stop(self) -> None:
        sandbox = self._sandbox
        if sandbox is not None:
            # SDK stop() saves a snapshot; runner teardown must discard the session.
            try:
                if self.spec.recording.enable and self._episode_dir is not None:
                    self._download_recording(sandbox)
            finally:
                try:
                    sandbox.terminate()
                finally:
                    sandbox.close()
                    self._sandbox = None
        self._runtime_info = RunnerRuntimeInfo(platform_family="linux")

    def _download_recording(self, sandbox) -> None:
        self._episode_dir.mkdir(parents=True, exist_ok=True)
        destination = self._episode_dir / "sandweave-recording"
        if not destination.exists():
            # Failed downloads retain their partial evidence; a retry uses a
            # new empty directory, as required by the SDK's download contract.
            temporary = Path(tempfile.mkdtemp(prefix=".sandweave-recording-", dir=self._episode_dir))
            sandbox.recording.download(temporary)
            temporary.rename(destination)
        manifest = json.loads((destination / "recording.json").read_text())
        videos = [destination / segment["id"] / "video.mp4" for segment in manifest["segments"]]
        if not videos or any(not video.is_file() for video in videos):
            raise RuntimeError(f"Sandweave recording has no complete video; evidence retained at {destination}")
        target = self._episode_dir / "recording.mp4"
        if target.exists():
            raise FileExistsError(f"Refusing to overwrite recording: {target}")
        if len(videos) == 1:
            shutil.copyfile(videos[0], target)
        else:
            import imageio_ffmpeg

            playlist = destination / "segments.txt"
            playlist.write_text("".join("file '" + str(video).replace("'", "'\\''") + "'\n" for video in videos))
            subprocess.run([
                imageio_ffmpeg.get_ffmpeg_exe(), "-nostdin", "-n", "-loglevel", "error",
                "-f", "concat", "-safe", "0", "-i", str(playlist), "-c", "copy", str(target),
            ], check=True, timeout=300)

    def _run(self, cmd: str, *, env=None, user=None, timeout=600, **kwargs):
        return self._active().run(
            cmd, shell="/bin/bash", user=user or "root",
            env=self.merge_exec_env(env), timeout=timeout, **kwargs,
        )

    def exec(self, cmd: str, env=None, user=None, use_pty: bool = True, timeout: int = 600) -> int:
        result = self._run(cmd, env=env, user=user, pty=use_pty, timeout=timeout)
        if result.returncode:
            self._report_log(f"Sandweave exec failed ({result.returncode}): {result.stderr[:500]}")
        return result.returncode

    def exec_capture(self, cmd: str) -> str:
        return self._run(cmd, check=True).stdout

    def exec_capture_bytes(self, cmd: str) -> bytes:
        return self._run(cmd, binary=True, check=True).stdout

    def exec_async(self, cmd: str, env=None, stdout=None, stderr=None):
        if stdout is not None or stderr is not None:
            raise NotImplementedError("SandweaveRunner does not redirect asynchronous process streams")
        return self._active().exec(
            cmd, shell="/bin/bash", user="root", env=self.merge_exec_env(env),
        )

    def run_reset(self, reset_script: str, seed: Optional[int] = None) -> None:
        self._run(reset_script, env={"SEED": str(seed)} if seed is not None else None, check=True)

    def run_task_init(self, init_script: str) -> None:
        self._run(init_script, check=True)

    def inject_action(self, action: Dict[str, Any]) -> None:
        mouse = dict(action.get("mouse") or {})
        if isinstance(mouse.get("buttons"), dict):
            mouse["buttons"] = [name for name, enabled in mouse["buttons"].items() if enabled]
        desktop = self._active().desktop
        if mouse:
            desktop.action({"mouse": mouse})
        for key, value in (action.get("keyboard") or {}).items():
            if key == "text":
                desktop.keyboard.type(value)
            else:
                desktop.action({"keyboard": {key: value}})

    def capture_observation(self) -> Dict[str, Any]:
        if self._screen is None:
            return {}
        return {"screen": {"format": "rgb", "fps": self._screen.fps,
                           "resolution": self.resolution}}

    def capture_screenshot_image(self):
        return self._active().desktop.screenshot()

    def capture_screenshot(self, host_path) -> bool:
        path = Path(host_path)
        path.parent.mkdir(parents=True, exist_ok=True)
        self.capture_screenshot_image().save(path, "PNG")
        return True

    def capture_audio_raw(self, duration_sec: float, rate: int, channels: int) -> bytes:
        return b""

    def copy_to(self, host_src: str, container_dst: str) -> None:
        self._active().files.upload(host_src, container_dst)

    def copy_from(self, container_src: str, host_dst: str) -> None:
        self._active().files.download(container_src, host_dst)

    def put_file(self, host_path) -> str:
        destination = f"/tmp/ga_{uuid.uuid4().hex}_{Path(host_path).name}"
        self.copy_to(str(host_path), destination)
        return destination

    def to_container_path(self, host_path):
        return self.put_file(host_path) if Path(host_path).exists() else str(host_path)

    def save_state(self, save_paths: Optional[list[str]]) -> str:
        destination = f"/tmp/ga_snapshot_{uuid.uuid4().hex}.tar"
        paths = " ".join(shlex.quote(path) for path in (save_paths or ["/workspace"]))
        self._run(f"tar -cf {shlex.quote(destination)} -- {paths}", timeout=1800, check=True)
        return destination

    def load_state(self, snapshot_container_path: str) -> None:
        self._run(f"tar -xf {shlex.quote(snapshot_container_path)} -C /", timeout=1800, check=True)

    def set_checkpoint_key(self, cache_level: str, task_id: Optional[str] = None,
                           use_savevm: bool = False) -> None:
        if cache_level not in {"pre_start", "post_start", "post_task"}:
            raise ValueError(f"Unsupported checkpoint level: {cache_level}")
        if use_savevm and not self.supports_savevm():
            raise ValueError("Sandweave does not support memory checkpoints for GPU desktops")
        self._cache_level, self._task_id = cache_level, task_id
        self._cache_state = "memory" if use_savevm else "filesystem"

    def _config_digest(self) -> str:
        config = dataclasses.asdict(self.spec)
        for key in ("recording", "diagnostics", "runner"):
            config.pop(key, None)
        config["sandweave_version"] = self._sdk.__version__
        config["template"] = self._template.resolve()
        return hashlib.sha256(json.dumps(config, sort_keys=True, default=str).encode()).hexdigest()

    def _checkpoint_key(self) -> str:
        if self._cache_level is None:
            raise RuntimeError("set_checkpoint_key() must precede checkpoint operations")
        config = {"environment": self._config_digest()}
        config["task_id"] = self._task_id if self._cache_level == "post_task" else None
        digest = hashlib.sha256(json.dumps(config, sort_keys=True, default=str).encode()).hexdigest()
        return f"gym-anything:v11:{digest}:{self._cache_level}:{self._cache_state}"

    def checkpoint_exists(self) -> bool:
        # The SDK has no top-level lookup API; use the metadata RPC its cache CLI uses.
        from sandweave.sandbox.targets import connect

        connection = connect(self.target)
        try:
            record = connection.call("snapshot_info", reference=self._checkpoint_key())
            return record["verification"]["status"] != "failed"
        except self._sdk.CacheMiss:
            return False
        finally:
            connection.close()

    def create_checkpoint(self) -> bool:
        try:
            saved = self._active().cache(self._checkpoint_key(), state=self._cache_state)
        except self._sdk.CacheConflict:
            return False
        if saved.verify()["status"] != "passed":
            raise RuntimeError("Sandweave checkpoint verification failed")
        return True

    def start_from_checkpoint(self, seed: Optional[int] = None) -> bool:
        try:
            self._start(cache=self._checkpoint_key())
            return True
        except (self._sdk.CacheMiss, self._sdk.IncompatibleSnapshot) as exc:
            self._report_log(f"Sandweave checkpoint unavailable: {exc}")
            return False
