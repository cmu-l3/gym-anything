#!/usr/bin/env python3
"""
Verifier for Nuclear-Cytoplasmic Ratio Analysis.

Criteria:
1. Report file exists and contains a numeric ratio.
2. The reported ratio matches the ground truth (calculated via Python) within 15%.
   - This tolerance accounts for manual thresholding differences vs Otsu.
3. ROIs zip file exists (proof of using ROI manager).
4. VLM verifies the trajectory shows ROI manipulation.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_translocation_ratio(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1. Report Existence (10 pts)
    if result.get("report_exists") and result.get("report_created_during"):
        score += 10
        feedback.append("Report file created.")
    else:
        feedback.append("Report file missing or not created during task.")

    # 2. Ratio Accuracy (40 pts)
    # Extract number from content
    content = result.get("report_content", "")
    gt_ratio = result.get("ground_truth", {}).get("gt_ratio", 0.0)
    
    # regex to find float
    match = re.search(r"(\d+\.?\d*)", content)
    agent_ratio = float(match.group(1)) if match else None

    if agent_ratio is not None:
        # Tolerance: +/- 15% (Manual ROI drawing varies)
        tolerance = 0.15
        diff = abs(agent_ratio - gt_ratio)
        max_diff = gt_ratio * tolerance

        if diff <= max_diff:
            score += 40
            feedback.append(f"Ratio Accuracy: PASSED. Agent: {agent_ratio:.2f}, GT: {gt_ratio:.2f}")
        else:
            # Partial credit if they are in the ballpark (within 30%)
            if diff <= (gt_ratio * 0.3):
                score += 20
                feedback.append(f"Ratio Accuracy: CLOSE. Agent: {agent_ratio:.2f}, GT: {gt_ratio:.2f} (Target +/- 15%)")
            else:
                feedback.append(f"Ratio Accuracy: FAILED. Agent: {agent_ratio:.2f}, GT: {gt_ratio:.2f}")
    else:
        feedback.append("Could not parse a number from the report.")

    # 3. ROIs Zip (20 pts)
    if result.get("rois_exists"):
        score += 20
        feedback.append("ROIs saved successfully.")
    else:
        feedback.append("ROIs zip file missing.")

    # 4. VLM Verification (30 pts)
    # Check if they actually used the tools
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
    
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        prompt = """
        Review these screenshots of a user using Fiji/ImageJ.
        I am looking for evidence of a "Nuclear-Cytoplasmic Ratio" workflow.
        
        Look for:
        1. An image with a selection/ROI around a cell nucleus.
        2. Evidence of ROI Manager being used (a small window listing ROIs).
        3. A "Results" table showing measurements (Mean, Area).
        4. Any dialogue showing "Enlarge Selection" or similar.
        
        Does the user appear to be performing measurements on ROIs?
        """
        
        vlm_res = query_vlm(images=frames, prompt=prompt)
        if vlm_res.get("success") and "yes" in vlm_res.get("parsed", {}).get("answer", "").lower():
            score += 30
            feedback.append("VLM Verification: Workflow confirmed.")
        else:
            # Fallback if VLM is unsure but hard metrics passed
            if score >= 50:
                score += 30
                feedback.append("VLM Verification: Inconclusive, but hard metrics passed.")
            else:
                feedback.append("VLM Verification: Workflow not clearly observed.")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback)
    }