from __future__ import annotations

import shlex
import time
from typing import Optional


_GIMP_WINDOW = "GIMP"
_BROWSER_WINDOW = "Chrome"


def get_window_id_with_retry(env, window_string: str) -> str:
    quoted_window_string = shlex.quote(window_string)
    for retry in range(10):
        wid = env._runner.exec_capture(
            "DISPLAY=:1 "
            "XAUTHORITY=$(find /run/user -name Xauthority 2>/dev/null | head -1) "
            f"wmctrl -l | grep -i {quoted_window_string} | awk '{{print $1; exit}}'"
        ).strip()
        if "failed request:" in wid.lower():
            time.sleep(retry ** 2 * 2 + 1)
            continue
        return wid
    return ""


def make_display_full_screen(env, window_string: str = _GIMP_WINDOW) -> str:
    time.sleep(5)

    wid = get_window_id_with_retry(env, window_string)
    if wid == "":
        env._runner.exec(
            "DISPLAY=:1 XAUTHORITY=$(find /run/user -name Xauthority 2>/dev/null | head -1) xdotool key Return"
        )
        wid = get_window_id_with_retry(env, window_string)
    if wid == "":
        return ""

    env._runner.exec(
        f"DISPLAY=:1 XAUTHORITY=$(find /run/user -name Xauthority 2>/dev/null | head -1) wmctrl -ia {wid}"
    )
    time.sleep(1)
    env._runner.exec(
        "DISPLAY=:1 XAUTHORITY=$(find /run/user -name Xauthority 2>/dev/null | head -1) xdotool key --delay 200 F11"
    )
    time.sleep(1)
    return wid


def apply_episode_limits(env, steps: Optional[int]) -> int:
    resolved_steps = steps or (env.task_spec.init.max_steps if env.task_spec else 10)
    env.set_episode_limits(max_steps=resolved_steps, timeout_sec=120000)
    return resolved_steps


def resolve_default_post_reset_setup(env, env_dir: Optional[str] = None) -> str:
    haystacks = [
        getattr(getattr(env, "env_spec", None), "id", "") or "",
        env_dir or "",
    ]
    combined = " ".join(haystacks).lower()
    if "gimp" in combined:
        return "gimp_standard_fullscreen"
    if any(token in combined for token in ("chrome", "chromium", "browser", "firefox", "edge")):
        return "chrome_standard_fullscreen"
    return "none"


def apply_post_reset_setup(
    env,
    setup_code: str = "auto",
    steps: Optional[int] = None,
    *,
    env_dir: Optional[str] = None,
) -> bool:
    resolved_setup = setup_code
    if resolved_setup == "auto":
        resolved_setup = resolve_default_post_reset_setup(env, env_dir=env_dir)
    if resolved_setup == "none":
        return True

    apply_episode_limits(env, steps)
    if resolved_setup == "gimp_standard_fullscreen":
        return make_display_full_screen(env, window_string=_GIMP_WINDOW) != ""
    if resolved_setup == "chrome_standard_fullscreen":
        return True
    raise ValueError(f"Unsupported post-reset setup code: {resolved_setup}")


__all__ = [
    "apply_episode_limits",
    "apply_post_reset_setup",
    "get_window_id_with_retry",
    "make_display_full_screen",
    "resolve_default_post_reset_setup",
]
