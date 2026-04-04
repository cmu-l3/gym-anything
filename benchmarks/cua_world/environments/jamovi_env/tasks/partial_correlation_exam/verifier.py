#!/usr/bin/env python3
import json
import os
import tempfile
import base64
import re
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

def verify_partial_correlation_exam(traj, env_info, task_info):
    """
    Verifies the partial_correlation_exam task.
    
    Criteria:
    1. Report file exists and was created during task (10 pts)
    2. OMV file exists and is valid size (10 pts)
    3. Report content: Partial r is within valid range (approx -0.25) (25 pts)
    4. Report content: Partial r is negative (5 pts)
    5. Report content: P-value < 0.05 (15 pts)
    6. Report content: Significant = Yes (10 pts)
    7. VLM: Trajectory shows Partial Correlation UI interaction (25 pts)
    """
    
    # 1. Setup and load result data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_log = []
    
    # Extract Metadata
    metadata = task_info.get('metadata', {})
    expected_r = metadata.get('expected_partial_r_center', -0.247)
    tolerance = metadata.get('expected_partial_r_tolerance', 0.1)

    # =========================================================
    # CRITERION 1 & 2: File Existence & Anti-Gaming (20 pts)
    # =========================================================
    omv_exists = result.get('omv_exists', False)
    omv_fresh = result.get('omv_created_during_task', False)
    omv_size = int(result.get('omv_size_bytes', 0))
    
    report_exists = result.get('report_exists', False)
    report_fresh = result.get('report_created_during_task', False)
    
    if omv_exists and omv_fresh and omv_size > 5000:
        score += 10
        feedback_log.append("OMV project file created successfully.")
    else:
        feedback_log.append("OMV file missing, too small, or not created during task.")

    if report_exists and report_fresh:
        score += 10
        feedback_log.append("Report file created successfully.")
    else:
        feedback_log.append("Report file missing or not created during task.")

    # =========================================================
    # CRITERION 3-6: Content Verification (55 pts)
    # =========================================================
    content_valid = False
    
    if report_exists:
        try:
            content_b64 = result.get('report_content_b64', "")
            content_str = base64.b64decode(content_valid).decode('utf-8') if content_b64 else ""
            
            # Parse Partial r
            # Look for "Partial r: -0.247" type patterns
            r_match = re.search(r'Partial r:?\s*([-+]?[0-9]*\.?[0-9]+)', content_str, re.IGNORECASE)
            p_match = re.search(r'P-value:?\s*([0-9]*\.?[0-9]+)', content_str, re.IGNORECASE)
            sig_match = re.search(r'Significant:?\s*(Yes|No|True|False)', content_str, re.IGNORECASE)
            
            if r_match:
                r_val = float(r_match.group(1))
                # Check range (Criterion 3: 25 pts)
                if (expected_r - tolerance) <= r_val <= (expected_r + tolerance):
                    score += 25
                    feedback_log.append(f"Partial r value ({r_val}) is correct.")
                    content_valid = True
                else:
                    feedback_log.append(f"Partial r value ({r_val}) is incorrect. Expected approx {expected_r}.")
                
                # Check sign (Criterion 4: 5 pts)
                if r_val < 0:
                    score += 5
                    feedback_log.append("Partial r direction (negative) is correct.")
            else:
                feedback_log.append("Could not parse 'Partial r' from report.")

            if p_match:
                p_val = float(p_match.group(1))
                # Check p-value < 0.05 (Criterion 5: 15 pts)
                if p_val < 0.05:
                    score += 15
                    feedback_log.append("P-value is correctly significant (<0.05).")
            
            if sig_match:
                sig_str = sig_match.group(1).lower()
                # Check interpretation (Criterion 6: 10 pts)
                if sig_str in ['yes', 'true']:
                    score += 10
                    feedback_log.append("Significance interpretation correct.")
        except Exception as e:
            feedback_log.append(f"Error parsing report content: {str(e)}")

    # =========================================================
    # CRITERION 7: VLM Trajectory Verification (25 pts)
    # =========================================================
    vlm_passed = False
    try:
        frames = sample_trajectory_frames(traj, n=4)
        final_shot = get_final_screenshot(traj)
        if final_shot:
            frames.append(final_shot)
            
        prompt = """
        Review these screenshots of a user interacting with Jamovi statistical software.
        The goal is to run a 'Partial Correlation'.
        
        Look for:
        1. A panel or menu titled 'Partial Correlation'.
        2. Lists of variables being moved into boxes labeled 'Variables' and 'Control'.
        3. A results table showing correlation values.
        
        Does the user successfully access the Partial Correlation analysis and produce results?
        Answer JSON: {"success": true/false, "reason": "..."}
        """
        
        vlm_res = query_vlm(images=frames, prompt=prompt)
        
        if vlm_res and vlm_res.get('parsed', {}).get('success', False):
            score += 25
            vlm_passed = True
            feedback_log.append("VLM confirms Partial Correlation workflow.")
        else:
            feedback_log.append("VLM did not observe Partial Correlation workflow.")
            
    except Exception as e:
        feedback_log.append(f"VLM verification failed: {str(e)}")

    # =========================================================
    # Final Decision
    # =========================================================
    # Pass threshold: 60 points AND content must be valid (r value correct)
    passed = (score >= 60) and content_valid
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_log)
    }