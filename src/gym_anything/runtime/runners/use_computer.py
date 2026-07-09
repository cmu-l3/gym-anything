"""Runner backed by remote macOS sandboxes from use.computer.

Each `start()` provisions an ephemeral macOS VM (M4, 4 cores / 8 GB) via the
use.computer HTTP API, uploads the env's `mounts` to mirror Docker's bind-mount
semantics, and translates `inject_action` into mac.mouse / mac.keyboard SDK
calls. `stop()` destroys the sandbox.

Capability story (declared in compatibility.py):
- live_recording=False — we capture per-step frames and let env.py assemble the video.
- checkpoint_caching=False, savevm=False — the upstream API has no snapshot endpoint.
- audio capture unsupported — the SDK has no audio endpoint; env.py silently degrades.
"""

from __future__ import annotations

import json
import logging
import os
import shlex
import time
from pathlib import Path
from typing import Any, Dict, List, Optional

from ...specs import EnvSpec
from .base import BaseRunner


logger = logging.getLogger(__name__)


DEFAULT_BASE_URL = "https://api.use.computer"
SSH_USER = "lume"
# macOS root volume is read-only under SIP, so the per-env workspace lives in
# the user's home rather than under `/workspace`. Env files written for this
# runner should target /Users/lume/workspace/... explicitly.
WORKSPACE_DIR = f"/Users/{SSH_USER}/workspace"


def _import_sdk():
    try:
        from use_computer import Computer  # noqa: F401
    except ImportError as exc:
        raise ImportError(
            "The use_computer SDK is required for UseComputerRunner. "
            "Install with: pip install use-computer"
        ) from exc
    from use_computer import Computer
    return Computer


class UseComputerRunner(BaseRunner):
    """Drives a remote macOS sandbox via the use.computer SDK."""

    is_macos = True

    def __init__(self, spec: EnvSpec):
        super().__init__(spec)
        self._Computer = _import_sdk()
        self._client = None
        self._sandbox = None
        self._sandbox_id: Optional[str] = None
        self._vnc_url: Optional[str] = None
        self._host: Optional[str] = None
        self._image = self._resolve_image(spec)
        self._base_url = os.environ.get("USE_COMPUTER_BASE_URL", DEFAULT_BASE_URL)
        if not (os.environ.get("USE_COMPUTER_API_KEY") or os.environ.get("MMINI_API_KEY")):
            raise RuntimeError(
                "USE_COMPUTER_API_KEY is not set. Mint a key at https://use.computer "
                "(or set USE_COMPUTER_BASE_URL=https://api.dev.use.computer for the dev env)."
            )

    @staticmethod
    def _resolve_image(spec: EnvSpec) -> Optional[str]:
        # Allow env.json to pin a use.computer image via spec.image (e.g. "base-macos", "base-human").
        # spec.image is otherwise interpreted as a Docker image tag by other runners — fine, we just
        # interpret it differently when this runner is selected.
        return spec.image or None

    # ------------------------------------------------------------------
    # Lifecycle
    # ------------------------------------------------------------------
    def start(self, seed: Optional[int] = None) -> None:
        del seed  # use.computer images are ephemeral, seed is not meaningful at sandbox layer
        self._client = self._Computer(base_url=self._base_url)
        create_kwargs: Dict[str, Any] = {"type": "macos"}
        # The SDK's typed create() doesn't take image=, but the underlying API does.
        # Hit the HTTP layer directly so envs can pick a non-default base image.
        if self._image:
            self._sandbox = self._create_with_image(self._image)
        else:
            self._sandbox = self._client.create(**create_kwargs)
        self._sandbox_id = self._sandbox.sandbox_id
        self._host = getattr(self._sandbox, "host", None)
        self._vnc_url = getattr(self._sandbox, "vnc_url", None) or None
        logger.info(
            "use.computer sandbox %s up (image=%s host=%s vnc=%s)",
            self._sandbox_id, self._image or "default", self._host, self._vnc_url,
        )
        # Keepalive so agent think-time over the 2-minute reaper doesn't kill the session.
        try:
            self._sandbox.start_keepalive(interval=30)
        except Exception as exc:
            logger.warning("start_keepalive failed (continuing): %s", exc)

        # Prepare the workspace root. Lives under $HOME because macOS root is
        # read-only under SIP; lume can mkdir here without sudo.
        self._sandbox.exec_ssh(f"mkdir -p {WORKSPACE_DIR}", timeout=30)
        # Mirror the env spec's `mounts` field — uploads each source dir into the target path.
        # Mount.mode is ignored; everything is read/write inside the throwaway VM.
        for mount in (self.spec.mounts or []):
            source = os.path.abspath(mount.source)
            target = mount.target
            if not os.path.isdir(source):
                logger.warning("Mount source %s is not a directory, skipping", source)
                continue
            logger.info("uploading %s -> %s", source, target)
            self._sandbox.upload_dir(source, target)
            # Restore exec bit on shell scripts (tarball preserves mode but be defensive).
            self._sandbox.exec_ssh(
                f"find {shlex.quote(target)} -name '*.sh' -exec chmod +x {{}} +",
                timeout=60,
            )

    def stop(self) -> None:
        if self._sandbox is not None:
            try:
                self._sandbox.stop_keepalive()
            except Exception:
                pass
            try:
                self._sandbox.close()
            except Exception as exc:
                logger.warning("sandbox close failed: %s", exc)
            self._sandbox = None
        if self._client is not None:
            try:
                self._client.close()
            except Exception:
                pass
            self._client = None

    # ------------------------------------------------------------------
    # Hook entry points called by GymAnythingEnv
    # ------------------------------------------------------------------
    def run_reset(self, reset_script: str, seed: Optional[int] = None) -> None:
        seed_env = f"SEED={seed} " if seed is not None else ""
        self._sandbox.exec_ssh(f"{seed_env}bash -lc {shlex.quote(reset_script)}", timeout=600)

    def run_task_init(self, init_script: str) -> None:
        self._sandbox.exec_ssh(f"bash -lc {shlex.quote(init_script)}", timeout=600)

    def exec(
        self,
        cmd: str,
        env: Optional[Dict[str, str]] = None,
        user: Optional[str] = None,
        use_pty: bool = True,
        timeout: int = 600,
    ) -> int:
        del use_pty  # SDK exec_ssh ignores PTY; stdout is captured on the gateway side
        if user and user != SSH_USER:
            cmd = f"sudo -u {shlex.quote(user)} {cmd}"
        if env:
            prefix = " ".join(f"{k}={shlex.quote(v)}" for k, v in env.items())
            cmd = f"{prefix} {cmd}"
        result = self._sandbox.exec_ssh(cmd, timeout=timeout)
        return int(getattr(result, "return_code", 0))

    def exec_capture(self, cmd: str) -> str:
        result = self._sandbox.exec_ssh(cmd, timeout=600)
        return result.stdout

    def exec_capture_bytes(self, cmd: str) -> bytes:
        # exec_ssh stdout is a str; for binary capture round-trip via base64.
        b64 = self._sandbox.exec_ssh(f"({cmd}) | base64", timeout=600).stdout
        import base64 as _b64
        return _b64.b64decode(b64)

    # ------------------------------------------------------------------
    # Actions
    # ------------------------------------------------------------------
    def inject_action(self, action: Dict[str, Any]) -> None:
        mouse = action.get("mouse")
        if mouse:
            self._apply_mouse(mouse)
        keyboard = action.get("keyboard")
        if keyboard:
            self._apply_keyboard(keyboard)
        api_call = action.get("api_call")
        if api_call:
            logger.debug("api_call action ignored (env-specific): %s", api_call.get("name"))
        voice = action.get("voice")
        if voice:
            logger.debug("voice action ignored on use_computer (no audio inject API)")

    def _apply_mouse(self, mouse: Dict[str, Any]) -> None:
        m = self._sandbox.mouse
        if "left_click" in mouse:
            x, y = mouse["left_click"]
            m.click(int(x), int(y), button="left")
        if "right_click" in mouse:
            x, y = mouse["right_click"]
            m.click(int(x), int(y), button="right")
        if "double_click" in mouse:
            x, y = mouse["double_click"]
            m.click(int(x), int(y), button="left", double=True)
        if "triple_click" in mouse:
            x, y = mouse["triple_click"]
            # SDK has no triple-click primitive; do 3 fast singles at the same point.
            for _ in range(3):
                m.click(int(x), int(y), button="left")
        if "left_click_drag" in mouse:
            (x1, y1), (x2, y2) = mouse["left_click_drag"]
            m.drag(int(x1), int(y1), int(x2), int(y2), button="left")
        if "right_click_drag" in mouse:
            (x1, y1), (x2, y2) = mouse["right_click_drag"]
            m.drag(int(x1), int(y1), int(x2), int(y2), button="right")
        if "move" in mouse:
            x, y = mouse["move"]
            m.move(int(x), int(y))
        if "scroll" in mouse:
            dy = int(mouse["scroll"])
            pos = m.get_position()
            direction = "down" if dy > 0 else "up"
            m.scroll(int(pos.x), int(pos.y), direction=direction, amount=abs(dy))

    _MODIFIER_KEYS = {"cmd", "command", "ctrl", "control", "shift", "alt", "option", "fn"}

    def _apply_keyboard(self, keyboard: Dict[str, Any]) -> None:
        kb = self._sandbox.keyboard
        text = keyboard.get("text")
        keys = keyboard.get("keys")
        if text:
            kb.type(text)
        if keys:
            seq = [keys] if isinstance(keys, str) else [str(k) for k in keys]
            modifiers = [k for k in seq if k.lower() in self._MODIFIER_KEYS]
            non_modifiers = [k for k in seq if k.lower() not in self._MODIFIER_KEYS]
            if not non_modifiers:
                # Pure modifier chord (rare) — fall back to hotkey on the raw join.
                kb.hotkey("+".join(seq))
            elif len(non_modifiers) == 1 and not modifiers:
                kb.press(non_modifiers[0])
            else:
                # press() carries modifiers; hotkey() is only for the literal
                # "+"-joined chord shape ("cmd+s"). Prefer press when we have
                # a single primary key with optional modifiers.
                kb.press(non_modifiers[-1], modifiers=modifiers or None)

    # ------------------------------------------------------------------
    # Observations
    # ------------------------------------------------------------------
    def capture_observation(self) -> Dict[str, Any]:
        # env.py composes the actual payload (screen file + audio bytes + ui_tree).
        # We just return the modality metadata for any caller that introspects.
        obs: Dict[str, Any] = {}
        screen_spec = next((o for o in self.spec.observation if o.type == "rgb_screen"), None)
        if screen_spec:
            obs["screen"] = {"format": "rgb", "fps": screen_spec.fps, "resolution": screen_spec.resolution}
        return obs

    def capture_screenshot(self, host_path) -> bool:
        try:
            png = self._sandbox.screenshot.take_full_screen()
        except Exception as exc:
            logger.warning("screenshot failed: %s", exc)
            return False
        Path(host_path).parent.mkdir(parents=True, exist_ok=True)
        Path(host_path).write_bytes(png)
        return True

    def capture_ui_tree(self) -> str:
        try:
            tree = self._sandbox.accessibility.get_tree(best_effort=True)
        except Exception as exc:
            logger.warning("ui_tree fetch failed: %s", exc)
            return ""
        if not getattr(tree, "available", False):
            return ""
        return json.dumps(getattr(tree, "tree", None) or {}, ensure_ascii=False)

    def capture_audio_raw(self, duration_sec: float, rate: int, channels: int) -> bytes:
        # No audio capture endpoint upstream. env.py wraps this in try/except
        # and silently omits "audio" from the observation when it raises.
        raise NotImplementedError(
            "use.computer SDK exposes no audio capture endpoint"
        )

    # ------------------------------------------------------------------
    # File transfer
    # ------------------------------------------------------------------
    def copy_to(self, host_src: str, container_dst: str) -> None:
        src = Path(host_src)
        if src.is_dir():
            self._sandbox.upload_dir(str(src), container_dst)
        else:
            self._sandbox.upload(str(src), container_dst)

    def copy_from(self, container_src: str, host_dst: str) -> None:
        # Best-effort: treat as a single file unless explicitly a directory.
        # The SDK distinguishes via download_file vs download_dir.
        ls = self._sandbox.exec_ssh(f"test -d {shlex.quote(container_src)} && echo dir || echo file", timeout=10)
        if ls.stdout.strip() == "dir":
            self._sandbox.download_dir(container_src, host_dst)
        else:
            self._sandbox.download_file(container_src, host_dst)

    def put_file(self, host_path) -> str:
        remote = f"/Users/{SSH_USER}/uploads/{Path(host_path).name}"
        self._sandbox.exec_ssh(f"mkdir -p /Users/{SSH_USER}/uploads", timeout=10)
        self._sandbox.upload(str(host_path), remote)
        return remote

    # ------------------------------------------------------------------
    # Capability declarations
    # ------------------------------------------------------------------
    def supports_live_recording(self) -> bool:
        # The SDK exposes Recording.start/stop, but the gym-anything FFmpegRecorder
        # is built around running ffmpeg inside the runtime — wiring use.computer's
        # recording endpoint into that recorder is a separate piece of work. For
        # now we declare False so env.py falls back to per-step frame assembly,
        # matching what avf / qemu / apptainer runners do.
        return False

    def supports_checkpoint_caching(self) -> bool:
        return False

    def supports_savevm(self) -> bool:
        return False

    # ------------------------------------------------------------------
    # Runtime info exposed to SessionInfo
    # ------------------------------------------------------------------
    def get_platform_family(self) -> str:
        return "macos"

    def get_runtime_info(self):
        from ...contracts import RunnerRuntimeInfo
        return RunnerRuntimeInfo(
            platform_family="macos",
            container_name=self._sandbox_id,
            instance_name=self._host,
            vnc_port=None,
            vnc_password=None,
            vnc_url=self._vnc_url,
            ssh_port=None,
            ssh_user=SSH_USER,
            ssh_password=None,
        )

    @property
    def vnc_url(self) -> Optional[str]:
        return self._vnc_url

    # ------------------------------------------------------------------
    # Internal: HTTP-level create (SDK's typed create() omits image=)
    # ------------------------------------------------------------------
    def _create_with_image(self, image: str):
        # Reuse the SDK's HTTP client + post-create plumbing instead of duplicating it.
        # MacOSSandbox moved to the package top level in newer SDK releases
        # (use_computer.sandbox no longer exists as of 0.0.44).
        from use_computer import MacOSSandbox

        http = self._client._http  # internal but stable; the SDK's create() uses it the same way
        resp = http.post("/v1/sandboxes", json={"type": "macos", "image": image}, timeout=180.0)
        resp.raise_for_status()
        data = resp.json()
        return MacOSSandbox(
            sandbox_id=data["sandbox_id"],
            http=http,
            vnc_url=f"{self._base_url}{data.get('vnc_url', '')}",
            ssh_url=f"{self._base_url}{data.get('ssh_url', '')}",
            vm_ip=data.get("vm_ip", ""),
            host=data.get("host", ""),
        )
