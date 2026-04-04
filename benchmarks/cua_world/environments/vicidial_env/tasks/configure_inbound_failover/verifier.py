#!/usr/bin/env python3
"""
Verifier for configure_inbound_failover task.
Checks if the Vicidial Inbound Group 'SUPPORT' is correctly configured
with Call Times, After Hours VM, No Agent VM, and Wait Time VM.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_inbound_failover(traj, env_info, task_info):
    """
    Verify the inbound group configuration.
    """
    # 1. Setup copy from environment
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 2. Load Expected Values
    metadata = task_info.get('metadata', {})
    expected = metadata.get('expected_values', {
        "call_time_id": "BIZ_HRS",
        "after_hours_action": "VOICEMAIL",
        "after_hours_voicemail": "8500",
        "no_agent_no_queue_action": "VOICEMAIL",
        "no_agent_no_queue_action_value": "8500",
        "wait_hold_option": "VOICEMAIL",
        "wait_time_option_seconds": 90,
        "wait_time_option_value": "8500"
    })

    # 3. Load Actual Results
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    actual = result.get('final_state', {})
    
    # 4. Scoring Logic
    score = 0
    feedback_parts = []
    
    # Criteria 1: Call Time (20 pts)
    if actual.get('call_time_id') == expected['call_time_id']:
        score += 20
        feedback_parts.append("Call Time: Correct (20/20)")
    else:
        feedback_parts.append(f"Call Time: Incorrect (Exp: {expected['call_time_id']}, Got: {actual.get('call_time_id')})")

    # Criteria 2: After Hours Config (20 pts)
    ah_score = 0
    if actual.get('after_hours_action') == expected['after_hours_action']:
        ah_score += 10
    if actual.get('after_hours_voicemail') == expected['after_hours_voicemail']:
        ah_score += 10
    
    score += ah_score
    if ah_score == 20:
        feedback_parts.append("After Hours: Correct (20/20)")
    else:
        feedback_parts.append(f"After Hours: Partial ({ah_score}/20)")

    # Criteria 3: No Agent No Queue (20 pts)
    nanq_score = 0
    if actual.get('no_agent_no_queue_action') == expected['no_agent_no_queue_action']:
        nanq_score += 10
    if actual.get('no_agent_no_queue_action_value') == expected['no_agent_no_queue_action_value']:
        nanq_score += 10
    
    score += nanq_score
    if nanq_score == 20:
        feedback_parts.append("No Agent: Correct (20/20)")
    else:
        feedback_parts.append(f"No Agent: Partial ({nanq_score}/20)")

    # Criteria 4: Wait Time Config (40 pts)
    wait_score = 0
    if actual.get('wait_hold_option') == expected['wait_hold_option']:
        wait_score += 10
    # Allow small tolerance for seconds (though exact is requested)
    try:
        act_sec = int(actual.get('wait_time_option_seconds', 0))
        if act_sec == expected['wait_time_option_seconds']:
            wait_score += 15
    except:
        pass
    if actual.get('wait_time_option_value') == expected['wait_time_option_value']:
        wait_score += 15
        
    score += wait_score
    if wait_score == 40:
        feedback_parts.append("Wait Time: Correct (40/40)")
    else:
        feedback_parts.append(f"Wait Time: Partial ({wait_score}/40)")

    # 5. Final Result
    passed = (score >= 80)  # Threshold
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }