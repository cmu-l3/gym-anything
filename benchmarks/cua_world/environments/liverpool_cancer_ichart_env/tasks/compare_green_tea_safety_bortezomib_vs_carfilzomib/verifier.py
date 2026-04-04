#!/usr/bin/env python3
"""
Verifier for Compare Green Tea Safety with Bortezomib vs Carfilzomib task.

Criteria:
1. Report file must exist and be created during the task.
2. Report must identify Bortezomib as high risk (Red/Orange).
3. Report must identify Carfilzomib as low risk (Green/Yellow/Grey).
4. Report must conclude Carfilzomib is safer.
5. VLM must confirm the agent actually looked up both interactions.
"""

import json
import tempfile
import os
import logging
import re
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_green_tea_safety(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve JSON result from device
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Metadata expectations
    expected_colors_bort = ["red", "orange"]
    expected_colors_carf = ["green", "yellow", "grey", "gray"]
    
    # --- Check 1: File Existence (10 pts) ---
    if result.get("file_exists") and result.get("file_created_during_task"):
        score += 10
        feedback_parts.append("Report file created successfully.")
    else:
        return {"passed": False, "score": 0, "feedback": "Report file not created."}

    content = result.get("file_content", "").lower()
    
    # --- Check 2: Content Analysis (40 pts) ---
    
    # Check Bortezomib result
    bort_correct = "bortezomib" in content and any(c in content for c in expected_colors_bort)
    if bort_correct:
        score += 15
        feedback_parts.append("Correctly identified Bortezomib risk.")
    else:
        feedback_parts.append("Failed to correctly identify Bortezomib interaction/color.")

    # Check Carfilzomib result
    carf_correct = ("carfilzomib" in content or "kyprolis" in content) and any(c in content for c in expected_colors_carf)
    if carf_correct:
        score += 15
        feedback_parts.append("Correctly identified Carfilzomib safety.")
    else:
        feedback_parts.append("Failed to correctly identify Carfilzomib interaction/color.")

    # Check Conclusion (Carfilzomib is safer)
    conclusion_correct = False
    if "carfilzomib" in content and ("safer" in content or "better" in content or "preferred" in content):
        # Crude check: ensure it doesn't say "Bortezomib is safer"
        if "bortezomib is safer" not in content:
            conclusion_correct = True
            score += 10
            feedback_parts.append("Correctly concluded Carfilzomib is safer.")
    
    if not conclusion_correct:
        feedback_parts.append("Did not clearly identify Carfilzomib as the safer option.")

    # --- Check 3: VLM Trajectory Verification (50 pts) ---
    # We need to verify the agent actually looked up the drugs, not just hallucinated the report.
    
    frames = sample_trajectory_frames(traj, n=6)
    
    prompt = """
    You are verifying a drug interaction check task in an Android app.
    The user must check "Green Tea" against two drugs: "Bortezomib" and "Carfilzomib".
    
    Look at the sequence of screenshots.
    1. Do you see "Bortezomib" selected or searched?
    2. Do you see "Carfilzomib" (or Kyprolis) selected or searched?
    3. Do you see "Green tea" in the list or an interaction result for it?
    4. Do you see any traffic light interaction colors (Red/Orange/Green)?
    
    Return JSON:
    {
        "saw_bortezomib": boolean,
        "saw_carfilzomib": boolean,
        "saw_green_tea": boolean,
        "interaction_screens_visited": boolean
    }
    """
    
    vlm_res = query_vlm(images=frames, prompt=prompt)
    
    vlm_passed = False
    if vlm_res and vlm_res.get("success"):
        parsed = vlm_res.get("parsed", {})
        
        if parsed.get("saw_bortezomib"): score += 15
        if parsed.get("saw_carfilzomib"): score += 15
        if parsed.get("saw_green_tea"): score += 10
        if parsed.get("interaction_screens_visited"): score += 10
        
        vlm_passed = True
        feedback_parts.append(f"VLM Analysis: {json.dumps(parsed)}")
    else:
        feedback_parts.append("VLM verification failed to run.")

    # Final logic
    # Must have the file correct AND decent visual evidence
    passed = (score >= 70) and bort_correct and carf_correct

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }