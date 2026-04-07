#!/usr/bin/env python3
"""
Verifier for reassign_user_portfolio task.

Verification Strategy:
1. Programmatic DB Check: Validates that all 5 target accounts and 5 target opportunities now belong to Jordan Hayes.
2. Anti-Gaming DB Check: Validates that all 6 control records (Taylor's) were untouched. A mass update without filtering fails this immediately.
3. VLM Trajectory Check: Reviews screenshots to ensure the agent actively navigated SuiteCRM to perform the operation.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_reassign_user_portfolio(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Setup expected UUID constants based on task setup
    NEW_REP_ID = "user_jhayes_002"
    CONTROL_REP_ID = "user_treed_003"
    
    # 1. Retrieve the Database state results
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/reassign_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    accounts = result.get('accounts', {})
    opps = result.get('opportunities', {})
    
    score = 0
    feedback_parts = []
    
    # 2. Evaluate Alex's Target Accounts (5 records, 5 pts each = 25 max)
    alex_acc_count = sum(1 for i in range(1, 6) if accounts.get(f'acc_alex_{i}') == NEW_REP_ID)
    score += (alex_acc_count * 5)
    feedback_parts.append(f"Accounts reassigned: {alex_acc_count}/5")

    # 3. Evaluate Alex's Target Opportunities (5 records, 5 pts each = 25 max)
    alex_opp_count = sum(1 for i in range(1, 6) if opps.get(f'opp_alex_{i}') == NEW_REP_ID)
    score += (alex_opp_count * 5)
    feedback_parts.append(f"Opportunities reassigned: {alex_opp_count}/5")

    # 4. Evaluate Taylor's Control Records (6 records total) -> 30 pts for 0 errors
    taylor_control_errors = 0
    for i in range(1, 4):
        if accounts.get(f'acc_taylor_{i}') != CONTROL_REP_ID:
            taylor_control_errors += 1
        if opps.get(f'opp_taylor_{i}') != CONTROL_REP_ID:
            taylor_control_errors += 1
            
    # Apply severe penalty for hitting control records (shows they didn't filter correctly)
    control_score = max(0, 30 - (taylor_control_errors * 15))
    score += control_score
    if taylor_control_errors > 0:
        feedback_parts.append(f"CRITICAL: {taylor_control_errors} control records wrongly modified!")
    else:
        feedback_parts.append("Control records safely preserved")

    # 5. VLM Trajectory Verification (20 max pts)
    # Checks that the agent actually navigated the interface to do this
    vlm_score = 0
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm, get_final_screenshot
        
        frames = sample_trajectory_frames(traj, n=5)
        final = get_final_screenshot(traj)
        
        vlm_prompt = """
        You are verifying a CRM task trajectory.
        Did the user navigate the SuiteCRM web interface to filter records and use Mass Update, OR use the 'Reassign Records' admin tool?
        Look for evidence of list views, filtering by user 'Alex Mercer', and assigning to 'Jordan Hayes'.
        
        Return ONLY a JSON object:
        {
          "used_crm_interface": true/false,
          "confidence": "high/medium/low",
          "reasoning": "Brief explanation"
        }
        """
        
        vlm_result = query_vlm(images=frames + [final], prompt=vlm_prompt)
        
        if vlm_result.get("success"):
            parsed = vlm_result.get("parsed", {})
            if parsed.get("used_crm_interface", False):
                vlm_score = 20
                feedback_parts.append("VLM confirmed UI usage")
            else:
                feedback_parts.append("VLM did not detect CRM UI workflow")
        else:
            feedback_parts.append("VLM query failed, skipping UI bonus")
            
    except ImportError:
        feedback_parts.append("VLM library unavailable, skipping UI check")

    score += vlm_score

    # Strict passing criteria: Must perfectly hit target records and avoid all control records
    key_criteria_met = (alex_acc_count == 5 and alex_opp_count == 5 and taylor_control_errors == 0)
    passed = (score >= 80) and key_criteria_met

    if not passed and key_criteria_met:
        feedback_parts.append("Key DB criteria met, but failed due to low secondary score.")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }