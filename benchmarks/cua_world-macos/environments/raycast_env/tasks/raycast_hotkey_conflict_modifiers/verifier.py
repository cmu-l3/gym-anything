"""Verifier for raycast_hotkey_conflict_modifiers.

Scoring (100 pts, pass >= 70):
  C1 — macOS system hotkey 64 ('Move focus to next window' = Cmd+`)        40 pts
        UNCHANGED — the agent did NOT touch the global system shortcut
        even while editing Raycast hotkeys.
  C2 — Raycast WAL grew by >= 500 bytes after setup                        25 pts
        (proxy: agent meaningfully edited Raycast hotkey settings, not
        just glanced at the panel; small WAL changes can happen from
        background reads)
  C3 — Rayconfig export file exists at expected path, new, valid           15 pts
        (gzipped JSON contents must decompress and contain 'hotkey' or
        'shortcut' keywords)
  C4 — Decompressed export mentions 'Quick AI' OR 'Notes' OR 'Clipboard'   20 pts
        (best-effort signal the export captured the relevant commands)

Raycast hotkey assignments live in encrypted local DB — we cannot directly
verify the specific bindings (single-tap fn, double-tap right option, left
control + space). Verification triangulates from observable proxies:
WAL delta + system-hotkey preservation + export content.
"""

import json
import os
import re
import tempfile

PASS_THRESHOLD = 70

CRITERION_POINTS = {
    "C1_macos_unchanged":  40,
    "C2_wal_delta_500":    25,
    "C3_export_valid":     15,
    "C4_export_mentions":  20,
}

EXPECTED_KEYWORDS = re.compile(
    r"\b(?:quick[\s-]*ai|raycast[\s-]*notes|clipboard[\s-]*history|hotkey|shortcut)\b",
    re.IGNORECASE,
)


def verify_hotkey_conflict_modifiers(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    result_path = "/tmp/raycast_hotkey_conflict_modifiers_result.json"
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        copy_from_env(result_path, tmp.name)
        with open(tmp.name, "r") as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0, "feedback": f"Result JSON malformed: {e}"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}
    finally:
        try:
            os.unlink(tmp.name)
        except Exception:
            pass

    score = 0
    feedback = []
    subscores = {}

    macos_unchanged = result.get("macos_hotkey_64_unchanged", False)
    wal_delta       = result.get("wal_size_delta", 0)
    export_exists   = result.get("export_file_exists", False)
    export_new      = result.get("export_file_is_new", False)
    export_size     = result.get("export_file_size_bytes", 0)
    export_preview  = result.get("export_content_preview", "") or ""

    # C1 — macOS hotkey untouched
    if macos_unchanged:
        score += CRITERION_POINTS["C1_macos_unchanged"]
        subscores["C1"] = CRITERION_POINTS["C1_macos_unchanged"]
        feedback.append("C1 PASS: macOS system hotkey 64 unchanged (agent stayed inside Raycast)")
    else:
        subscores["C1"] = 0
        feedback.append("C1 FAIL: macOS system hotkey 64 was modified or missing — agent touched global shortcut")

    # C2 — Raycast WAL delta >= 500 bytes
    if wal_delta >= 500:
        score += CRITERION_POINTS["C2_wal_delta_500"]
        subscores["C2"] = CRITERION_POINTS["C2_wal_delta_500"]
        feedback.append(f"C2 PASS: Raycast WAL grew by {wal_delta} bytes (settings edited)")
    else:
        subscores["C2"] = 0
        feedback.append(f"C2 FAIL: Raycast WAL delta only {wal_delta} bytes (< 500; settings likely unchanged)")

    # C3 — Export file valid
    if export_exists and export_new and export_size > 0:
        score += CRITERION_POINTS["C3_export_valid"]
        subscores["C3"] = CRITERION_POINTS["C3_export_valid"]
        feedback.append(f"C3 PASS: rayconfig export exists ({export_size} bytes)")
    else:
        subscores["C3"] = 0
        feedback.append("C3 FAIL: rayconfig export missing/stale/empty")

    # C4 — Export content mentions relevant keywords
    if EXPECTED_KEYWORDS.search(export_preview):
        score += CRITERION_POINTS["C4_export_mentions"]
        subscores["C4"] = CRITERION_POINTS["C4_export_mentions"]
        feedback.append("C4 PASS: export contents reference hotkey/Quick AI/Notes/Clipboard")
    else:
        subscores["C4"] = 0
        feedback.append("C4 FAIL: export contents do not mention expected Raycast commands")

    passed = score >= PASS_THRESHOLD

    return {
        "passed":    passed,
        "score":     score,
        "feedback":  " | ".join(feedback),
        "subscores": subscores,
    }
