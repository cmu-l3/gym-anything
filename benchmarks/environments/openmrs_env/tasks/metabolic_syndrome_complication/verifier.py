#!/usr/bin/env python3
"""
Verifier: metabolic_syndrome_complication

Checks that the nurse completed all three documentation tasks for Yolando Flatley:
  1. Recorded clinic vitals (BP 158/96, Weight 102 kg, Pulse 78, Temp 37.0 C)
  2. Added Obesity condition (Confirmed)
  3. Scheduled an endocrinology follow-up appointment within 21 days

Scoring: 33 + 34 + 33 = 100 pts; pass threshold = 67 / 100.
"""

import json
import os
import tempfile


def verify_metabolic_syndrome_complication(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    result_path = (task_info.get("metadata", {}) or {}).get(
        "result_file", "/tmp/metabolic_syndrome_complication_result.json"
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
            "PASS [33/33]: All clinic vitals recorded within acceptable range "
            "(BP systolic 150-166, Weight 97-107 kg, Pulse 70-86, Temp 36.7-37.3 C)."
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
                f"PARTIAL [7/33]: Only {present[0]} recorded; missing: {', '.join(missing)}."
            )
        else:
            feedback_parts.append(
                "FAIL [0/33]: No valid vitals recorded. "
                "Required: BP 158/96, Weight 102 kg, Pulse 78, Temp 37.0 C."
            )

    # --- Criterion 2: Obesity condition (34 pts) ---
    obesity_ok = result.get("obesity_condition_added", False)
    if obesity_ok:
        score += 34
        feedback_parts.append(
            "PASS [34/34]: Obesity condition added to active problem list."
        )
    else:
        feedback_parts.append(
            "FAIL [0/34]: Obesity condition not found. "
            "Required: add 'Obesity' as a Confirmed condition."
        )

    # --- Criterion 3: Appointment within 21 days (33 pts) ---
    appt_ok = result.get("appointment_added", False)
    if appt_ok:
        score += 33
        feedback_parts.append(
            "PASS [33/33]: Follow-up appointment scheduled within 21-day window."
        )
    else:
        feedback_parts.append(
            "FAIL [0/33]: No new appointment found. "
            "Required: schedule any appointment within 21 days."
        )

    passed = score >= 67
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts),
    }
