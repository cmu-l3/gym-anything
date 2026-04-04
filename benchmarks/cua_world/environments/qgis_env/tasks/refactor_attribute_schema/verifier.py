#!/usr/bin/env python3
"""Verifier for refactor_attribute_schema task."""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_refactor_attribute_schema(traj, env_info, task_info):
    """
    Verify schema refactoring.
    
    Scoring (100 points):
    - Output file exists and is valid: 20 pts
    - Correct fields present (station_id, name, temperature, date): 20 pts
    - Forbidden fields removed (STN_ID_X, etc): 20 pts
    - Temperature converted to numeric type: 25 pts
    - Data integrity preserved (values match): 15 pts
    
    Pass threshold: 70 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_file.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}

    logger.info(f"Task result: {result}")
    
    score = 0
    feedback_parts = []
    
    analysis = result.get('analysis', {})
    
    # 1. File exists and valid (20 pts)
    if result.get('file_exists') and analysis.get('valid'):
        score += 20
        feedback_parts.append("Valid output file found")
    else:
        feedback_parts.append("Output file missing or invalid")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}
        
    # 2. Correct fields (20 pts)
    required = ["has_station_id", "has_name", "has_temperature", "has_date"]
    missing = [k for k in required if not analysis.get(k)]
    if not missing:
        score += 20
        feedback_parts.append("All required fields present")
    else:
        # Partial credit
        present = len(required) - len(missing)
        score += present * 5
        feedback_parts.append(f"Missing fields: {missing}")
        
    # 3. Forbidden fields removed (20 pts)
    forbidden_found = analysis.get('found_forbidden', [])
    if not forbidden_found:
        score += 20
        feedback_parts.append("Legacy fields removed")
    else:
        feedback_parts.append(f"Legacy fields still present: {forbidden_found}")
        
    # 4. Numeric Type (25 pts)
    if analysis.get('temp_is_numeric'):
        score += 25
        feedback_parts.append("Temperature converted to number")
    else:
        feedback_parts.append("Temperature is still Text/String (Critical Fail)")
        
    # 5. Data Integrity (15 pts)
    if analysis.get('integrity_check'):
        score += 15
        feedback_parts.append("Data values preserved correctly")
    else:
        feedback_parts.append("Data values mismatch or corrupted")
        
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }