#!/usr/bin/env python3
"""
Verifier for JASP Multinomial Regression Task
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_multinomial_regression(traj, env_info, task_info):
    """
    Verifies that the agent performed a Multinomial Logistic Regression in JASP.
    
    Checks:
    1. Output JASP file exists and is a valid ZIP archive (modified during task).
    2. Output text file exists and contains a valid R² value (0.70 - 0.95).
    3. JASP file contains evidence of Multinomial Regression (via content sniff).
    4. VLM verification of the workflow.
    """
    
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_r2_min = metadata.get('expected_r2_min', 0.70)
    expected_r2_max = metadata.get('expected_r2_max', 0.95)

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

    score = 0
    feedback_parts = []
    
    # 2. Check JASP File (40 points)
    jasp_exists = result.get('jasp_file_exists', False)
    jasp_fresh = result.get('jasp_created_during_task', False)
    jasp_content = result.get('jasp_analysis_snippet', "")
    archive_list = result.get('archive_listing', "")
    
    if jasp_exists and jasp_fresh:
        score += 15
        feedback_parts.append("JASP project file saved.")
        
        # Check internal structure
        if "Multinomial" in jasp_content or "Multinomial" in archive_list:
            score += 25
            feedback_parts.append("JASP file contains Multinomial Regression analysis.")
        elif "analyses" in archive_list or "index.html" in archive_list:
            # Valid JASP file but grep missed the specific keyword (fallback)
            score += 15
            feedback_parts.append("Valid JASP archive found (analysis type verification inconclusive).")
        else:
            feedback_parts.append("JASP file created but appears empty or invalid.")
    elif jasp_exists:
        feedback_parts.append("JASP file found but was not created during this task (stale).")
    else:
        feedback_parts.append("JASP project file not found.")

    # 3. Check R² Value (30 points)
    text_exists = result.get('text_file_exists', False)
    text_content = result.get('text_content', "").strip()
    
    r2_valid = False
    if text_exists:
        try:
            r2_val = float(text_content)
            if 0.0 <= r2_val <= 1.0:
                score += 10 # It's a valid probability/stat
                if expected_r2_min <= r2_val <= expected_r2_max:
                    score += 20
                    feedback_parts.append(f"Reported R² ({r2_val}) is correct.")
                    r2_valid = True
                else:
                    feedback_parts.append(f"Reported R² ({r2_val}) is outside expected range ({expected_r2_min}-{expected_r2_max}).")
            else:
                feedback_parts.append(f"Reported value '{text_content}' is not a valid statistic (0-1).")
        except ValueError:
            feedback_parts.append(f"Reported content '{text_content}' is not a number.")
    else:
        feedback_parts.append("R² result file not found.")

    # 4. VLM Verification (30 points)
    # Using trajectory frames to verify UI interaction steps
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    if frames:
        vlm_prompt = (
            "Review these screenshots of a JASP statistical analysis session.\n"
            "1. Do you see the JASP interface open?\n"
            "2. Is the 'Multinomial Logistic Regression' analysis selected or visible in the results panel?\n"
            "3. Are variables like 'species', 'island', or 'bill_depth' being used?\n"
            "4. Is there an output table showing 'Odds Ratios' or 'Multinomial'?\n"
            "Respond with 'Yes' or 'No' for each and provide a final confidence score (0-10)."
        )
        
        vlm_result = query_vlm(images=frames + [final_screen], prompt=vlm_prompt)
        vlm_feedback = vlm_result.get('result', '').lower()
        
        if "yes" in vlm_feedback and ("multinomial" in vlm_feedback or "odds" in vlm_feedback):
            score += 30
            feedback_parts.append("VLM confirms Multinomial Regression workflow.")
        elif "yes" in vlm_feedback:
            score += 15
            feedback_parts.append("VLM confirms JASP usage but analysis type unclear.")
        else:
            feedback_parts.append("VLM could not verify the workflow.")
    else:
        feedback_parts.append("No trajectory frames available for VLM.")

    # Final Pass/Fail
    passed = score >= 65 and r2_valid
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }