"""Verifier for sshfs_home_nas_setup on macOS / macfuse_env.

Scoring (100 points, pass at 70):
    C1  10 pts  Homebrew installed (brew binary present on PATH or at the
                standard Apple Silicon / Intel prefix).
    C2  10 pts  `gromgit/fuse` tap added (visible in `brew tap`).
    C3  15 pts  `sshfs` binary exists at a discoverable path under the
                Homebrew prefix or on PATH.
    C4   5 pts  Mount point ~/NAS/ exists as a directory.
    C5  20 pts  SSH config has a working `Host homeserver` block. Split as:
                    5 host stanza present
                    5 hostname == 192.168.1.100
                    5 user == pi
                    5 IdentityFile set (non-empty value)
    C6  25 pts  Mount script in place. Split as:
                    5 file exists
                    5 file is executable (chmod +x)
                    5 contains `volname=` option
                    5 contains `reconnect` option
                    5 contains `defer_permissions` option
    C7  15 pts  LaunchAgent plist in place. Split as:
                    5 plist exists at the expected path with the correct Label
                    5 RunAtLoad=true AND KeepAlive=true
                    5 StandardOutPath or StandardErrorPath set

Anti-Pattern 4 (partial-credit ceiling): per-bucket scoring uses binary 5-pt
sub-checks within C5/C6/C7. A do-nothing agent that only creates ~/NAS/
scores 5/100 (C4 only), far below the 70 pass threshold.

Anti-Pattern 13 (strategy enumeration):
    Do nothing                           ->   0 (fail)
    NAS dir only                         ->   5 (fail)
    Plist + script (wrong opts)          ->  25 (fail)
    Homebrew+tap+sshfs, skip config      ->  40 (fail)
    Full setup minus defer_permissions   ->  95 (pass)
    Full setup                           -> 100 (pass)

The 70 threshold requires both the toolchain installation chain (Homebrew +
tap + sshfs, 35 pts) AND substantial configuration work (SSH config + mount
script + launchagent, 60 pts). Either chain alone is below 70.

Read pattern: copy_from_env(/tmp/sshfs_home_nas_setup_result.json,
local_tmp) — produced by export_result.sh.
"""

from __future__ import annotations

import json
import logging
import os
import tempfile
from typing import Any, Dict


logger = logging.getLogger(__name__)

REMOTE_RESULT = "/tmp/sshfs_home_nas_setup_result.json"
PASS_THRESHOLD = 70


def _empty_subscores() -> Dict[str, int]:
    return {
        "C1_brew_installed": 0,
        "C2_gromgit_tap": 0,
        "C3_sshfs_binary": 0,
        "C4_mount_point": 0,
        "C5_ssh_config": 0,
        "C6_mount_script": 0,
        "C7_launchagent": 0,
    }


def verify_sshfs_home_nas_setup(
    traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]
) -> Dict[str, Any]:
    del traj
    copy_from_env = env_info.get("copy_from_env")
    if copy_from_env is None:
        return {
            "score": 0,
            "passed": False,
            "feedback": "env_info missing copy_from_env",
            "subscores": _empty_subscores(),
        }

    metadata = (task_info or {}).get("metadata", {}) or {}
    pass_threshold = int(metadata.get("pass_threshold", PASS_THRESHOLD))

    # Pull the export JSON to a host-side temp file.
    with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as f:
        local_path = f.name
    try:
        try:
            copy_from_env(REMOTE_RESULT, local_path)
        except Exception as exc:
            logger.warning("copy_from_env failed: %s", exc)
            return {
                "score": 0,
                "passed": False,
                "feedback": f"Could not retrieve result file from sandbox: {exc}",
                "subscores": _empty_subscores(),
            }
        try:
            with open(local_path, "r", encoding="utf-8") as fh:
                data = json.load(fh)
        except Exception as exc:
            logger.warning("result JSON parse failed: %s", exc)
            return {
                "score": 0,
                "passed": False,
                "feedback": f"Export produced unparseable JSON: {exc}",
                "subscores": _empty_subscores(),
            }
    finally:
        try:
            os.unlink(local_path)
        except Exception:
            pass

    subscores = _empty_subscores()
    feedback: list[str] = []

    # ---- C1: Homebrew installed (10 pts) ----
    if bool(data.get("brew_installed")):
        subscores["C1_brew_installed"] = 10
        feedback.append(
            f"C1 PASS: brew at {data.get('brew_binary_path')!r} (+10)"
        )
    else:
        feedback.append(
            "C1 FAIL: no brew binary found at /opt/homebrew/bin/brew, "
            "/usr/local/bin/brew, or on PATH (+0)"
        )

    # ---- C2: gromgit/fuse tap added (10 pts) ----
    if bool(data.get("gromgit_tap_added")):
        subscores["C2_gromgit_tap"] = 10
        feedback.append("C2 PASS: gromgit/fuse tap is present (+10)")
    else:
        feedback.append("C2 FAIL: gromgit/fuse tap not in `brew tap` list (+0)")

    # ---- C3: sshfs binary exists (15 pts) ----
    sshfs_path = data.get("sshfs_binary_path")
    if sshfs_path:
        subscores["C3_sshfs_binary"] = 15
        feedback.append(f"C3 PASS: sshfs at {sshfs_path!r} (+15)")
    else:
        feedback.append(
            "C3 FAIL: sshfs binary not found at /opt/homebrew/bin/sshfs, "
            "/usr/local/bin/sshfs, or on PATH (+0)"
        )

    # ---- C4: mount point ~/NAS/ exists (5 pts) ----
    if bool(data.get("mount_point_exists")):
        subscores["C4_mount_point"] = 5
        feedback.append("C4 PASS: /Users/lume/NAS/ exists (+5)")
    else:
        feedback.append("C4 FAIL: /Users/lume/NAS/ does not exist (+5)")

    # ---- C5: SSH config homeserver block (20 pts, 5-pt sub-checks) ----
    c5_total = 0
    if bool(data.get("ssh_host_configured")):
        c5_total += 5
        feedback.append("C5a PASS: `Host homeserver` block present (+5)")
    else:
        feedback.append("C5a FAIL: no `Host homeserver` block in ~/.ssh/config (+0)")

    if bool(data.get("ssh_hostname_correct")):
        c5_total += 5
        feedback.append("C5b PASS: HostName 192.168.1.100 (+5)")
    else:
        feedback.append("C5b FAIL: HostName != 192.168.1.100 (+0)")

    if bool(data.get("ssh_user_correct")):
        c5_total += 5
        feedback.append("C5c PASS: User pi (+5)")
    else:
        feedback.append("C5c FAIL: User != pi (+0)")

    if bool(data.get("ssh_identity_file_set")):
        c5_total += 5
        feedback.append("C5d PASS: IdentityFile set (+5)")
    else:
        feedback.append("C5d FAIL: IdentityFile not set (+0)")

    subscores["C5_ssh_config"] = c5_total

    # ---- C6: mount script (25 pts, 5-pt sub-checks) ----
    c6_total = 0
    if bool(data.get("mount_script_exists")):
        c6_total += 5
        feedback.append("C6a PASS: ~/Documents/mount_nas.sh exists (+5)")
    else:
        feedback.append("C6a FAIL: ~/Documents/mount_nas.sh missing (+0)")

    if bool(data.get("mount_script_executable")):
        c6_total += 5
        feedback.append("C6b PASS: mount_nas.sh has +x bit (+5)")
    else:
        feedback.append("C6b FAIL: mount_nas.sh not executable (+0)")

    if bool(data.get("mount_script_has_volname")):
        c6_total += 5
        feedback.append("C6c PASS: mount script contains volname= (+5)")
    else:
        feedback.append("C6c FAIL: volname= option missing (+0)")

    if bool(data.get("mount_script_has_reconnect")):
        c6_total += 5
        feedback.append("C6d PASS: mount script contains reconnect (+5)")
    else:
        feedback.append("C6d FAIL: reconnect option missing (+0)")

    if bool(data.get("mount_script_has_defer_permissions")):
        c6_total += 5
        feedback.append("C6e PASS: mount script contains defer_permissions (+5)")
    else:
        feedback.append("C6e FAIL: defer_permissions option missing (+0)")

    subscores["C6_mount_script"] = c6_total

    # ---- C7: LaunchAgent plist (15 pts, 5-pt sub-checks) ----
    c7_total = 0
    if bool(data.get("launchagent_plist_exists")) and bool(data.get("launchagent_label_correct")):
        c7_total += 5
        feedback.append(
            "C7a PASS: plist exists at "
            "~/Library/LaunchAgents/com.lume.sshfs.homeserver.plist with "
            "correct Label (+5)"
        )
    else:
        feedback.append(
            "C7a FAIL: plist missing or Label != com.lume.sshfs.homeserver (+0)"
        )

    if bool(data.get("launchagent_has_runatload")) and bool(data.get("launchagent_has_keepalive")):
        c7_total += 5
        feedback.append("C7b PASS: RunAtLoad and KeepAlive both true (+5)")
    else:
        feedback.append("C7b FAIL: RunAtLoad and/or KeepAlive not set true (+0)")

    if bool(data.get("launchagent_has_logging")):
        c7_total += 5
        feedback.append(
            "C7c PASS: StandardOutPath/StandardErrorPath logging configured (+5)"
        )
    else:
        feedback.append("C7c FAIL: no Standard{Out,Error}Path logging set (+0)")

    subscores["C7_launchagent"] = c7_total

    total = sum(subscores.values())
    passed = total >= pass_threshold
    if passed:
        feedback.insert(
            0,
            f"PASSED ({total}/100, threshold {pass_threshold}): SSHFS home-NAS configuration complete.",
        )
    else:
        feedback.insert(
            0,
            f"FAILED ({total}/100, threshold {pass_threshold}): SSHFS home-NAS setup incomplete.",
        )
    return {
        "passed": passed,
        "score": total,
        "feedback": " | ".join(feedback),
        "subscores": subscores,
    }
