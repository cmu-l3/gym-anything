#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_leave_policy(traj, env_info, task_info):
    """
    Verify the leave policy configuration task.
    
    Strategy:
    1. Check if the database file was modified during the task (Anti-gaming).
    2. Analyze the SQL output from the export script (if available).
    3. Use VLM to verify the UI steps via trajectory frames (Critical).
    """
    
    # 1. Setup and Load Result
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\workspace\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 2. Database Activity Check (20 points)
    db_state = result_data.get("db_state", {})
    if db_state.get("modified_during_task", False):
        score += 20
        feedback_parts.append("Database modification detected (Save action confirmed).")
    else:
        feedback_parts.append("No database changes detected (Did you save?).")

    # 3. SQL/Data Verification (20 points - Bonus/Best Effort)
    # If the SQL query ran and found the record, full points.
    sql_output = result_data.get("sql_output", "").lower()
    policy_name_expected = "grade a - annual leave policy 2025"
    
    if policy_name_expected in sql_output:
        score += 20
        feedback_parts.append("Database record confirmed via SQL.")
    else:
        # If SQL failed or didn't run, we rely more on VLM, but don't penalize heavily 
        # if the DB file was at least modified.
        if db_state.get("modified_during_task", False):
            feedback_parts.append("SQL verification inconclusive, relying on visual evidence.")
        else:
            feedback_parts.append("No record found in database.")

    # 4. VLM Trajectory Verification (60 points)
    # We look for evidence of the specific configuration steps.
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    
    # Add final frame to analysis list
    all_frames = frames + [final_frame] if final_frame else frames

    prompt = f"""
    You are an expert HR systems auditor. Review these screenshots of a user configuring a Leave Policy in AttendHRM.
    
    The user was tasked to create a policy with these EXACT settings:
    1. Name: "Grade A - Annual Leave Policy 2025"
    2. Employee Grade: "Grade A"
    3. Casual Leave: 12 days (No Carry Forward)
    4. Sick Leave: 10 days (No Carry Forward)
    5. Earned Leave: 15 days (Yes Carry Forward)

    Please analyze the screenshots for:
    - **Policy Name Visibility:** Is the policy name visible in a text field?
    - **Grade Selection:** Is "Grade A" selected?
    - **Entitlements Table:** Can you see a table with rows for Casual, Sick, and Earned leave?
    - **Values:** Do the numbers 12, 10, and 15 appear in the correct rows?
    - **Carry Forward:** Are there checkboxes or yes/no toggles for carry forward?

    Output JSON:
    {{
        "policy_name_correct": boolean,
        "grade_selected": boolean,
        "entitlements_visible": boolean,
        "values_match": boolean,
        "carry_forward_logic_visible": boolean,
        "final_save_indicated": boolean,
        "confidence": "high|medium|low",
        "reasoning": "string"
    }}
    """
    
    vlm_result = query_vlm(images=all_frames, prompt=prompt)
    
    vlm_score = 0
    if vlm_result and vlm_result.get('success'):
        parsed = vlm_result.get('parsed', {})
        if parsed.get('policy_name_correct'): vlm_score += 15
        if parsed.get('entitlements_visible'): vlm_score += 10
        if parsed.get('values_match'): vlm_score += 20
        if parsed.get('final_save_indicated') or db_state.get("modified_during_task", False): vlm_score += 15
        
        feedback_parts.append(f"VLM Analysis: {parsed.get('reasoning')}")
    else:
        feedback_parts.append("VLM analysis failed.")
    
    score += vlm_score

    # Final Pass Logic
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }