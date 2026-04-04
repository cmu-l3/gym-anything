#!/usr/bin/env python3
"""
Verifier for record_vital_signs task.
Verifies that correct vital signs were recorded in the database for the correct patient.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_record_vital_signs(traj, env_info, task_info):
    """
    Verify vital signs recording.
    
    Criteria:
    1. Vitals record exists for the correct patient (15 pts)
    2. Record was created during the task window (15 pts)
    3. All values match expectations (10 pts each, 70 pts total)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_values = metadata.get('expected_values', {})
    tolerances = metadata.get('tolerances', {})
    
    score = 0
    max_score = 100
    feedback_parts = []
    
    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    # Check 1: Vitals found for correct patient
    if not result.get('vitals_found', False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No vitals record found for the target patient."
        }
    
    score += 15
    feedback_parts.append("Vitals record found for correct patient")
    
    # Check 2: Timestamp validity (Anti-gaming)
    if result.get('timestamp_valid', False) and result.get('new_record_created', False):
        score += 15
        feedback_parts.append("Record created during task")
    else:
        feedback_parts.append("WARNING: Record timestamp invalid or pre-existing")
        
    # Check 3: Verify values
    vitals_data = result.get('vitals_data', {})
    correct_fields = 0
    total_fields = len(expected_values)
    
    for field, expected in expected_values.items():
        actual_raw = vitals_data.get(field)
        
        # Handle missing data
        if actual_raw is None or actual_raw == "" or str(actual_raw).lower() == "null":
            feedback_parts.append(f"{field}: Missing")
            continue
            
        try:
            actual = float(actual_raw)
            tolerance = tolerances.get(field, 0.5 if field in ['height', 'weight'] else 0.1)
            
            if abs(actual - expected) <= tolerance:
                correct_fields += 1
            else:
                feedback_parts.append(f"{field}: Incorrect ({actual} vs {expected})")
        except ValueError:
            feedback_parts.append(f"{field}: Invalid format ({actual_raw})")

    # Score fields (remaining 70 points distributed)
    # 8 fields total: bps, bpd, pulse, temp, resp, o2, height, weight
    # 70 / 8 = 8.75 points per field
    field_score = int((correct_fields / 8) * 70)
    score += field_score
    
    if correct_fields == 8:
        feedback_parts.append("All values correct")
    else:
        feedback_parts.append(f"{correct_fields}/8 values correct")

    passed = score >= 70 and result.get('vitals_found', False)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "correct_fields": correct_fields,
            "total_fields": 8,
            "vitals_found": result.get('vitals_found'),
            "timestamp_valid": result.get('timestamp_valid')
        }
    }