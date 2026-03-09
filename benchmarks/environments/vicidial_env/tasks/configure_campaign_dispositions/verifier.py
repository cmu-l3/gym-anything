#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_campaign_dispositions(traj, env_info, task_info):
    """
    Verify the Vicidial campaign disposition configuration task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load expected metadata
    metadata = task_info.get('metadata', {})
    expected_statuses_config = metadata.get('expected_statuses', {})
    
    # Load result from environment
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    actual_statuses_list = result.get("campaign_statuses", [])
    initial_count = result.get("initial_count", 0)
    
    # Convert list to dict for easier lookup
    actual_statuses = {item['status']: item for item in actual_statuses_list}
    
    score = 0
    feedback = []
    
    # 1. Anti-gaming check (Statuses must be new)
    if len(actual_statuses_list) > initial_count:
        score += 8
        feedback.append("New statuses detected.")
    else:
        feedback.append("No new statuses found.")

    # 2. Check each expected status
    max_status_points = 92  # Remaining points
    # Points breakdown per status: ~15 points per status * 6 = 90 + 2 buffer
    
    for code, expected in expected_statuses_config.items():
        actual = actual_statuses.get(code)
        
        if not actual:
            feedback.append(f"MISSING: Status '{code}' not found.")
            continue
            
        status_score = 0
        status_feedback = []
        
        # Name check (3 pts)
        if actual.get('status_name') == expected.get('status_name'):
            status_score += 3
        else:
            status_feedback.append(f"Name mismatch (exp: {expected.get('status_name')})")

        # Selectable check (2 pts)
        if actual.get('selectable') == 'Y':
            status_score += 2
        else:
            status_feedback.append("Not Selectable")

        # Human Answered check (2 pts)
        if actual.get('human_answered') == 'Y':
            status_score += 2
        else:
            status_feedback.append("Not Human Answered")
            
        # Specific Flag Checks (8 pts total distributed)
        # Check specific 'Y' flags required
        required_flags = ['sale', 'customer_contact', 'not_interested', 'unworkable', 'scheduled_callback']
        
        flags_correct = True
        for flag in required_flags:
            exp_val = expected.get(flag, 'N')
            act_val = actual.get(flag, 'N')
            
            if act_val != exp_val:
                status_feedback.append(f"Flag '{flag}' wrong (exp: {exp_val}, got: {act_val})")
                flags_correct = False
        
        if flags_correct:
            status_score += 8
        else:
            # Partial credit for flags could be complex, sticking to all-or-nothing for the complex flags block to ensure precision
            pass
            
        score += status_score
        if status_feedback:
            feedback.append(f"{code}: " + ", ".join(status_feedback))
        else:
            feedback.append(f"{code}: Perfect")

    # Final tally
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }