from __future__ import annotations

import json
import os
import shlex
import tempfile
import unittest
from pathlib import Path
from typing import Literal

from PIL import Image

from gym_anything.compatibility import list_supported_runners
from gym_anything.config.loading import from_config
from gym_anything.doctor import get_runner_status
from gym_anything.specs import EnvSpec


RunnerProfile = Literal["desktop_linux", "android", "synthetic"]

RUNNER_PROFILES: dict[str, RunnerProfile] = {
    "docker": "desktop_linux",
    "qemu": "desktop_linux",
    "qemu_native": "desktop_linux",
    "apptainer": "desktop_linux",
    "avf": "desktop_linux",
    "avd": "android",
    "avd_native": "android",
    "local": "synthetic",
}

_EXECUTION_ENV = "GYM_ANYTHING_RUN_EXECUTION_TESTS"
_RUNNER_FILTER_ENV = "GYM_ANYTHING_EXECUTION_RUNNERS"
_MAGENTA = (255, 0, 255)
_GREEN = (0, 255, 0)


def _desktop_linux_runner_keys() -> list[str]:
    return [runner for runner, profile in RUNNER_PROFILES.items() if profile == "desktop_linux"]


def _selected_execution_runners() -> list[str]:
    selected = _desktop_linux_runner_keys()
    requested = os.environ.get(_RUNNER_FILTER_ENV, "").strip()
    if not requested:
        return selected

    allowed = {item.strip() for item in requested.split(",") if item.strip()}
    unknown = sorted(allowed - set(RUNNER_PROFILES))
    if unknown:
        raise AssertionError(f"Unknown runner keys in {_RUNNER_FILTER_ENV}: {', '.join(unknown)}")
    return [runner for runner in selected if runner in allowed]


def _runner_class_for(runner_key: str):
    if runner_key == "docker":
        from gym_anything.runtime.runners.docker import DockerRunner

        return DockerRunner
    if runner_key == "qemu":
        from gym_anything.runtime.runners.qemu_apptainer import QemuApptainerRunner

        return QemuApptainerRunner
    if runner_key == "qemu_native":
        from gym_anything.runtime.runners.qemu_native import QemuNativeRunner

        return QemuNativeRunner
    if runner_key == "apptainer":
        from gym_anything.runtime.runners.apptainer_direct import ApptainerDirectRunner

        return ApptainerDirectRunner
    if runner_key == "avf":
        from gym_anything.runtime.runners.avf import AVFRunner

        return AVFRunner
    if runner_key == "avd":
        from gym_anything.runtime.runners.avd_apptainer import AVDApptainerRunner

        return AVDApptainerRunner
    if runner_key == "avd_native":
        from gym_anything.runtime.runners.avd_native import AVDNativeRunner

        return AVDNativeRunner
    if runner_key == "local":
        from gym_anything.runtime.runners.local import LocalRunner

        return LocalRunner
    raise KeyError(f"Unsupported runner key in test suite: {runner_key}")


def _make_runner_spec(*, runner_key: str, output_dir: str) -> EnvSpec:
    data: dict[str, object] = {
        "id": f"tests.{runner_key}.runner-contract@1",
        "runner": runner_key,
        "os_type": "linux",
        "observation": [{"type": "rgb_screen", "fps": 1, "resolution": [1280, 720]}],
        "action": [{"type": "mouse"}, {"type": "keyboard"}],
        "recording": {"enable": False, "output_dir": output_dir},
        "vnc": {"enable": True, "password": "password"},
        "resources": {"cpu": 1, "mem_gb": 4, "gpu": 0, "net": True},
    }
    if runner_key == "docker":
        preset_dir = Path(__file__).resolve().parents[1] / "src" / "gym_anything" / "presets" / "x11_lite"
        data["dockerfile"] = str(preset_dir / "Dockerfile")
        data["entrypoint"] = "/workspace/start_app.sh"
        data["security"] = {"user": "root", "cap_drop": ["ALL"]}
    return EnvSpec.from_dict(data)


def _unsupported_hints_for(runner_key: str, status: dict[str, object]) -> list[str]:
    hints = {runner_key.lower()}
    for token in runner_key.lower().split("_"):
        if token:
            hints.add(token)

    reason = status.get("reason")
    if isinstance(reason, str):
        hints.add(reason.lower())
        for token in reason.lower().replace("(", " ").replace(")", " ").replace("/", " ").split():
            token = token.strip(" ,.")
            if len(token) >= 4:
                hints.add(token)

    deps = status.get("deps", {})
    if isinstance(deps, dict):
        for dep, info in deps.items():
            if isinstance(info, dict) and not info.get("installed", False):
                hints.add(str(dep).lower())

    # Generic hints for runners whose binaries are simply missing
    hints.add("not found")

    return sorted(hints)


def _linux_marker_name(runner_key: str) -> str:
    return f"GA_MARKER_{runner_key.upper()}_MAGENTA"


def _linux_marker_hook(runner_key: str) -> str:
    marker = _linux_marker_name(runner_key)
    payload = f"printf '%s\\n' {shlex.quote(marker)}; sleep 300"
    command = (
        'display=""; '
        'for candidate in "${DISPLAY:-}" :1 :99 :0; do '
        '[ -n "$candidate" ] || continue; '
        'if DISPLAY="$candidate" xdpyinfo >/dev/null 2>&1; then display="$candidate"; break; fi; '
        'done; '
        '[ -n "$display" ] || exit 89; '
        'if command -v xterm >/dev/null 2>&1 && command -v wmctrl >/dev/null 2>&1; then '
        f'  DISPLAY="$display" xterm -title {shlex.quote(marker)} -fa Monospace -fs 28 -bg \'#ff00ff\' -fg \'#00ff00\' '
        f'-geometry 120x40+0+0 -e bash -lc {shlex.quote(payload)} >/tmp/ga_marker_xterm.log 2>&1 & '
        '  wid=""; '
        '  for _ in $(seq 1 20); do '
        f'    wid=$(DISPLAY="$display" wmctrl -l | grep -F -m1 {shlex.quote(marker)} | awk \'{{print $1}}\'); '
        '    if [ -n "$wid" ]; then '
        '      DISPLAY="$display" wmctrl -ia "$wid" || true; '
        '      DISPLAY="$display" wmctrl -ir "$wid" -b add,maximized_vert,maximized_horz || true; '
        '      break; '
        '    fi; '
        '    sleep 0.5; '
        '  done; '
        '  [ -n "$wid" ] || exit 87; '
        '  sleep 2; '
        'else '
        '  exit 88; '
        'fi'
    )
    return shlex.quote(command)


def _write_execution_env(root: Path, *, runner_key: str) -> None:
    env_data: dict[str, object] = {
        "id": f"tests.{runner_key}.execution@1",
        "runner": runner_key,
        "os_type": "linux",
        "observation": [{"type": "rgb_screen", "fps": 1, "resolution": [1280, 720]}],
        "action": [{"type": "mouse"}, {"type": "keyboard"}],
        "recording": {"enable": False, "output_dir": str(root / "artifacts")},
        "vnc": {"enable": True, "password": "password"},
        "resources": {"cpu": 1, "mem_gb": 4, "gpu": 0, "net": True},
    }
    if runner_key == "docker":
        env_data["base"] = "x11-lite"
    (root / "env.json").write_text(json.dumps(env_data, indent=2))

    task_dir = root / "tasks" / "marker"
    task_dir.mkdir(parents=True)
    task_data = {
        "id": "marker",
        "env_id": env_data["id"],
        "hooks": {"pre_task": _linux_marker_hook(runner_key), "pre_task_timeout": 60},
        "success": {"mode": "program", "spec": {"program": "verifier.py::verify"}},
        "metadata": {"post_task_settle_sec": 0},
    }
    (task_dir / "task.json").write_text(json.dumps(task_data, indent=2))
    (task_dir / "verifier.py").write_text(
        "def verify(*args, **kwargs):\n"
        '    return {"passed": True, "score": 100.0}\n'
    )


def _assert_marker_visible(testcase: unittest.TestCase, screenshot_path: Path, resolution: tuple[int, int]) -> None:
    testcase.assertTrue(screenshot_path.exists(), f"Missing screenshot artifact: {screenshot_path}")
    image = Image.open(screenshot_path).convert("RGB")
    testcase.assertEqual(image.size, resolution)

    total_pixels = image.size[0] * image.size[1]
    magenta_pixels = 0
    green_pixels = 0
    for r, g, b in image.getdata():
        if abs(r - _MAGENTA[0]) <= 40 and g <= 70 and abs(b - _MAGENTA[2]) <= 40:
            magenta_pixels += 1
        if r <= 80 and abs(g - _GREEN[1]) <= 60 and b <= 80:
            green_pixels += 1

    testcase.assertGreater(
        magenta_pixels / total_pixels,
        0.05,
        "Expected the rendered marker window to occupy a visible portion of the screenshot.",
    )
    testcase.assertGreater(
        green_pixels,
        200,
        "Expected marker text/foreground signal to be visible in the screenshot.",
    )


class RunnerContractClassificationTests(unittest.TestCase):
    def test_runner_profiles_cover_public_registry(self) -> None:
        self.assertEqual(set(list_supported_runners()), set(RUNNER_PROFILES))


class RunnerUnsupportedContractTests(unittest.TestCase):
    def test_unavailable_desktop_runners_fail_explicitly(self) -> None:
        statuses = get_runner_status()

        for runner_key in _desktop_linux_runner_keys():
            status = statuses[runner_key]
            if status.get("available"):
                continue

            with self.subTest(runner=runner_key):
                spec = _make_runner_spec(
                    runner_key=runner_key,
                    output_dir=str(Path(tempfile.gettempdir()) / f"ga-test-{runner_key}-unsupported"),
                )
                runner_cls = _runner_class_for(runner_key)
                runner = None
                try:
                    with self.assertRaises(Exception) as cm:
                        runner = runner_cls(spec)
                        runner.start(seed=1)
                    lower = str(cm.exception).lower()
                    hints = _unsupported_hints_for(runner_key, status)
                    self.assertTrue(
                        any(hint in lower for hint in hints),
                        f"{runner_key} failed without an explicit unsupported reason. "
                        f"error={cm.exception!r} hints={hints}",
                    )
                finally:
                    if runner is not None:
                        try:
                            runner.stop()
                        except Exception:
                            pass


@unittest.skipUnless(
    os.environ.get(_EXECUTION_ENV) == "1",
    f"Set {_EXECUTION_ENV}=1 to run real runner execution tests.",
)
class RunnerExecutionContractTests(unittest.TestCase):
    def test_desktop_runners_either_report_unsupported_or_render_a_real_marker(self) -> None:
        statuses = get_runner_status()
        selected = _selected_execution_runners()
        if not selected:
            self.skipTest(f"No desktop runners selected via {_RUNNER_FILTER_ENV}.")

        for runner_key in selected:
            with self.subTest(runner=runner_key):
                status = statuses[runner_key]
                if not status.get("available"):
                    self._assert_explicitly_unsupported(runner_key, status)
                    continue
                self._assert_runner_renders_marker(runner_key)

    def _assert_explicitly_unsupported(self, runner_key: str, status: dict[str, object]) -> None:
        spec = _make_runner_spec(
            runner_key=runner_key,
            output_dir=str(Path(tempfile.gettempdir()) / f"ga-test-{runner_key}-unsupported"),
        )
        runner_cls = _runner_class_for(runner_key)
        runner = None
        try:
            with self.assertRaises(Exception) as cm:
                runner = runner_cls(spec)
                runner.start(seed=1)
            lower = str(cm.exception).lower()
            hints = _unsupported_hints_for(runner_key, status)
            self.assertTrue(
                any(hint in lower for hint in hints),
                f"{runner_key} failed without an explicit unsupported reason. "
                f"error={cm.exception!r} hints={hints}",
            )
        finally:
            if runner is not None:
                try:
                    runner.stop()
                except Exception:
                    pass

    def _assert_runner_renders_marker(self, runner_key: str) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            _write_execution_env(root, runner_key=runner_key)
            env = from_config(root, "marker")

            try:
                observation = env.reset(seed=1)
                self.assertIn("screen", observation)

                info = env.get_session_info()
                self.assertIsNotNone(info)
                self.assertEqual(info.platform_family, "linux")

                screenshot_path = Path(observation["screen"]["path"])
                _assert_marker_visible(self, screenshot_path, resolution=(1280, 720))
            finally:
                env.close()
