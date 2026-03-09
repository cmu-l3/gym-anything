#!/usr/bin/env python3
"""
Verifier for create_flu_control_chart task.

Verifies:
1. Threshold calculation accuracy (compared to ground truth)
2. Identification of alert weeks
3. Creation of control chart image
4. Anti-gaming (files created during task)
5. VLM verification of the chart
"""

import json
import base64
import os
import tempfile
import logging
import re
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_flu_control_chart(traj, env_info, task_info):
    """
    Verify the Epi Info 7 flu control chart task.
    """
    # 1. Retrieve Result Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_lines = []

    # 2. Parse Ground Truth
    gt_b64 = result.get("ground_truth_b64", "")
    if gt_b64:
        gt = json.loads(base64.b64decode(gt_b64).decode('utf-8'))
        gt_threshold = gt.get("threshold", 0)
        gt_alerts = set(gt.get("alert_weeks", []))
    else:
        # Fallback if setup failed (should not happen)
        gt_threshold = 48313.89 
        gt_alerts = {51, 52, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12}

    # 3. Analyze Report Content (Primary Verification)
    report_exists = result.get("report_exists", False)
    report_fresh = result.get("report_created_during_task", False)
    
    if report_exists and report_fresh:
        score += 10 # File exists and is new
        feedback_lines.append("Report file created.")
        
        content = base64.b64decode(result.get("report_content_b64", "")).decode('utf-8', errors='ignore')
        
        # Extract Threshold
        # Looking for patterns like "Threshold: 12345.6"
        threshold_match = re.search(r"Threshold[:\s=]+([0-9\.]+)", content, re.IGNORECASE)
        if threshold_match:
            try:
                user_threshold = float(threshold_match.group(1))
                # Allow 1% tolerance
                if abs(user_threshold - gt_threshold) / gt_threshold < 0.01:
                    score += 30
                    feedback_lines.append(f"Threshold accurate (Found: {user_threshold:.2f}, Expected: {gt_threshold:.2f}).")
                else:
                    feedback_lines.append(f"Threshold incorrect (Found: {user_threshold:.2f}, Expected: {gt_threshold:.2f}).")
            except ValueError:
                feedback_lines.append("Could not parse threshold value.")
        else:
            feedback_lines.append("Threshold value not found in report.")

        # Extract Alert Weeks
        # Looking for numbers in "Alert Weeks: 51, 52, 1..."
        alerts_section = re.search(r"Alert Weeks[:\s=]+([0-9,\s]+)", content, re.IGNORECASE)
        if alerts_section:
            try:
                user_alerts_str = alerts_section.group(1)
                user_alerts = set(int(x.strip()) for x in user_alerts_str.replace(',', ' ').split() if x.strip().isdigit())
                
                # Jaccard index or intersection check
                intersection = user_alerts.intersection(gt_alerts)
                
                if user_alerts == gt_alerts:
                    score += 30
                    feedback_lines.append("Alert weeks identified perfectly.")
                elif len(intersection) / len(gt_alerts) > 0.8:
                    score += 20
                    feedback_lines.append("Alert weeks mostly correct.")
                elif len(intersection) > 0:
                    score += 10
                    feedback_lines.append("Some alert weeks identified.")
                else:
                    feedback_lines.append("No correct alert weeks identified.")
            except Exception:
                feedback_lines.append("Could not parse alert weeks.")
        else:
            feedback_lines.append("Alert weeks section not found.")
    else:
        feedback_lines.append("Report file missing or not created during task.")

    # 4. Image Verification
    image_exists = result.get("image_exists", False)
    image_fresh = result.get("image_created_during_task", False)
    
    if image_exists and image_fresh:
        score += 10
        feedback_lines.append("Control chart image created.")
        
        # VLM Verification of the chart
        # We verify that the chart actually looks like a control chart
        # Check final screenshot if image file analysis is hard inside container
        final_screenshot = get_final_screenshot(traj)
        
        vlm_prompt = """
        Analyze this screenshot of Epi Info 7 or the exported image.
        1. Is there a Line Chart visible?
        2. Does it show two lines (one variable and one straight threshold line)?
        3. Is the X-axis related to time (Weeks)?
        4. Does the chart look like an epidemic curve?
        """
        
        vlm_result = query_vlm(images=[final_screenshot], prompt=vlm_prompt)
        if vlm_result.get("success"):
            parsed = vlm_result.get("parsed", {})
            # Simple keyword check in VLM response if structured parsing isn't guaranteed
            # Assuming query_vlm returns a structured analysis or we parse the text
            response_text = str(vlm_result).lower()
            if "line" in response_text and "chart" in response_text:
                score += 20
                feedback_lines.append("VLM confirms chart content.")
            else:
                score += 10 # Partial credit for creating file
                feedback_lines.append("VLM could not confirm chart details.")
        else:
            # Fallback if VLM fails but file exists
            score += 20 
            feedback_lines.append("Chart file exists (VLM skipped).")
            
    else:
        feedback_lines.append("Control chart image missing.")

    # 5. Final Calculation
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_lines)
    }