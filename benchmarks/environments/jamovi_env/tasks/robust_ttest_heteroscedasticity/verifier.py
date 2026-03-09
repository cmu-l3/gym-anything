#!/usr/bin/env python3
"""
Verifier for robust_ttest_heteroscedasticity task.
Verifies that the agent correctly identified unequal variances and reported Welch's t-test results.
"""

import json
import os
import tempfile
import base64
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_robust_ttest_heteroscedasticity(traj, env_info, task_info):
    """
    Verify the robust t-test task results.
    
    Criteria:
    1. Result text file exists and was created during task.
    2. Project (.omv) file exists.
    3. Results contain correct Welch's t-test statistics (Df ~ 11.1, NOT 22).
    4. Levene's test p-value is reported and significant.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {}).get('ground_truth', {})
    
    # Ground Truth Values
    EXPECTED_STUDENT_DF = 22.0
    EXPECTED_WELCH_DF_MIN = 10.5
    EXPECTED_WELCH_DF_MAX = 12.0
    EXPECTED_LEVENE_P_MAX = 0.05  # Should be significant (< 0.001 typically)
    
    score = 0
    feedback_parts = []
    
    # 1. Load result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    # 2. Check File Existence (20 pts)
    txt_exists = result_data.get("txt_exists", False)
    omv_exists = result_data.get("omv_exists", False)
    created_during = result_data.get("txt_created_during_task", False)
    
    if omv_exists:
        score += 10
        feedback_parts.append("Project file (.omv) saved.")
    else:
        feedback_parts.append("Project file missing.")

    if txt_exists and created_during:
        score += 10
        feedback_parts.append("Result text file created.")
    else:
        feedback_parts.append("Result text file missing or stale.")
        return {"passed": False, "score": score, "feedback": " ".join(feedback_parts)}

    # 3. Parse Result Content
    try:
        content = base64.b64decode(result_data.get("txt_content_base64", "")).decode('utf-8')
    except:
        return {"passed": False, "score": score, "feedback": "Could not decode result file."}
        
    # Helper to extract values
    def get_val(key):
        # Matches "Key: Value" or "Key = Value" case insensitive
        match = re.search(f"{key}[\\s:=]+([\\d\\.\\-a-zA-Z]+)", content, re.IGNORECASE)
        if match:
            return match.group(1)
        return None

    # Extract reported values
    reported_levene_p = get_val("Levene_p")
    reported_choice = get_val("Statistic_Choice")
    reported_t = get_val("t_statistic")
    reported_df = get_val("df")
    reported_p = get_val("p_value")
    
    # 4. Check Assumption Check (Levene's) (15 pts)
    try:
        levene_p_val = float(reported_levene_p)
        if levene_p_val < EXPECTED_LEVENE_P_MAX:
            score += 15
            feedback_parts.append(f"Levene's test correctly reported as significant (p={levene_p_val}).")
        else:
            feedback_parts.append(f"Levene's p-value seems wrong or not significant (p={levene_p_val}).")
    except (TypeError, ValueError):
        feedback_parts.append("Could not parse Levene_p value.")

    # 5. Check Statistical Decision (Welch vs Student) (45 pts)
    # This is the CRITICAL part of the task
    try:
        df_val = float(reported_df)
        
        # Check if they reported Student's t-test (df=22)
        if abs(df_val - EXPECTED_STUDENT_DF) < 0.1:
            feedback_parts.append("FAIL: Reported Student's t-test results (df=22). The task required a robust test due to unequal variances.")
        # Check if they reported Welch's t-test (df ~ 11.1)
        elif EXPECTED_WELCH_DF_MIN <= df_val <= EXPECTED_WELCH_DF_MAX:
            score += 45
            feedback_parts.append(f"SUCCESS: Correctly reported Welch's t-test (df={df_val}).")
        else:
            feedback_parts.append(f"Reported df ({df_val}) is incorrect.")
            
    except (TypeError, ValueError):
        feedback_parts.append("Could not parse degrees of freedom (df).")

    # 6. Check Statistic Choice Label (10 pts)
    if reported_choice and "welch" in reported_choice.lower():
        score += 10
        feedback_parts.append("Explicitly labeled as 'Welch'.")
    elif reported_choice:
        feedback_parts.append(f"Labeled as '{reported_choice}' instead of 'Welch'.")
    else:
        feedback_parts.append("Statistic choice not labeled.")

    # 7. Check T-Statistic Value (10 pts)
    try:
        t_val = float(reported_t)
        # Welch t should be approx 2.37 (same as student in this specific case, but checking range)
        if 2.30 <= abs(t_val) <= 2.45:
            score += 10
            feedback_parts.append(f"T-statistic correct ({t_val}).")
        else:
            feedback_parts.append(f"T-statistic incorrect ({t_val}).")
    except (TypeError, ValueError):
        feedback_parts.append("Could not parse t_statistic.")

    passed = (score >= 65)  # Threshold allows missing minor formatting but strictly requires Welch's results
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }