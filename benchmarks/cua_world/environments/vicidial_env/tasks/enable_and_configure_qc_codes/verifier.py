#!/usr/bin/env python3
"""
Verifier for enable_and_configure_qc_codes task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_enable_and_configure_qc_codes(traj, env_info, task_info):
    """
    Verifies that the Quality Control module was enabled and specific codes were created.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_setting = metadata.get('expected_setting', '1')
    required_codes = metadata.get('required_codes', [])
    
    # Load result from environment
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

    score = 0
    feedback_parts = []
    
    # Criterion 1: QC Features Enabled (25 points)
    # The system setting must be '1'
    qc_active = str(result.get('qc_features_active', '0')).strip()
    if qc_active == expected_setting:
        score += 25
        feedback_parts.append("QC Features enabled successfully (25/25)")
    else:
        feedback_parts.append(f"QC Features NOT enabled (Found: {qc_active}) (0/25)")
        # Critical failure: If the module isn't enabled, they couldn't have (legitimately) accessed the menu to add codes via UI
        # However, we'll still check codes in case they did it via URL manipulation or partial success
    
    # Check Codes (75 points total)
    found_codes_list = result.get('found_codes', [])
    # Convert list of dicts to a lookup dict for easier verification
    found_codes_map = {item['code']: item['name'] for item in found_codes_list}
    
    for req in required_codes:
        req_code = req['code']
        req_name = req['name']
        
        if req_code in found_codes_map:
            # Code exists (15 pts)
            score += 15
            
            # Check Name Accuracy (10 pts)
            # Vicidial is sometimes case sensitive, but we'll be slightly lenient on whitespace
            actual_name = found_codes_map[req_code]
            if actual_name.strip() == req_name.strip():
                score += 10
                feedback_parts.append(f"Code {req_code}: Created and named correctly (25/25)")
            else:
                feedback_parts.append(f"Code {req_code}: Created but name mismatch. Expected '{req_name}', got '{actual_name}' (15/25)")
        else:
            feedback_parts.append(f"Code {req_code}: Missing (0/25)")

    # Anti-gaming check implied:
    # The setup script explicitly DELETES these codes before start.
    # If they exist now, they must have been created during the session.
    
    passed = (score >= 65) and (qc_active == expected_setting)
    
    if not passed and qc_active != expected_setting:
         feedback_parts.append("FAIL: Task cannot pass if System Setting 'QC Features Active' is not enabled.")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }