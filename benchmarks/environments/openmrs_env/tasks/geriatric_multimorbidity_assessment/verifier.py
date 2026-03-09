#!/usr/bin/env python3
"""
Verifier: geriatric_multimorbidity_assessment

Checks that the nurse completed all three documentation tasks for Corie Bergnaum:
  1. Recorded clinic vitals (BP 162/88, Weight 62 kg, Pulse 72, Temp 36.8 C)
  2. Added Migraine condition (Confirmed)
  3. Ordered Acetaminophen 500mg medication

Scoring: 33 + 34 + 33 = 100 pts; pass threshold = 67 / 100.
"""

import json
import os
import tempfile


def verify_geriatric_multimorbidity_assessment(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    result_path = (task_info.get("metadata", {}) or {}).get(
        "result_file", "/tmp/geriatric_multimorbidity_assessment_result.json"
    )

    with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
        tmp_path = tmp.name

    try:
        copy_from_env(result_path, tmp_path)
        with open(tmp_path, encoding="utf-8") as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not read result file from VM: {e}",
        }
    finally:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)

    score = 0
    feedback_parts = []

    # --- Criterion 1: Vitals (33 pts, partial 15 pts) ---
    vitals_ok = result.get("vitals_recorded", False)
    vitals_details = result.get("vitals_details", {})
    if vitals_ok:
        score += 33
        feedback_parts.append(
            "PASS [33/33]: All vitals recorded within acceptable range "
            "(BP systolic 154-170, Weight 57-67 kg, Pulse 64-80, Temp 36.5-37.1 C)."
        )
    else:
        present = [k for k, v in vitals_details.items() if v]
        missing = [k for k, v in vitals_details.items() if not v]
        if len(present) >= 2:
            score += 15
            feedback_parts.append(
                f"PARTIAL [15/33]: Some vitals recorded ({', '.join(present)}) "
                f"but missing/out-of-range: {', '.join(missing)}."
            )
        elif len(present) == 1:
            score += 7
            feedback_parts.append(
                f"PARTIAL [7/33]: Only {present[0]} recorded; "
                f"missing: {', '.join(missing)}."
            )
        else:
            feedback_parts.append(
                "FAIL [0/33]: No valid vitals recorded. "
                "Required: BP 162/88, Weight 62 kg, Pulse 72, Temp 36.8 C."
            )

    # --- Criterion 2: Migraine condition (34 pts) ---
    migraine_ok = result.get("migraine_condition_added", False)
    if migraine_ok:
        score += 34
        feedback_parts.append(
            "PASS [34/34]: Migraine condition added to active problem list."
        )
    else:
        feedback_parts.append(
            "FAIL [0/34]: Migraine condition not found. "
            "Required: add 'Migraine' as a Confirmed condition."
        )

    # --- Criterion 3: Acetaminophen order (33 pts) ---
    med_ok = result.get("acetaminophen_ordered", False)
    if med_ok:
        score += 33
        feedback_parts.append(
            "PASS [33/33]: Acetaminophen medication order placed successfully."
        )
    else:
        feedback_parts.append(
            "FAIL [0/33]: Acetaminophen order not found. "
            "Required: order Acetaminophen (any strength/form) as a new drug order."
        )

    passed = score >= 67
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts),
    }
