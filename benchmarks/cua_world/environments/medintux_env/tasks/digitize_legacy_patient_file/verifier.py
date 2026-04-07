#!/usr/bin/env python3
"""
Verifier for digitize_legacy_patient_file task.

Criteria:
1. Patient 'Sarah CONNOR' exists in DB (30 pts)
2. DOB is correct (1965-05-12) (10 pts)
3. Address contains expected details (10 pts)
4. A clinical note exists for the patient (20 pts)
5. History transcribed (Appendicectomy, Fracture) (15 pts)
6. Allergies transcribed (Latex, Penicillin) (15 pts)

Pass Threshold: 70 pts
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_digitize_legacy_patient_file(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Patient Exists (30 pts)
    if result.get("patient_found"):
        score += 30
        feedback_parts.append("Patient created")
    else:
        return {"passed": False, "score": 0, "feedback": "Patient 'Sarah CONNOR' not found in database."}

    # 2. DOB Check (10 pts)
    # Expected: 1965-05-12
    dob = result.get("patient_dob", "")
    if "1965-05-12" in dob:
        score += 10
        feedback_parts.append("DOB Correct")
    else:
        feedback_parts.append(f"DOB Mismatch (Found: {dob})")

    # 3. Address Check (10 pts)
    addr = (result.get("patient_address", "") + " " + result.get("patient_city", "")).lower()
    if "cyberdyne" in addr and "paris" in addr:
        score += 10
        feedback_parts.append("Address Correct")
    else:
        feedback_parts.append("Address Mismatch/Incomplete")

    # 4. Note Exists (20 pts)
    note_content = result.get("full_note_content", "").lower()
    if result.get("note_found") and len(note_content) > 10:
        score += 20
        feedback_parts.append("Clinical note created")
    else:
        feedback_parts.append("No clinical note found")
        # Fail early if no note, as we can't check content
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # 5. History Content (15 pts)
    # Terms: Appendicectomy, Fracture
    history_terms = ["appendicectomy", "fracture"]
    found_hist = [term for term in history_terms if term in note_content]
    if len(found_hist) == 2:
        score += 15
        feedback_parts.append("History fully transcribed")
    elif len(found_hist) == 1:
        score += 7
        feedback_parts.append("History partially transcribed")
    else:
        feedback_parts.append("History missing")

    # 6. Allergies Content (15 pts)
    # Terms: Latex, Penicillin
    allergy_terms = ["latex", "penicillin"]
    found_all = [term for term in allergy_terms if term in note_content]
    if len(found_all) == 2:
        score += 15
        feedback_parts.append("Allergies fully transcribed")
    elif len(found_all) == 1:
        score += 7
        feedback_parts.append("Allergies partially transcribed")
    else:
        feedback_parts.append("Allergies missing")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }