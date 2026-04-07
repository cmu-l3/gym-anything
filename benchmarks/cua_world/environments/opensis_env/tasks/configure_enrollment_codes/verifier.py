#!/usr/bin/env python3
"""
Verifier for configure_enrollment_codes task.
Checks if the agent correctly added the required enrollment/withdrawal codes.
"""

import json
import os
import logging
import tempfile
import sys

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_enrollment_codes(traj, env_info, task_info):
    """
    Verify that 6 specific enrollment codes were added to the database.
    
    Scoring:
    - 5 pts: Basic task interaction (login/navigation inferred from any code change)
    - 45 pts: 3 Entry codes (15 pts each)
    - 45 pts: 3 Withdrawal codes (15 pts each)
    - 5 pts: Anti-gaming (codes added during task window)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expectations
    metadata = task_info.get('metadata', {})
    expected_entry = metadata.get('expected_entry_codes', [])
    expected_exit = metadata.get('expected_exit_codes', [])
    
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

    # Check for error in export
    if 'error' in result:
        return {"passed": False, "score": 0, "feedback": f"Export script error: {result['error']}"}

    current_codes = result.get('codes', [])
    initial_count = result.get('initial_count', 0)
    current_count = result.get('current_count', 0)
    
    score = 0.0
    feedback_parts = []
    
    # 1. Check for basic interaction (5 pts)
    if current_count > initial_count:
        score += 5
        feedback_parts.append("Database modified (login successful)")
    elif len(current_codes) > 0 and initial_count == 0:
        score += 5
        feedback_parts.append("Codes found (login successful)")
    else:
        return {"passed": False, "score": 0, "feedback": "No codes added"}

    # Helper to check code match
    def check_code(expected, actual_list):
        # We try to match by Title first, then Short Name
        # Type is used to confirm correctness
        
        tgt_title = expected['title'].lower()
        tgt_short = expected['short_name'].lower()
        tgt_type_kw = expected['type_keyword'].lower() # 'add' or 'drop'
        
        for code in actual_list:
            act_title = code.get('title', '').lower()
            act_short = code.get('short_name', '').lower()
            act_type = code.get('type', '').lower()
            
            # Fuzzy match title (contains) or Exact match short name
            match_identity = (tgt_title in act_title) or (tgt_short == act_short)
            
            if match_identity:
                # Check type
                # 'Add' types usually have 'add' or 'entry' or '1'
                # 'Drop' types usually have 'drop' or 'withdraw' or '2'
                type_ok = False
                if tgt_type_kw == 'add':
                    if any(x in act_type for x in ['add', 'entry', 'new', 'enroll', '1']):
                        type_ok = True
                elif tgt_type_kw == 'drop':
                    if any(x in act_type for x in ['drop', 'withdraw', 'exit', '2']):
                        type_ok = True
                
                if type_ok:
                    return True, "Correct"
                else:
                    return False, f"Found but wrong type (expected {tgt_type_kw}, got {act_type})"
        
        return False, "Not found"

    # 2. Verify Entry Codes (45 pts)
    entry_score = 0
    for exp in expected_entry:
        found, msg = check_code(exp, current_codes)
        if found:
            entry_score += 15
            feedback_parts.append(f"[+] Entry code '{exp['title']}': OK")
        else:
            feedback_parts.append(f"[-] Entry code '{exp['title']}': {msg}")
    score += entry_score

    # 3. Verify Exit Codes (45 pts)
    exit_score = 0
    for exp in expected_exit:
        found, msg = check_code(exp, current_codes)
        if found:
            exit_score += 15
            feedback_parts.append(f"[+] Exit code '{exp['title']}': OK")
        else:
            feedback_parts.append(f"[-] Exit code '{exp['title']}': {msg}")
    score += exit_score

    # 4. Anti-gaming check (5 pts)
    # Ensure items were actually added during this session
    if (current_count - initial_count) >= 3:
        score += 5
    else:
        feedback_parts.append("Anti-gaming: Too few items added relative to start")

    # Pass threshold: 50 points (At least 3 codes correct + login)
    passed = score >= 50

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": "\n".join(feedback_parts)
    }