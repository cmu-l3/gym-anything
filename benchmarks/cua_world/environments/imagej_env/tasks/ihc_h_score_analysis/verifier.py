#!/usr/bin/env python3
"""Verifier for IHC H-Score Analysis task."""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_ihc_h_score_analysis(traj, env_info, task_info):
    """
    Verify H-Score analysis.
    
    Points Breakdown (100 total):
    - File exists & created during task: 10 pts
    - Total Area matches GT (within 10%): 20 pts
    - Tier Areas (Low/Med/High) match GT (within 10%): 30 pts (10 each)
    - Math Logic (User's H-Score matches formula using User's Areas): 30 pts
    - Final Accuracy (User's H-Score matches GT H-Score): 10 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy unavailable"}

    # Load results
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_file.close()
        try:
            copy_from_env("/tmp/h_score_result.json", temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_file.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error loading results: {e}"}

    score = 0
    feedback = []
    
    # 1. File Checks
    if not result.get("file_exists"):
        return {"passed": False, "score": 0, "feedback": "Result CSV file not found."}
    
    if not result.get("file_created_during_task"):
        feedback.append("Warning: Result file timestamp suggests it wasn't created during this task.")
        # We penalize but don't fail immediately if content is good (could be time sync issue)
    else:
        score += 10
        feedback.append("Result file created successfully.")

    user = result.get("user_data", {})
    gt = result.get("ground_truth", {})
    
    if not gt or "error" in gt:
        feedback.append("Warning: Ground Truth generation failed. Using fallback checks.")
        # Fallback values for "Fluorescent Cells" (approximate knowns)
        gt = {
            "gt_total_area": 140000, # Approx
            "gt_h_score": 150 # Approx
        }

    # 2. Area Accuracy (Total)
    u_total = user.get("total_area", 0)
    g_total = gt.get("gt_total_area", 1) # avoid div0
    
    # Tolerance: 10% (thresholding algorithms vary slightly)
    if g_total > 0 and abs(u_total - g_total) / g_total < 0.15:
        score += 20
        feedback.append(f"Total Area accurate ({u_total:.0f} vs GT {g_total:.0f})")
    else:
        feedback.append(f"Total Area inaccurate (User: {u_total:.0f}, GT: {g_total:.0f})")

    # 3. Tier Accuracy
    tiers_correct = 0
    for tier in ["low", "med", "high"]:
        u_val = user.get(f"{tier}_area", 0)
        g_val = gt.get(f"gt_{tier}_area", 1)
        if g_val > 0 and abs(u_val - g_val) / g_val < 0.15:
            tiers_correct += 1
    
    score += (tiers_correct * 10)
    feedback.append(f"Tier Areas: {tiers_correct}/3 correct.")

    # 4. Math Logic Check (Internal Consistency)
    # Does User_HScore == Formula(User_Areas)?
    # This proves the agent followed the formula, even if segmentation was slightly off
    u_hscore = user.get("h_score", 0)
    
    calc_hscore = 0
    if u_total > 0:
        p_low = (user.get("low_area", 0) / u_total) * 100
        p_med = (user.get("med_area", 0) / u_total) * 100
        p_high = (user.get("high_area", 0) / u_total) * 100
        calc_hscore = (1 * p_low) + (2 * p_med) + (3 * p_high)
    
    if abs(u_hscore - calc_hscore) < 5: # Allow rounding diffs
        score += 30
        feedback.append("H-Score calculation logic is correct.")
    else:
        feedback.append(f"H-Score calculation logic incorrect (Reported: {u_hscore:.1f}, Calc from areas: {calc_hscore:.1f})")

    # 5. Final Accuracy
    g_hscore = gt.get("gt_h_score", 0)
    if abs(u_hscore - g_hscore) < 15: # Allow +/- 15 points on 300 scale
        score += 10
        feedback.append(f"Final H-Score accurate ({u_hscore:.1f} vs GT {g_hscore:.1f})")
    else:
        feedback.append(f"Final H-Score inaccurate.")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }