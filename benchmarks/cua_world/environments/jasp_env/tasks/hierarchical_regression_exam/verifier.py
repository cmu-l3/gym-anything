#!/usr/bin/env python3
"""
Verifier for Hierarchical Linear Regression Task in JASP.

Verification Strategy:
1. File Existence: Checks for .jasp and .txt output files.
2. Anti-Gaming: Checks file timestamps against task start time.
3. Content Verification: Parses the text report for specific R² and R² Change values.
   - Model 1 R² (Revise only) ≈ 0.157
   - Model 2 R² Change (adding Anxiety) ≈ 0.053
   - These specific values confirm the correct variable entry order (Hierarchical).
4. VLM Verification: Inspects trajectory/final screenshot to confirm JASP UI state.
"""

import json
import os
import re
import base64
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_hierarchical_regression(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # 1. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Data
    jasp_exists = result.get("jasp_file_exists", False)
    jasp_valid_time = result.get("jasp_file_created_during_task", False)
    report_exists = result.get("report_file_exists", False)
    report_valid_time = result.get("report_file_created_during_task", False)
    report_b64 = result.get("report_content_base64", "")
    
    # Decode report content
    report_text = ""
    if report_b64:
        try:
            report_text = base64.b64decode(report_b64).decode('utf-8', errors='ignore')
        except:
            report_text = ""

    score = 0
    feedback = []

    # 3. Check File Artifacts (30 points)
    if jasp_exists and jasp_valid_time:
        score += 15
        feedback.append("JASP project file created successfully.")
    elif jasp_exists:
        feedback.append("JASP file exists but timestamp is invalid (pre-existing?).")
    else:
        feedback.append("JASP project file missing.")

    if report_exists and report_valid_time:
        score += 15
        feedback.append("Report text file created successfully.")
    else:
        feedback.append("Report text file missing or timestamp invalid.")

    # 4. Check Statistical Values in Report (50 points)
    # We look for numbers in the text that match the expected ranges.
    # Ground truth (approx): Model 1 R^2 ~ 0.15-0.16. Model 2 Change ~ 0.05.
    
    metadata = task_info.get("metadata", {}).get("ground_truth", {})
    r2_min = metadata.get("model1_r2_min", 0.13)
    r2_max = metadata.get("model1_r2_max", 0.18)
    change_min = metadata.get("model2_r2_change_min", 0.03)
    change_max = metadata.get("model2_r2_change_max", 0.07)

    # Find all floats in the text
    floats_in_text = [float(x) for x in re.findall(r"0\.\d+", report_text)]
    
    # Check for Model 1 R^2
    has_model1_r2 = any(r2_min <= x <= r2_max for x in floats_in_text)
    
    # Check for Model 2 R^2 Change
    # This implies the user successfully ran a hierarchical model, not just a standard one
    has_r2_change = any(change_min <= x <= change_max for x in floats_in_text)

    if has_model1_r2:
        score += 20
        feedback.append("Report contains correct R² for Model 1 (Revise).")
    else:
        feedback.append("Report does not contain valid R² for Model 1 (Expected ~0.157).")

    if has_r2_change:
        score += 30
        feedback.append("Report contains correct R² Change for Model 2 (Anxiety).")
    else:
        feedback.append("Report does not contain valid R² Change (Expected ~0.053). Did you configure Block 2 correctly?")

    # 5. VLM Verification (20 points)
    # Use VLM to confirm the UI shows the Linear Regression table with "Model 1" and "Model 2" rows
    final_screenshot = get_final_screenshot(traj)
    frames = sample_trajectory_frames(traj, n=2)
    
    vlm_score = 0
    if final_screenshot:
        vlm_prompt = (
            "Analyze this JASP screenshot. Does it show a Linear Regression output table? "
            "Are there rows indicating 'Model 1' and 'Model 2' (or H0/H1)? "
            "Is there a column for 'R² Change' or 'Change Statistics'? "
            "Answer JSON: {'table_visible': bool, 'two_models_visible': bool, 'change_stats_visible': bool}"
        )
        
        try:
            vlm_response = query_vlm(images=[final_screenshot], prompt=vlm_prompt)
            # Parse simple JSON from VLM
            import re
            json_match = re.search(r"\{.*\}", vlm_response.get("result", ""), re.DOTALL)
            if json_match:
                data = json.loads(json_match.group(0))
                if data.get("table_visible"): vlm_score += 5
                if data.get("two_models_visible"): vlm_score += 10
                if data.get("change_stats_visible"): vlm_score += 5
                feedback.append(f"VLM verification passed: {vlm_score}/20 pts")
            else:
                # Fallback if VLM output isn't JSON
                if "Model 1" in vlm_response.get("result", "") and "Model 2" in vlm_response.get("result", ""):
                    vlm_score = 20
                    feedback.append("VLM visual check passed.")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            # If VLM fails but file analysis passed, give partial credit to avoid false fails
            if score >= 60:
                vlm_score = 10 
    
    score += vlm_score

    # Final Pass Logic
    # Must have created files and found the hierarchical effect (R2 Change)
    passed = (score >= 70) and has_r2_change and jasp_exists

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }