#!/usr/bin/env python3
"""
Verifier for identify_outbreak_source_rr task.
"""

import json
import os
import re
import tempfile
import logging
from vlm_utils import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_identify_outbreak_source_rr(traj, env_info, task_info):
    """
    Verifies that the agent correctly identified the outbreak source.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    max_score = 100
    feedback_parts = []
    
    # 1. Retrieve Result and Ground Truth Files
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    
    try:
        # Get result JSON
        copy_from_env("C:\\Users\\Docker\\Documents\\task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
            
        # Get ground truth
        copy_from_env("C:\\Users\\Docker\\Documents\\OutbreakData\\ground_truth.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            ground_truth = json.load(f)
            
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task files: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)

    # 2. Check File Existence (10 pts)
    if not result_data.get("output_exists"):
        return {"passed": False, "score": 0, "feedback": "Report file 'culprit_report.txt' was not created."}
    
    score += 10
    feedback_parts.append("Report file created.")

    # 3. Parse Report Content
    content = result_data.get("report_content", "")
    
    # Extract Culprit using Regex
    culprit_match = re.search(r"Culprit:\s*(\w+)", content, re.IGNORECASE)
    rr_match = re.search(r"RiskRatio:\s*([0-9\.]+)", content, re.IGNORECASE)
    
    reported_culprit = culprit_match.group(1) if culprit_match else None
    reported_rr = float(rr_match.group(1)) if rr_match else None
    
    actual_culprit = ground_truth.get("culprit")
    actual_rr = ground_truth.get("risk_ratio")
    
    # 4. Verify Culprit (50 pts)
    if reported_culprit and reported_culprit.lower() == actual_culprit.lower():
        score += 50
        feedback_parts.append(f"Correctly identified culprit: {actual_culprit}.")
    else:
        feedback_parts.append(f"Incorrect culprit. Reported: {reported_culprit}, Actual: {actual_culprit}.")
        
    # 5. Verify Risk Ratio (30 pts)
    if reported_rr is not None:
        # Allow 10% tolerance
        tolerance = 0.1 * actual_rr
        if abs(reported_rr - actual_rr) <= tolerance:
            score += 30
            feedback_parts.append(f"Risk Ratio accurate ({reported_rr}).")
        else:
            score += 10 # Partial credit for format
            feedback_parts.append(f"Risk Ratio inaccurate. Reported: {reported_rr}, Actual: {actual_rr:.2f}.")
    else:
        feedback_parts.append("Risk Ratio format incorrect or missing.")
        
    # 6. VLM Verification of Workflow (10 pts)
    # Check if 'Classic Analysis' and 'Risk Ratio' tables were visible
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        vlm_prompt = """
        Review these screenshots of Epi Info 7 usage.
        Does the user perform the following actions:
        1. Open the 'Classic Analysis' or 'Analysis' module?
        2. Load a dataset?
        3. Generate tables showing Risk Ratios (Look for 'Risk-Based' or 'RR' columns)?
        
        Answer JSON: {"analysis_visible": bool, "risk_ratios_visible": bool}
        """
        
        try:
            vlm_res = query_vlm(images=frames, prompt=vlm_prompt)
            if vlm_res and vlm_res.get("parsed"):
                parsed = vlm_res.get("parsed")
                if parsed.get("risk_ratios_visible"):
                    score += 10
                    feedback_parts.append("Visual evidence of Risk Ratio analysis found.")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            # Fallback: if they got the right answer, they probably did it.
            if score >= 60:
                score += 10

    passed = score >= 90
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }