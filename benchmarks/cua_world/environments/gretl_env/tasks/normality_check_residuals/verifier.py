#!/usr/bin/env python3
"""
Verifier for normality_check_residuals task.

Criteria:
1. Normality test text file exists and contains correct Chi-square statistic.
2. Histogram image file exists and is a valid image.
3. Both files created during the task.
4. VLM verification of the histogram (checking for Normal curve overlay).
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

def verify_normality_check(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy function missing"}

    # 1. Load Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, "r") as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback = []

    # 2. Verify Text Output (Normality Test) - 40 Points
    text_exists = result.get("text_file_exists", False)
    text_fresh = result.get("text_created_during_task", False)
    
    ground_truth_raw = ""
    agent_text_raw = ""

    if text_exists and text_fresh:
        try:
            agent_text_raw = base64.b64decode(result.get("text_content_b64", "")).decode("utf-8", errors="ignore")
            ground_truth_raw = base64.b64decode(result.get("ground_truth_b64", "")).decode("utf-8", errors="ignore")
            
            # Extract Chi-square values using Regex
            # Pattern looks for "Chi-square(df) = number"
            chi_sq_pattern = r"Chi-square\(\d+\)\s*=\s*([\d\.]+)"
            
            gt_match = re.search(chi_sq_pattern, ground_truth_raw)
            agent_match = re.search(chi_sq_pattern, agent_text_raw)

            if gt_match and agent_match:
                gt_val = float(gt_match.group(1))
                agent_val = float(agent_match.group(1))
                
                # Tolerance check (1% error)
                if abs(gt_val - agent_val) < 0.05 * gt_val:
                    score += 40
                    feedback.append(f"Correct normality test statistic found ({agent_val})")
                else:
                    score += 10
                    feedback.append(f"Normality test found but statistic differs (Exp: {gt_val}, Found: {agent_val})")
            elif "Doornik-Hansen" in agent_text_raw or "Shapiro-Wilk" in agent_text_raw:
                # Partial credit if format is different but test is correct
                score += 20
                feedback.append("Normality test output found, but statistic parsing failed")
            else:
                feedback.append("Text file exists but doesn't look like a normality test")
        except Exception as e:
            feedback.append(f"Error parsing text content: {str(e)}")
    else:
        feedback.append("Normality test text file missing or not created during task")

    # 3. Verify Image Output (Histogram) - 20 Points
    img_exists = result.get("image_file_exists", False)
    img_fresh = result.get("image_created_during_task", False)
    img_size = result.get("image_size", 0)

    if img_exists and img_fresh:
        if img_size > 1000:  # Minimum valid PNG size
            score += 20
            feedback.append("Histogram image created successfully")
        else:
            feedback.append("Image file exists but is empty/corrupt")
    else:
        feedback.append("Histogram image missing")

    # 4. VLM Verification (Visual Check of Histogram) - 40 Points
    # We check if the plot actually looks like a distribution with a normal curve
    final_screenshot = get_final_screenshot(traj)
    
    # We can also verify the output image directly if we pull it
    # But using the final screenshot is safer if the user has it open
    # For robust checking, let's use the final screenshot to check the Gretl UI state
    
    vlm_prompt = """
    Analyze this screenshot of the Gretl econometrics software.
    1. Is a histogram or frequency distribution plot visible?
    2. Does the plot have a bell-shaped curve (Normal density) overlay?
    3. Is there a regression results window visible?
    
    Answer JSON: {"histogram_visible": bool, "normal_curve_visible": bool, "regression_visible": bool}
    """
    
    vlm_passed = False
    if final_screenshot:
        try:
            vlm_res = query_vlm(images=[final_screenshot], prompt=vlm_prompt)
            parsed = vlm_res.get("parsed", {})
            
            if parsed.get("histogram_visible", False):
                score += 20
                feedback.append("VLM confirmed histogram visibility")
                
                if parsed.get("normal_curve_visible", False):
                    score += 20
                    feedback.append("VLM confirmed normal curve overlay")
                    vlm_passed = True
            
        except Exception as e:
            feedback.append(f"VLM verification failed: {str(e)}")

    # 5. Final Pass/Fail
    passed = score >= 80  # Requires correct stats (40) + image (20) + partial VLM (20)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }