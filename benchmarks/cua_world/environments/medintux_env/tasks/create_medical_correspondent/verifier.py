#!/usr/bin/env python3
"""
Verifier for create_medical_correspondent task.

CRITERIA:
1. Record exists in database (40 pts)
2. City is 'Toulouse' and CP is '31300' (20 pts)
3. Phone number matches '05 61 77 22 33' (normalization applied) (20 pts)
4. Specialty/Qualite set to Cardiology related term (10 pts)
5. No duplicates created (Clean execution) (10 pts)
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def normalize_phone(phone_str):
    """Remove spaces, dots, dashes, and parens from phone string."""
    if not phone_str:
        return ""
    return re.sub(r'[\s\.\-\(\)]', '', str(phone_str))

def verify_create_medical_correspondent(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
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

    # Extract data
    record_found = result.get('record_found', False)
    db_record = result.get('db_record', {})
    count_diff = result.get('count_diff', 0)
    
    score = 0
    feedback_parts = []
    
    # Metadata expectations
    metadata = task_info.get('metadata', {})
    expected_ville = metadata.get('expected_ville', 'Toulouse').lower()
    expected_cp = metadata.get('expected_cp', '31300')
    expected_tel = normalize_phone(metadata.get('expected_tel', '0561772233'))
    specialty_keywords = [k.lower() for k in metadata.get('expected_specialty_keywords', ['cardio'])]

    # 1. Record Existence (40 pts)
    if record_found:
        score += 40
        feedback_parts.append("Correspondent record created successfully.")
    else:
        return {"passed": False, "score": 0, "feedback": "No record found for 'MARTIN Sophie'."}

    # 2. Address Check (20 pts)
    # Check Ville
    actual_ville = (db_record.get('ville') or "").strip().lower()
    actual_cp = (db_record.get('cp') or "").strip()
    
    if expected_ville in actual_ville:
        score += 10
        feedback_parts.append(f"City correct ({actual_ville}).")
    else:
        feedback_parts.append(f"City incorrect (expected {expected_ville}, got {actual_ville}).")
        
    # Check CP
    if expected_cp in actual_cp:
        score += 10
        feedback_parts.append(f"Postal code correct ({actual_cp}).")
    else:
        feedback_parts.append(f"Postal code incorrect (expected {expected_cp}, got {actual_cp}).")

    # 3. Phone Check (20 pts)
    # Check Tel1, Tel2, and Mobile
    actual_tel1 = normalize_phone(db_record.get('tel1'))
    actual_tel2 = normalize_phone(db_record.get('tel2'))
    actual_mobile = normalize_phone(db_record.get('mobile'))
    
    phone_match = False
    if expected_tel in actual_tel1 or expected_tel in actual_tel2 or expected_tel in actual_mobile:
        phone_match = True
    
    if phone_match:
        score += 20
        feedback_parts.append("Phone number correct.")
    else:
        feedback_parts.append(f"Phone number incorrect (expected {expected_tel}).")

    # 4. Specialty Check (10 pts)
    actual_qualite = (db_record.get('qualite') or "").lower()
    if any(keyword in actual_qualite for keyword in specialty_keywords):
        score += 10
        feedback_parts.append(f"Specialty correct ({actual_qualite}).")
    else:
        feedback_parts.append(f"Specialty might be missing or incorrect (got '{actual_qualite}').")

    # 5. No Duplicates / Clean Execution (10 pts)
    # If count_diff is exactly 1, it means exactly one record was added
    if count_diff == 1:
        score += 10
        feedback_parts.append("Clean execution (exactly 1 record added).")
    elif count_diff > 1:
        feedback_parts.append(f"Multiple records added ({count_diff}).")
    else:
        feedback_parts.append("Record count did not increase as expected.")

    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }