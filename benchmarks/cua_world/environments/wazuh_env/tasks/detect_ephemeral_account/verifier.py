#!/usr/bin/env python3
import json
import os
import tempfile
import re

def verify_detect_ephemeral_account(traj, env_info, task_info):
    """
    Verifies that the agent correctly created the ephemeral account detection rule.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment access failed"}

    # Load result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. Static Analysis of Rules File (40 points)
    rules_content = result.get('rules_content', '')
    
    # Check Rule ID
    if 'id="100050"' in rules_content or "id='100050'" in rules_content:
        score += 10
        feedback.append("Rule ID 100050 found.")
    else:
        feedback.append("Rule ID 100050 NOT found.")

    # Check Logic Structure (Regex checks)
    # Looking for <if_sid>5904</if_sid> (Trigger)
    if re.search(r'<if_sid>\s*5904\s*</if_sid>', rules_content):
        score += 5
        feedback.append("Correct trigger SID (5904).")
    
    # Looking for <if_matched_sid>5902</if_matched_sid> (Context)
    if re.search(r'<if_matched_sid>\s*5902\s*</if_matched_sid>', rules_content):
        score += 10
        feedback.append("Correct context SID (5902).")

    # Looking for <timeframe> (approx 300)
    if re.search(r'<timeframe>\s*300\s*</timeframe>', rules_content):
        score += 5
        feedback.append("Correct timeframe (300s).")

    # Looking for <same_field>
    if '<same_field>' in rules_content:
        score += 10
        feedback.append("Field correlation used.")

    # 2. Dynamic Verification (60 points)
    # This is the most important part: Did it actually work?
    dynamic = result.get('dynamic_verification', {})
    
    if dynamic.get('dynamic_test_fired') is True:
        score += 40
        feedback.append("SUCCESS: Rule 100050 fired on 'create then delete' sequence.")
    else:
        feedback.append("FAILURE: Rule did not fire on test sequence.")
        actual_fired = dynamic.get('fired_rule_id')
        if actual_fired:
            feedback.append(f"Fired rule {actual_fired} instead.")

    # Negative test (ensure no false positives)
    if dynamic.get('negative_test_passed') is True:
        score += 10
        feedback.append("Negative test passed (rule didn't fire on isolated delete).")
    else:
        feedback.append("Negative test failed (rule fired on isolated delete).")

    # Check severity level
    fired_level = dynamic.get('fired_rule_level')
    if fired_level == 12:
        score += 10
        feedback.append("Severity level 12 verified.")
    elif fired_level:
        feedback.append(f"Wrong severity level: {fired_level} (Expected 12).")

    # Pass threshold
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }