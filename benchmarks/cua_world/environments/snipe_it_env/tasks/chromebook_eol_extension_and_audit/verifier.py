#!/usr/bin/env python3
"""
Verifier for chromebook_eol_extension_and_audit task.

Scoring breakdown (100 points):
- C1: Depreciation Schedule (10 pts)
- C2: Model Update (10 pts)
- C3: Valid Assets Status (20 pts)
- C4: Expired Assets Status (20 pts)
- C5: Valid Assets Notes (15 pts)
- C6: Expired Assets Notes (15 pts)
- C7: Control Asset Check (10 pts)
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/chromebook_audit_result.json"


def verify_chromebook_audit(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env(RESULT_PATH, temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_file.name)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found in VM."}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    score = 0
    feedback = []

    depreciation = result.get("depreciation", {})
    model = result.get("model", {})
    assets = result.get("assets", {})

    # --- C1: Depreciation Schedule (10 pts) ---
    c1_score = 0
    if depreciation.get("found"):
        if str(depreciation.get("months")) == "48":
            c1_score = 10
            feedback.append("C1: 'Chromebook 4-Year' depreciation exists with 48 months (+10)")
        else:
            feedback.append(f"C1: Depreciation found but months is {depreciation.get('months')}, expected 48 (+0)")
    else:
        feedback.append("C1: 'Chromebook 4-Year' depreciation not found (+0)")
    score += c1_score

    # --- C2: Model Update (10 pts) ---
    c2_score = 0
    if model.get("found"):
        eol = str(model.get("eol"))
        dep_id = str(model.get("depreciation_id"))
        correct_dep_id = str(depreciation.get("id")) if depreciation.get("found") else "-1"
        
        if eol == "48" and dep_id == correct_dep_id and dep_id != "0":
            c2_score = 10
            feedback.append("C2: Model EOL set to 48 and assigned to correct depreciation (+10)")
        else:
            feedback.append(f"C2: Model EOL={eol} (expected 48), Depreciation_ID={dep_id} (expected {correct_dep_id}) (+0)")
    else:
        feedback.append("C2: Lenovo Chromebook 300e model not found (+0)")
    score += c2_score

    # Definitions
    valid_keys = ["CB001", "CB003", "CB005"]
    expired_keys = ["CB002", "CB004"]
    
    # --- Check for Do-Nothing / Complete Failure ---
    any_status_changed = False
    for k in valid_keys + expired_keys:
        if assets.get(k, {}).get("status", "") != "Pending EOL Review":
            any_status_changed = True
            break
            
    if not any_status_changed and c1_score == 0 and c2_score == 0:
        return {"passed": False, "score": 0, "feedback": "DO-NOTHING: No policies updated and no assets modified."}

    # --- C3: Valid Assets Status (20 pts) ---
    valid_status_count = 0
    for k in valid_keys:
        if assets.get(k, {}).get("status", "") == "Ready to Deploy":
            valid_status_count += 1
            
    c3_score = int(20 * (valid_status_count / len(valid_keys)))
    score += c3_score
    feedback.append(f"C3: {valid_status_count}/{len(valid_keys)} valid assets correctly set to 'Ready to Deploy' (+{c3_score})")

    # --- C4: Expired Assets Status (20 pts) ---
    expired_status_count = 0
    for k in expired_keys:
        if assets.get(k, {}).get("status", "") == "Retired":
            expired_status_count += 1
            
    c4_score = int(20 * (expired_status_count / len(expired_keys)))
    score += c4_score
    feedback.append(f"C4: {expired_status_count}/{len(expired_keys)} expired assets correctly set to 'Retired' (+{c4_score})")

    # --- C5: Valid Assets Notes (15 pts) ---
    valid_notes_count = 0
    for k in valid_keys:
        if "lifespan extended" in assets.get(k, {}).get("notes", "").lower():
            valid_notes_count += 1
            
    c5_score = int(15 * (valid_notes_count / len(valid_keys)))
    score += c5_score
    feedback.append(f"C5: {valid_notes_count}/{len(valid_keys)} valid assets have correct notes (+{c5_score})")

    # --- C6: Expired Assets Notes (15 pts) ---
    expired_notes_count = 0
    for k in expired_keys:
        if "reached 48m eol" in assets.get(k, {}).get("notes", "").lower():
            expired_notes_count += 1
            
    c6_score = int(15 * (expired_notes_count / len(expired_keys)))
    score += c6_score
    feedback.append(f"C6: {expired_notes_count}/{len(expired_keys)} expired assets have correct notes (+{c6_score})")

    # --- C7: Control Asset (10 pts) ---
    cb006 = assets.get("CB006", {})
    c7_score = 0
    if cb006.get("found"):
        if cb006.get("status") == "Ready to Deploy" and "Control asset - active." == cb006.get("notes", ""):
            c7_score = 10
            feedback.append("C7: Control asset CB006 left entirely unmodified (+10)")
        else:
            feedback.append(f"C7: Control asset CB006 was erroneously modified (status: {cb006.get('status')}) (+0)")
    else:
        feedback.append("C7: Control asset not found (+0)")
    score += c7_score

    # Determine Pass/Fail
    # To pass, agent must score >= 70 and demonstrate attempting the date logic (partial success on statuses)
    attempted_logic = (valid_status_count > 0 or expired_status_count > 0)
    passed = (score >= 70) and attempted_logic

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }