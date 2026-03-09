#!/usr/bin/env python3
"""
Verifier: post_mi_cardiac_workup

Checks that the nurse completed all three documentation tasks for Jesse Becker:
  1. Added Codeine allergy (Nausea and vomiting / Moderate)
  2. Added Type 2 diabetes mellitus condition (Confirmed)
  3. Ordered Creatinine lab test

Scoring: 33 + 34 + 33 = 100 pts; pass threshold = 67 / 100.
"""

import json
import os
import tempfile


def verify_post_mi_cardiac_workup(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    result_path = (task_info.get("metadata", {}) or {}).get(
        "result_file", "/tmp/post_mi_cardiac_workup_result.json"
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

    # --- Criterion 1: Codeine allergy (33 pts, partial 15 pts) ---
    allergy_added = result.get("codeine_allergy_added", False)
    severity_ok = result.get("allergy_severity_moderate", False)
    reaction_ok = result.get("allergy_reaction_nausea", False)
    if allergy_added and severity_ok and reaction_ok:
        score += 33
        feedback_parts.append(
            "PASS [33/33]: Codeine allergy documented with Nausea and vomiting reaction and Moderate severity."
        )
    elif allergy_added:
        score += 15
        parts = []
        if not severity_ok:
            parts.append("severity should be Moderate")
        if not reaction_ok:
            parts.append("reaction should be Nausea and vomiting")
        feedback_parts.append(
            f"PARTIAL [15/33]: Codeine allergy found but incomplete — {'; '.join(parts)}."
        )
    else:
        feedback_parts.append(
            "FAIL [0/33]: Codeine allergy not found. "
            "Required: Allergen=Codeine, Reaction=Nausea and vomiting, Severity=Moderate."
        )

    # --- Criterion 2: Type 2 diabetes condition (34 pts) ---
    dm_ok = result.get("diabetes_condition_added", False)
    if dm_ok:
        score += 34
        feedback_parts.append(
            "PASS [34/34]: Type 2 diabetes mellitus added to active problem list."
        )
    else:
        feedback_parts.append(
            "FAIL [0/34]: Diabetes condition not found. "
            "Required: add 'Type 2 diabetes mellitus' as a Confirmed condition."
        )

    # --- Criterion 3: Creatinine lab order (33 pts) ---
    lab_ok = result.get("creatinine_ordered", False)
    if lab_ok:
        score += 33
        feedback_parts.append(
            "PASS [33/33]: Creatinine lab test ordered successfully."
        )
    else:
        feedback_parts.append(
            "FAIL [0/33]: Creatinine order not found. "
            "Required: order a Creatinine (serum) lab test."
        )

    passed = score >= 67
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts),
    }
