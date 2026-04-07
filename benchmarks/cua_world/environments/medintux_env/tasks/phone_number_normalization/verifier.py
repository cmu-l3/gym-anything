#!/usr/bin/env python3
"""
Verifier for phone_number_normalization task.
"""

import json
import base64
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_phone_number_normalization(traj, env_info, task_info):
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
    feedback = []
    
    # 1. Verify DB Cleaning (Separators removed) - 40 pts
    db_state = result.get("db_state", {})
    remaining_separators = db_state.get("remaining_separators", -1)
    
    if remaining_separators == 0:
        score += 40
        feedback.append("Database cleaned: No separators found.")
    else:
        feedback.append(f"Database dirty: Found {remaining_separators} records with separators.")

    # 2. Verify Specific Transformations (Logic check) - 20 pts
    # TEST-GUID-SPACES -> 0612345678
    # TEST-GUID-DOTS -> 0491234567
    test_cases = result.get("test_cases", {})
    
    expected_transformations = {
        "TEST-GUID-SPACES": "0612345678",
        "TEST-GUID-DOTS": "0491234567",
        "TEST-GUID-DASHES": "0145678901",
        "TEST-GUID-CLEAN": "0987654321"
    }
    
    transform_success = 0
    total_transforms = len(expected_transformations)
    
    for guid, expected in expected_transformations.items():
        actual = test_cases.get(guid, "")
        if actual == expected:
            transform_success += 1
        else:
            feedback.append(f"Failed transform for {guid}: Expected '{expected}', got '{actual}'")
            
    if transform_success == total_transforms:
        score += 20
        feedback.append("All test cases transformed correctly.")
    elif transform_success > 0:
        partial = int(20 * (transform_success / total_transforms))
        score += partial
        feedback.append(f"Partial transform success ({transform_success}/{total_transforms}).")

    # 3. Verify Report Generation - 20 pts for existence, 20 pts for content
    report_exists = result.get("report_exists", False)
    
    if report_exists:
        score += 20
        feedback.append("Report file exists.")
        
        # Verify content matches invalid cases
        # TEST-GUID-SHORT (061234) and TEST-GUID-TEXT (Pas de telephone) should be in report
        content_b64 = result.get("report_content_base64", "")
        if content_b64:
            try:
                report_text = base64.b64decode(content_b64).decode('utf-8', errors='ignore')
                
                # Check headers
                if "guid" in report_text.lower() and "telephone" in report_text.lower():
                    feedback.append("Report headers look correct.")
                
                # Check specific invalid cases
                found_short = "TEST-GUID-SHORT" in report_text or "061234" in report_text
                found_text = "TEST-GUID-TEXT" in report_text or "Pas de telephone" in report_text
                
                if found_short and found_text:
                    score += 20
                    feedback.append("Report contains expected invalid records.")
                elif found_short or found_text:
                    score += 10
                    feedback.append("Report contains some expected records.")
                else:
                    feedback.append("Report missing expected invalid records (TEST-GUID-SHORT/TEXT).")
            except Exception as e:
                feedback.append(f"Error reading report content: {e}")
    else:
        feedback.append("Report file not created.")

    return {
        "passed": score >= 60 and remaining_separators == 0,
        "score": score,
        "feedback": " | ".join(feedback)
    }