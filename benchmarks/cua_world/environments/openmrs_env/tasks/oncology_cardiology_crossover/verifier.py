#!/usr/bin/env python3
"""
Verifier: oncology_cardiology_crossover

Checks that the nurse completed all three documentation tasks for Mateo Matias:
  1. Added Iodinated contrast media allergy (Urticaria / Moderate)
  2. Recorded cardio-oncology vitals (BP 128/78, Weight 72 kg, Pulse 66, Temp 37.2 C)
  3. Scheduled a cardio-oncology follow-up appointment within 28 days

Scoring: 33 + 34 + 33 = 100 pts; pass threshold = 67 / 100.
"""

import json
import os
import tempfile


def verify_oncology_cardiology_crossover(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    result_path = (task_info.get("metadata", {}) or {}).get(
        "result_file", "/tmp/oncology_cardiology_crossover_result.json"
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

    # --- Criterion 1: Iodinated contrast allergy (33 pts, partial 15 pts) ---
    allergy_added = result.get("contrast_allergy_added", False)
    severity_ok = result.get("allergy_severity_moderate", False)
    reaction_ok = result.get("allergy_reaction_urticaria", False)
    if allergy_added and severity_ok and reaction_ok:
        score += 33
        feedback_parts.append(
            "PASS [33/33]: Iodinated contrast media allergy documented with Urticaria reaction and Moderate severity."
        )
    elif allergy_added:
        score += 15
        parts = []
        if not severity_ok:
            parts.append("severity should be Moderate")
        if not reaction_ok:
            parts.append("reaction should be Urticaria or Hives")
        feedback_parts.append(
            f"PARTIAL [15/33]: Contrast media allergy found but incomplete — {'; '.join(parts)}."
        )
    else:
        feedback_parts.append(
            "FAIL [0/33]: Contrast media allergy not found. "
            "Required: Allergen=Iodinated contrast media, Reaction=Urticaria, Severity=Moderate."
        )

    # --- Criterion 2: Vitals (34 pts, partial 17 pts) ---
    vitals_ok = result.get("vitals_recorded", False)
    vitals_details = result.get("vitals_details", {})
    if vitals_ok:
        score += 34
        feedback_parts.append(
            "PASS [34/34]: All cardio-oncology vitals recorded within acceptable range "
            "(BP systolic 120-136, Weight 67-77 kg, Pulse 58-74, Temp 36.9-37.5 C)."
        )
    else:
        present = [k for k, v in vitals_details.items() if v]
        missing = [k for k, v in vitals_details.items() if not v]
        if len(present) >= 2:
            score += 17
            feedback_parts.append(
                f"PARTIAL [17/34]: Some vitals recorded ({', '.join(present)}) "
                f"but missing/out-of-range: {', '.join(missing)}."
            )
        elif len(present) == 1:
            score += 8
            feedback_parts.append(
                f"PARTIAL [8/34]: Only {present[0]} recorded; missing: {', '.join(missing)}."
            )
        else:
            feedback_parts.append(
                "FAIL [0/34]: No valid vitals recorded. "
                "Required: BP 128/78, Weight 72 kg, Pulse 66, Temp 37.2 C."
            )

    # --- Criterion 3: Appointment within 28 days (33 pts) ---
    appt_ok = result.get("appointment_added", False)
    if appt_ok:
        score += 33
        feedback_parts.append(
            "PASS [33/33]: Follow-up appointment scheduled within 28-day window."
        )
    else:
        feedback_parts.append(
            "FAIL [0/33]: No new appointment found. "
            "Required: schedule any appointment within 28 days."
        )

    passed = score >= 67
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts),
    }
