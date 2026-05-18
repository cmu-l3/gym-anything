"""Verifier for gocryptfs_personal_vault on macOS / macfuse_env.

Scoring (100 points, pass at 70):
     5 pts  C1   Homebrew installed (brew binary present and executable).
    15 pts  C2   gocryptfs binary installed (executable at one of the
                 Homebrew bin paths; the gocryptfs-mac package).
    20 pts  C3   ~/Documents/vault.enc/ initialized — directory exists AND
                 contains gocryptfs.conf (the gocryptfs init config file).
                 Without gocryptfs.conf the directory is just an mkdir, which
                 the agent gets no credit for.
     5 pts  C4   ~/Documents/vault.plain/ exists as a directory.
    20 pts  C5   ~/Documents/mount_vault.sh complete — file exists,
                 executable bit set, contains the substring "gocryptfs".
     5 pts  C6   ~/Documents/umount_vault.sh complete — file exists,
                 executable bit set, contains "umount" or "diskutil unmount".
    20 pts  C7   LaunchAgent plist correct — divided into 4 sub-conditions
                 of 5 pts each:
                   - parses + Label matches "com.lume.gocryptfs.vault"  (5)
                   - RunAtLoad is boolean true                          (5)
                   - StandardOutPath AND StandardErrorPath are non-empty (5)
                   - ProgramArguments references mount_vault.sh         (5)
    10 pts  C8   launchctl list contains "com.lume.gocryptfs.vault"
                 (proves the agent ran `launchctl load`).

Anti-Pattern 4 safety: max partial-only credit is C4 (5, trivial mkdir) +
C6 (5, trivial umount stub) = 10/100, far below 70 pass threshold.

Anti-Pattern 13 strategy enumeration: the "no LaunchAgent" path scores 70
(install + init + scripts) — right at threshold. The full happy path scores
100. The mass-guess / do-nothing paths score 0.

Read pattern: copy_from_env(/tmp/gocryptfs_personal_vault_result.json,
local_tmp) — produced by export_result.sh.
"""

from __future__ import annotations

import json
import logging
import os
import tempfile
from typing import Any, Dict, List


logger = logging.getLogger(__name__)

REMOTE_RESULT = "/tmp/gocryptfs_personal_vault_result.json"
PASS_THRESHOLD = 70


def _empty_subscores() -> Dict[str, int]:
    return {
        "C1_brew": 0,
        "C2_gocryptfs": 0,
        "C3_vault_enc_initialized": 0,
        "C4_vault_plain": 0,
        "C5_mount_script": 0,
        "C6_umount_script": 0,
        "C7_plist": 0,
        "C8_launchctl_loaded": 0,
    }


def verify_gocryptfs_personal_vault(
    traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]
) -> Dict[str, Any]:
    del traj
    copy_from_env = env_info.get("copy_from_env")
    if copy_from_env is None:
        return {
            "score": 0,
            "passed": False,
            "feedback": "env_info missing copy_from_env — verifier cannot read sandbox state.",
            "subscores": _empty_subscores(),
        }

    metadata = (task_info or {}).get("metadata", {}) or {}
    pass_threshold = int(metadata.get("pass_threshold", PASS_THRESHOLD))

    # Pull the export JSON into a host-side temp file.
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
    feedback: List[str] = []

    # ---- C1: Homebrew installed (5 pts) ----
    if bool(data.get("brew_installed")):
        subscores["C1_brew"] = 5
        feedback.append(
            f"C1 PASS: brew installed at {data.get('brew_path')!r} (+5)"
        )
    else:
        feedback.append("C1 FAIL: brew not found at /opt/homebrew/bin or /usr/local/bin (+0)")

    # ---- C2: gocryptfs binary installed (15 pts) ----
    if bool(data.get("gocryptfs_installed")):
        subscores["C2_gocryptfs"] = 15
        feedback.append(
            f"C2 PASS: gocryptfs at {data.get('gocryptfs_path')!r} (+15)"
        )
    else:
        feedback.append(
            "C2 FAIL: gocryptfs binary not found — install via "
            "`brew install gromgit/fuse/gocryptfs-mac` (+0)"
        )

    # ---- C3: vault.enc initialized (20 pts) ----
    # Full credit requires BOTH the directory AND gocryptfs.conf — the conf
    # file is the proof that `gocryptfs -init` actually ran. An agent that
    # just `mkdir`'d the directory without running -init does not get credit.
    enc_exists = bool(data.get("vault_enc_exists"))
    enc_conf = bool(data.get("vault_enc_conf_exists"))
    if enc_exists and enc_conf:
        subscores["C3_vault_enc_initialized"] = 20
        feedback.append(
            "C3 PASS: ~/Documents/vault.enc/ exists with gocryptfs.conf (+20)"
        )
    elif enc_exists and not enc_conf:
        feedback.append(
            "C3 FAIL: vault.enc directory exists but no gocryptfs.conf — "
            "did you run `gocryptfs -init`? (+0)"
        )
    else:
        feedback.append("C3 FAIL: ~/Documents/vault.enc/ not present (+0)")

    # ---- C4: vault.plain mountpoint (5 pts) ----
    if bool(data.get("vault_plain_exists")):
        subscores["C4_vault_plain"] = 5
        feedback.append("C4 PASS: ~/Documents/vault.plain/ exists (+5)")
    else:
        feedback.append("C4 FAIL: ~/Documents/vault.plain/ not present (+0)")

    # ---- C5: mount_vault.sh complete (20 pts) ----
    # All three sub-conditions required for credit. No partial credit here —
    # an executable script with no gocryptfs call is worthless; a script with
    # the call but no +x bit won't run.
    mount_exists = bool(data.get("mount_script_exists"))
    mount_exec = bool(data.get("mount_script_executable"))
    mount_has_gocryptfs = bool(data.get("mount_script_has_gocryptfs"))
    if mount_exists and mount_exec and mount_has_gocryptfs:
        subscores["C5_mount_script"] = 20
        feedback.append("C5 PASS: mount_vault.sh exists, executable, invokes gocryptfs (+20)")
    else:
        missing = []
        if not mount_exists:
            missing.append("file missing")
        if mount_exists and not mount_exec:
            missing.append("not executable")
        if mount_exists and not mount_has_gocryptfs:
            missing.append("no gocryptfs invocation")
        feedback.append(f"C5 FAIL: mount_vault.sh — {', '.join(missing) or 'unknown'} (+0)")

    # ---- C6: umount_vault.sh complete (5 pts) ----
    umount_exists = bool(data.get("umount_script_exists"))
    umount_exec = bool(data.get("umount_script_executable"))
    umount_has_unmount = bool(data.get("umount_script_has_unmount"))
    if umount_exists and umount_exec and umount_has_unmount:
        subscores["C6_umount_script"] = 5
        feedback.append(
            "C6 PASS: umount_vault.sh exists, executable, contains umount/diskutil unmount (+5)"
        )
    else:
        missing = []
        if not umount_exists:
            missing.append("file missing")
        if umount_exists and not umount_exec:
            missing.append("not executable")
        if umount_exists and not umount_has_unmount:
            missing.append("no umount/diskutil unmount command")
        feedback.append(f"C6 FAIL: umount_vault.sh — {', '.join(missing) or 'unknown'} (+0)")

    # ---- C7: LaunchAgent plist correct (20 pts, 4×5) ----
    plist_score = 0
    plist_parses = bool(data.get("plist_parses"))
    label_matches = bool(data.get("plist_label_matches"))
    run_at_load = bool(data.get("plist_run_at_load_true"))
    log_paths = bool(data.get("plist_log_paths_set"))
    prog_args = bool(data.get("plist_program_args_invokes_mount"))
    if plist_parses and label_matches:
        plist_score += 5
        feedback.append("C7a PASS: plist parses + Label=com.lume.gocryptfs.vault (+5)")
    else:
        if not data.get("plist_exists"):
            feedback.append("C7a FAIL: ~/Library/LaunchAgents/com.lume.gocryptfs.vault.plist not present (+0)")
        elif not plist_parses:
            feedback.append("C7a FAIL: plist does not parse (plutil convert failed) (+0)")
        else:
            feedback.append("C7a FAIL: Label mismatch — expected 'com.lume.gocryptfs.vault' (+0)")
    if run_at_load:
        plist_score += 5
        feedback.append("C7b PASS: RunAtLoad is boolean true (+5)")
    else:
        feedback.append("C7b FAIL: RunAtLoad not set to <true/> (+0)")
    if log_paths:
        plist_score += 5
        feedback.append("C7c PASS: StandardOutPath + StandardErrorPath both set (+5)")
    else:
        feedback.append("C7c FAIL: missing StandardOutPath or StandardErrorPath (+0)")
    if prog_args:
        plist_score += 5
        feedback.append("C7d PASS: ProgramArguments references mount_vault.sh (+5)")
    else:
        feedback.append(
            "C7d FAIL: ProgramArguments does not reference /Users/lume/Documents/mount_vault.sh (+0)"
        )
    subscores["C7_plist"] = plist_score

    # ---- C8: launchctl list contains label (10 pts) ----
    if bool(data.get("launch_agent_loaded")):
        subscores["C8_launchctl_loaded"] = 10
        feedback.append("C8 PASS: launchctl list contains com.lume.gocryptfs.vault (+10)")
    else:
        feedback.append(
            "C8 FAIL: launchctl list does not contain com.lume.gocryptfs.vault — "
            "did you run `launchctl load ...`? (+0)"
        )

    total = sum(subscores.values())
    passed = total >= pass_threshold
    if passed:
        feedback.insert(
            0,
            f"PASSED ({total}/100, threshold {pass_threshold}): "
            "gocryptfs personal vault configured end-to-end.",
        )
    else:
        feedback.insert(
            0,
            f"FAILED ({total}/100, threshold {pass_threshold}): "
            "vault setup incomplete.",
        )
    return {
        "score": total,
        "passed": passed,
        "feedback": " | ".join(feedback),
        "subscores": subscores,
    }
