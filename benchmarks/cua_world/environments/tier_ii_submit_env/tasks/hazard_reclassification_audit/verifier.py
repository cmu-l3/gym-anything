#!/usr/bin/env python3
"""
Verifier for hazard_reclassification_audit task.

Scoring (100 pts total, pass threshold: 60):
  Chlorine (CAS 7782-50-5) — 3 missing hazards to add:
    17 pts — Acute toxicity (any route of exposure) = true
    17 pts — Gas under pressure (compressed gas) = true
    16 pts — Skin corrosion or irritation = true
  Fluorosilic Acid (CAS 16961-83-4) — 3 missing hazards to add:
    17 pts — Acute toxicity (any route of exposure) = true
    17 pts — Skin corrosion or irritation = true
    16 pts — Serious eye damage or eye irritation = true

Do-nothing baseline: Both chemicals have incomplete hazards → score=0, passed=False.
"""
import json
import os
import tempfile


RESULT_PATH = "C:\\Users\\Docker\\Desktop\\hazard_reclassification_audit_result.json"

# Expected corrections: hazards that must be "true" after the agent acts.
# These are all "false" in the baseline.
EXPECTED_FIXES = {
    "7782-50-5": {  # Chlorine
        "label": "Chlorine",
        "fixes": [
            ("Acute toxicity (any route of exposure)", 17),
            ("Gas under pressure (compressed gas)", 17),
            ("Skin corrosion or irritation", 16),
        ],
    },
    "16961-83-4": {  # Fluorosilic Acid
        "label": "Fluorosilic Acid",
        "fixes": [
            ("Acute toxicity (any route of exposure)", 17),
            ("Skin corrosion or irritation", 17),
            ("Serious eye damage or eye irritation", 16),
        ],
    },
}


def verify_hazard_reclassification_audit(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    metadata = task_info.get("metadata", {})
    result_file = metadata.get("result_file", RESULT_PATH)
    pass_threshold = metadata.get("pass_threshold", 60)

    # Copy result JSON from VM
    tmp = tempfile.NamedTemporaryFile(suffix=".json", delete=False)
    try:
        copy_from_env(result_file, tmp.name)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Export file not found: {e}",
        }

    try:
        with open(tmp.name, "r", encoding="utf-8-sig") as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not parse result JSON: {e}",
        }
    finally:
        try:
            os.unlink(tmp.name)
        except Exception:
            pass

    # Do-nothing gate: file must exist
    if not result.get("file_exists", False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Output .t2s file not found (do-nothing detected).",
        }

    chemicals = result.get("chemicals", [])
    if not chemicals:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No chemicals found in exported .t2s.",
        }

    # Build CAS → hazards map
    cas_map = {}
    for chem in chemicals:
        cas = chem.get("cas", "")
        hazards = chem.get("hazards", {})
        cas_map[cas] = hazards

    score = 0
    feedback_parts = []

    for cas, spec in EXPECTED_FIXES.items():
        label = spec["label"]
        hazards = cas_map.get(cas, {})
        if not hazards:
            feedback_parts.append(f"FAIL: {label} (CAS {cas}) not found in export")
            continue

        for hazard_name, points in spec["fixes"]:
            val = str(hazards.get(hazard_name, "false")).lower().strip()
            if val == "true":
                score += points
                feedback_parts.append(f"PASS: {label} — {hazard_name} = true (+{points})")
            else:
                feedback_parts.append(f"FAIL: {label} — {hazard_name} = {val} (expected true)")

    passed = score >= pass_threshold
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts),
    }
