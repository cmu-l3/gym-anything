"""Smoke verifier for macfuse_env: passes when the macFUSE bundle is on disk
with a readable version and the userspace mount helper is present. Uses
`exec_capture` only — no AX calls, no copy_from_env round-trip needed.
"""

from __future__ import annotations

from typing import Any, Dict


BUNDLE_PATH = "/Library/Filesystems/macfuse.fs"
INFO_PLIST = f"{BUNDLE_PATH}/Contents/Info.plist"
MOUNT_HELPER = f"{BUNDLE_PATH}/Contents/Resources/mount_macfuse"


def verify_macfuse_installed(
    traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]
) -> Dict[str, Any]:
    del traj, task_info
    exec_capture = env_info["exec_capture"]

    bundle_present = bool(exec_capture(
        f"test -d {BUNDLE_PATH} && echo yes || echo no"
    ).strip() == "yes")

    version = exec_capture(
        f"/usr/bin/defaults read {BUNDLE_PATH}/Contents/Info CFBundleShortVersionString 2>/dev/null || true"
    ).strip()
    version_readable = bool(version) and version.lower() != "unknown"

    mount_helper_present = bool(exec_capture(
        f"test -x {MOUNT_HELPER} && echo yes || echo no"
    ).strip() == "yes")

    passed = bundle_present and version_readable and mount_helper_present
    if passed:
        score = 100
    else:
        score = 0
        if bundle_present:
            score += 40
        if version_readable:
            score += 30
        if mount_helper_present:
            score += 30
        # Cap below 100 so partial never crosses pass — full requires all 3.
        if not passed and score >= 100:
            score = 70

    feedback = (
        f"bundle_present={bundle_present}; "
        f"version={version!r} (readable={version_readable}); "
        f"mount_helper_present={mount_helper_present}"
    )
    return {"passed": passed, "score": score, "feedback": feedback}
