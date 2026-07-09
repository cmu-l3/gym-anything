"""Verifier for ntfs_automount_agent on macOS / macfuse_env.

Scoring (100 points, pass at 70):
    10 pts  C1   Homebrew binary present at any of the canonical Homebrew
                 prefixes (/opt/homebrew, /usr/local, linuxbrew).
    15 pts  C2   ntfs-3g (or its mount_ntfs helper) binary present, indicating
                 that `brew install gromgit/fuse/ntfs-3g-mac` actually ran and
                 produced a usable mount tool. Probes both Apple Silicon and
                 Intel Homebrew prefixes plus the explicit `opt/ntfs-3g-mac`
                 cellar symlinks.
    20 pts  C3   ~/Documents/ntfs-automount.sh exists, is executable, AND
                 contains a `diskutil` invocation.
                 Partial: 5 pts if the file exists but is not executable OR
                 does not mention diskutil (gate-style partial; total partial
                 contribution = 5 pts).
    15 pts  C4   ntfs-automount.sh contains an NTFS-detection substring —
                 either `Windows_NTFS` (the verbatim `diskutil info` value
                 for the File System Personality field) or a bare `NTFS`.
    15 pts  C5   ntfs-automount.sh contains a mount invocation — either
                 `ntfs-3g` or `mount_ntfs`.
     5 pts  C6   ~/Documents/ntfs-unmount.sh exists AND is executable.
    20 pts  C7   ~/Library/LaunchAgents/com.lume.ntfs-automount.plist exists,
                 parses, has Label == "com.lume.ntfs-automount", has a
                 WatchPaths key whose array contains "/Volumes".

Partial-credit upper bound (Anti-Pattern 4 safety):
    Only C3 has a partial (5 pts). Sum of partials = 5. Pass threshold 70
    > 5 by a wide margin, so partial credit alone cannot pass the task.

Strategy enumeration (Anti-Pattern 13):
    Do-nothing                         → 0     (no files, no binaries)
    Files-only (no Homebrew/ntfs-3g)   → 20 + 15 + 15 + 5 + 20 = 75? — wait,
                                          this would PASS without installing
                                          tools. Re-derive: scripts + plist
                                          alone score C3+C4+C5+C6+C7
                                          = 20+15+15+5+20 = 75 ≥ 70. THIS
                                          IS A LEAK. Fix below.
    Install-only (no scripts/plist)    → 10 + 15 = 25  → safely below 70.
    Correct behavior                   → 100 → passes.

    The "files-only" leak would let an agent pass by writing the three
    artifacts without ever running brew. To close it, the verifier requires
    EITHER (a) C1 + C2 both satisfied OR (b) the C3 mount-command criterion
    references a path that resolves to an actual binary on disk — but
    enforcing the latter from a static script is unreliable (the agent may
    use $PATH lookup, not an absolute path). The clean fix: gate the
    high-value plist + mount-command criteria on "Homebrew present" so
    that without brew the agent caps at 10 + (gated 0) + 20-partial(5) +
    0 + 0 + 5 + 0 = 20 max. See `gates` section below for the exact rule.

Gates:
- Gate 1 (no work): no scripts, no plist, no brew → score 0.
- Gate 2 (no tool install): if BOTH brew_present=False AND ntfs3g_present=False,
  cap the total at 50 (below pass threshold). This forces a passing agent to
  actually run brew, not just write scripts.

Read pattern: copy_from_env(/tmp/ntfs_automount_agent_result.json, local_tmp)
— produced by export_result.sh.
"""

from __future__ import annotations

import json
import logging
import os
import tempfile
from typing import Any, Dict


logger = logging.getLogger(__name__)

REMOTE_RESULT = "/tmp/ntfs_automount_agent_result.json"
PASS_THRESHOLD = 70
NO_TOOL_INSTALL_CAP = 50


def _empty_subscores() -> Dict[str, int]:
    return {
        "homebrew_installed": 0,
        "ntfs3g_binary": 0,
        "automount_script": 0,
        "automount_ntfs_detection": 0,
        "automount_mount_command": 0,
        "unmount_script": 0,
        "launchagent_plist": 0,
    }


def verify_ntfs_automount_agent(
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

    # Pull export JSON to a local temp file and parse.
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

    brew_present = bool(data.get("brew_present", False))
    ntfs3g_present = bool(data.get("ntfs3g_present", False))

    automount_exists = bool(data.get("automount_sh_exists", False))
    automount_exec = bool(data.get("automount_sh_executable", False))
    automount_has_diskutil = bool(data.get("automount_sh_has_diskutil", False))
    automount_has_ntfs = bool(data.get("automount_sh_has_ntfs_check", False))
    automount_has_mount = bool(data.get("automount_sh_has_mount_cmd", False))

    unmount_exists = bool(data.get("unmount_sh_exists", False))
    unmount_exec = bool(data.get("unmount_sh_executable", False))

    plist_exists = bool(data.get("plist_exists", False))
    plist_valid = bool(data.get("plist_valid", False))
    plist_label_correct = bool(data.get("plist_label_correct", False))
    plist_watchpaths_has_volumes = bool(data.get("plist_watchpaths_has_volumes", False))

    # ---- Gate 1: no work at all ----
    if (
        not brew_present
        and not ntfs3g_present
        and not automount_exists
        and not unmount_exists
        and not plist_exists
    ):
        return {
            "score": 0,
            "passed": False,
            "feedback": "No evidence of task completion: no Homebrew, no ntfs-3g, "
                        "no scripts, no LaunchAgent plist.",
            "subscores": _empty_subscores(),
        }

    subscores = _empty_subscores()
    feedback: list[str] = []

    # ---- C1: Homebrew installed (10 pts) ----
    if brew_present:
        subscores["homebrew_installed"] = 10
        feedback.append(f"Homebrew at {data.get('brew_path', '')!r} (+10)")
    else:
        feedback.append("Homebrew not installed (+0)")

    # ---- C2: ntfs-3g binary (15 pts) ----
    if ntfs3g_present:
        subscores["ntfs3g_binary"] = 15
        feedback.append(f"ntfs-3g binary at {data.get('ntfs3g_path', '')!r} (+15)")
    else:
        feedback.append("No ntfs-3g binary found in any Homebrew prefix (+0)")

    # ---- C3: automount.sh exists, executable, contains diskutil (20 pts) ----
    if automount_exists and automount_exec and automount_has_diskutil:
        subscores["automount_script"] = 20
        feedback.append("ntfs-automount.sh exists, executable, mentions diskutil (+20)")
    elif automount_exists:
        subscores["automount_script"] = 5
        bits = []
        if not automount_exec:
            bits.append("not executable")
        if not automount_has_diskutil:
            bits.append("no diskutil call")
        feedback.append(f"ntfs-automount.sh exists but {', '.join(bits) or 'incomplete'} (+5)")
    else:
        feedback.append("ntfs-automount.sh missing (+0)")

    # ---- C4: NTFS detection substring (15 pts) ----
    if automount_exists and automount_has_ntfs:
        subscores["automount_ntfs_detection"] = 15
        feedback.append("ntfs-automount.sh has NTFS detection (+15)")
    else:
        feedback.append("ntfs-automount.sh missing NTFS detection (+0)")

    # ---- C5: mount command substring (15 pts) ----
    if automount_exists and automount_has_mount:
        subscores["automount_mount_command"] = 15
        feedback.append("ntfs-automount.sh has ntfs-3g/mount_ntfs invocation (+15)")
    else:
        feedback.append("ntfs-automount.sh missing mount command (+0)")

    # ---- C6: unmount.sh exists + executable (5 pts) ----
    if unmount_exists and unmount_exec:
        subscores["unmount_script"] = 5
        feedback.append("ntfs-unmount.sh exists and executable (+5)")
    elif unmount_exists:
        feedback.append("ntfs-unmount.sh exists but not executable (+0)")
    else:
        feedback.append("ntfs-unmount.sh missing (+0)")

    # ---- C7: LaunchAgent plist (20 pts) ----
    if plist_exists and plist_valid and plist_label_correct and plist_watchpaths_has_volumes:
        subscores["launchagent_plist"] = 20
        feedback.append("LaunchAgent plist has correct Label and WatchPaths=[/Volumes] (+20)")
    else:
        bits = []
        if not plist_exists:
            bits.append("not present")
        elif not plist_valid:
            bits.append("unparseable")
        else:
            if not plist_label_correct:
                bits.append("wrong/missing Label")
            if not plist_watchpaths_has_volumes:
                bits.append("WatchPaths does not include /Volumes")
        feedback.append(f"LaunchAgent plist: {', '.join(bits) or 'incomplete'} (+0)")

    total = sum(subscores.values())

    # ---- Gate 2: no tool install → cap at NO_TOOL_INSTALL_CAP ----
    # Closes the "files-only" shortcut described in the module docstring's
    # strategy enumeration. If neither brew nor ntfs-3g is installed, the
    # agent has not actually built an NTFS automount system — they have
    # written hopeful-looking text files. Cap below the pass threshold.
    capped = False
    if not brew_present and not ntfs3g_present:
        if total > NO_TOOL_INSTALL_CAP:
            feedback.append(
                f"GATE: neither Homebrew nor ntfs-3g installed — score capped at "
                f"{NO_TOOL_INSTALL_CAP} (was {total})"
            )
            total = NO_TOOL_INSTALL_CAP
            capped = True

    passed = total >= pass_threshold
    if passed:
        feedback.insert(
            0,
            f"PASSED ({total}/100, threshold {pass_threshold}): NTFS automount "
            f"system in place.",
        )
    else:
        feedback.insert(
            0,
            f"FAILED ({total}/100, threshold {pass_threshold}): NTFS automount "
            f"setup incomplete.",
        )

    return {
        "score": total,
        "passed": passed,
        "feedback": " | ".join(feedback),
        "subscores": subscores,
    }
