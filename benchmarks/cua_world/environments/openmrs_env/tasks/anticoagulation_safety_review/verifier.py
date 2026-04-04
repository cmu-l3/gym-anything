#!/usr/bin/env python3
"""
Verifier: anticoagulation_safety_review
Features tested: allergy_documentation, vitals_recording, condition_problem_list

Checks three nursing documentation tasks for Rosario Ortiz (pre-anticoagulation):
  1. Aspirin allergy documented (Anaphylaxis / Severe)                          33 pts
  2. Admission vitals recorded (BP 148/90, Weight 87 kg, Pulse 92, Temp 37.4)  34 pts
  3. Chronic kidney disease added to active problem list (Confirmed)            33 pts

Pass threshold: 67 / 100 (any 2 of 3 criteria fully met).
"""

import json
import os
import tempfile


def verify_anticoagulation_safety_review(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    result_path = (task_info.get("metadata", {}) or {}).get(
        "result_file", "/tmp/anticoagulation_safety_review_result.json"
    )

    with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
        tmp_path = tmp.name

    try:
        copy_from_env(result_path, tmp_path)
        with open(tmp_path, encoding="utf-8") as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result file: {e}"}
    finally:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)

    score = 0
    feedback_parts = []

    # --- Criterion 1: Aspirin allergy (33 pts) ---
    allergy_added = result.get("aspirin_allergy_added", False)
    severity_ok = result.get("allergy_severity_severe", False)
    reaction_ok = result.get("allergy_reaction_anaphylaxis", False)
    if allergy_added and severity_ok and reaction_ok:
        score += 33
        feedback_parts.append("PASS [33/33]: Aspirin allergy — Anaphylaxis / Severe documented correctly.")
    elif allergy_added:
        score += 15
        issues = []
        if not reaction_ok:
            issues.append("reaction should be Anaphylaxis")
        if not severity_ok:
            issues.append("severity should be Severe")
        feedback_parts.append(f"PARTIAL [15/33]: Aspirin allergy found but incomplete — {'; '.join(issues)}.")
    else:
        feedback_parts.append("FAIL [0/33]: Aspirin allergy not found. Required: Allergen=Aspirin, Reaction=Anaphylaxis, Severity=Severe.")

    # --- Criterion 2: Vitals (34 pts) ---
    vitals_ok = result.get("vitals_recorded", False)
    vitals_details = result.get("vitals_details", {})
    present = [k for k, v in vitals_details.items() if v]
    missing = [k for k, v in vitals_details.items() if not v]
    if vitals_ok:
        score += 34
        feedback_parts.append("PASS [34/34]: All admission vitals recorded (BP 148/90, Weight 87 kg, Pulse 92, Temp 37.4°C).")
    elif len(present) >= 2:
        score += 20
        feedback_parts.append(
            f"PARTIAL [20/34]: Vitals partially recorded ({', '.join(present)}) — missing/out-of-range: {', '.join(missing)}."
        )
    elif len(present) == 1:
        score += 10
        feedback_parts.append(f"PARTIAL [10/34]: Only {present[0]} recorded — missing: {', '.join(missing)}.")
    else:
        feedback_parts.append("FAIL [0/34]: No valid vitals recorded. Required: BP 148/90, Weight 87 kg, Pulse 92, Temp 37.4°C.")

    # --- Criterion 3: CKD condition (33 pts) ---
    ckd_ok = result.get("ckd_condition_added", False)
    if ckd_ok:
        score += 33
        feedback_parts.append("PASS [33/33]: Chronic kidney disease added to active problem list.")
    else:
        feedback_parts.append("FAIL [0/33]: CKD condition not found. Required: add 'Chronic kidney disease' as a Confirmed condition.")

    passed = score >= 67
    return {"passed": passed, "score": score, "feedback": "\n".join(feedback_parts)}
