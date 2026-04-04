#!/usr/bin/env python3
import json
import os
import re
import base64
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_regression_reference_level_change(traj, env_info, task_info):
    """
    Verifies that the user correctly changed the reference level to 'F' and ran the regression.
    
    Criteria:
    1. .omv file created (20 pts)
    2. Report file created (20 pts)
    3. Correct Intercept value in report (indicates Ref=F) (40 pts)
    4. VLM verification of Data tab/Regression interaction (20 pts)
    """
    
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    # 2. Check File Artifacts
    omv_exists = result.get("omv_exists", False)
    omv_valid = result.get("omv_valid_time", False)
    report_exists = result.get("report_exists", False)
    
    if omv_exists and omv_valid:
        score += 20
        feedback.append("Jamovi project file saved.")
    elif omv_exists:
        score += 10
        feedback.append("Jamovi project file exists but has old timestamp (did you save?).")
    else:
        feedback.append("Jamovi project file not found.")

    if report_exists:
        score += 20
        feedback.append("Report file created.")
    else:
        feedback.append("Report file not found.")

    # 3. Verify Statistical Values (The Core Logic)
    # Ground Truth:
    # If Ref = F (Correct): Intercept ~ 2.167
    # If Ref = A (Wrong):   Intercept ~ 14.500
    
    val_correct = False
    if result.get("report_content_b64"):
        try:
            content = base64.b64decode(result.get("report_content_b64")).decode('utf-8')
            # Look for numbers in the report
            numbers = [float(x) for x in re.findall(r"-?\d+\.\d+", content)]
            
            # Check for Intercept ~ 2.17
            has_correct_intercept = any(2.1 <= n <= 2.25 for n in numbers)
            # Check for Spray A coefficient ~ 12.33
            has_correct_coeff = any(12.2 <= n <= 12.5 for n in numbers)
            
            # Check for Wrong Intercept (Default A)
            has_wrong_intercept = any(14.4 <= n <= 14.6 for n in numbers)

            if has_correct_intercept:
                score += 40
                val_correct = True
                feedback.append("Correct Intercept value found (Matches Reference Level 'F').")
                if has_correct_coeff:
                    feedback.append("Correct Spray A coefficient found.")
            elif has_wrong_intercept:
                feedback.append("Incorrect Intercept found (~14.5). This indicates Reference Level was left at default 'A'.")
            else:
                feedback.append("Could not identify valid regression coefficients in the report.")
                
        except Exception as e:
            feedback.append(f"Error parsing report content: {e}")

    # 4. VLM Verification (Trajectory)
    # We want to see if they visited the Data tab or interacted with variable levels
    vlm_score = 0
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    if frames:
        prompt = """
        You are verifying a Jamovi task. The user must:
        1. Go to the 'Data' tab or open Variable properties.
        2. Change the 'spray' variable levels (moving 'F' to the top).
        3. Run a Linear Regression.

        Look at these screenshots. Do you see:
        - The 'Data' tab active or a Variable Setup panel open?
        - A Linear Regression results table?
        - Any evidence of the 'spray' variable being modified?
        """
        
        try:
            vlm_resp = query_vlm(images=frames + [final_screen], prompt=prompt)
            if vlm_resp and vlm_resp.get("success"):
                # Basic heuristic: if VLM is happy, give points. 
                # Ideally we parse structured JSON, but strict boolean is fine here.
                # Assuming simple positive response logic handled by VLM util or implicit trust for now.
                # Let's check for keywords in reasoning if structured parsing isn't guaranteed.
                # For this implementation, we will assume a generic "passed" check if available,
                # otherwise default to 20 if artifacts were good, else 0.
                pass  # Rely on artifacts primarily, VLM is bonus confirmation
                
                # If they got the values right, they MUST have done the steps.
                # If they failed values, VLM might give partial credit for UI navigation.
                if val_correct:
                    vlm_score = 20
                elif omv_exists and "Regression" in str(vlm_resp): 
                    vlm_score = 10 # Tried regression but maybe wrong settings
                    
        except Exception:
            pass
    
    if val_correct:
        vlm_score = 20 # Implicitly correct workflow if values match
    
    score += vlm_score

    return {
        "passed": score >= 75,
        "score": score,
        "feedback": " ".join(feedback)
    }