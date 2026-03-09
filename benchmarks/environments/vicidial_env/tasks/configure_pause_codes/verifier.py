#!/usr/bin/env python3
"""
Verifier for configure_pause_codes task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_pause_codes(traj, env_info, task_info):
    """
    Verify that the 6 pause codes were correctly configured in Vicidial.
    
    Scoring:
    - 5 pts for each code existing (5 * 6 = 30)
    - 3 pts for each correct name (3 * 6 = 18)
    - 4 pts for each correct billable status (4 * 6 = 24)
    - 8 pts bonus for having EXACTLY 6 codes (no extras)
    - 20 pts for evidence of Admin UI usage (anti-gaming log check)
    
    Total: 100 points
    Pass Threshold: 60 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve result data
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

    # 2. Get expected configuration
    metadata = task_info.get('metadata', {})
    expected_codes = metadata.get('expected_codes', [])
    
    actual_codes = result.get('final_pause_codes', [])
    log_entries = result.get('admin_log_entries', 0)
    
    score = 0
    feedback_parts = []
    
    # Map actual codes by code ID for easy lookup
    # Normalize keys to handle potential case issues, though Vicidial codes are usually UPCASE
    actual_map = {item['code'].upper(): item for item in actual_codes}
    
    # 3. Verify each expected code
    codes_found = 0
    for expected in expected_codes:
        exp_code = expected['code'].upper()
        exp_name = expected['name']
        exp_billable = expected['billable']
        
        if exp_code in actual_map:
            codes_found += 1
            score += 5 # Exists
            
            actual = actual_map[exp_code]
            
            # Check Name (case insensitive roughly, but stricter is better)
            if actual.get('name', '').strip().lower() == exp_name.lower():
                score += 3
            else:
                feedback_parts.append(f"Code {exp_code}: Name mismatch ('{actual.get('name')}' vs '{exp_name}')")
                
            # Check Billable
            if actual.get('billable') == exp_billable:
                score += 4
            else:
                feedback_parts.append(f"Code {exp_code}: Billable mismatch ({actual.get('billable')} vs {exp_billable})")
        else:
            feedback_parts.append(f"Missing code: {exp_code}")

    # 4. Check for clean state (exact count)
    if len(actual_codes) == len(expected_codes) and codes_found == len(expected_codes):
        score += 8
        feedback_parts.append("Perfect code count (bonus +8)")
    elif len(actual_codes) > len(expected_codes):
        feedback_parts.append(f"Found {len(actual_codes)} codes (expected {len(expected_codes)})")

    # 5. Anti-Gaming: Admin Log Check
    # If codes were added but logs are empty, user likely used SQL injection or scripts bypassing UI
    if codes_found > 0:
        if log_entries > 0:
            score += 20
            feedback_parts.append("Admin activity verified")
        else:
            feedback_parts.append("WARNING: No admin log activity detected despite changes (Possible gaming)")
            # No points for this section
    else:
        # If nothing was done, giving points for logs (e.g. login only) might be too generous, 
        # but the score will be low anyway.
        if log_entries > 0:
            score += 5 # Small credit for trying
    
    # 6. Final Result
    passed = score >= 60
    
    feedback_str = f"Score: {score}/100. Found {codes_found}/6 codes. " + "; ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback_str
    }