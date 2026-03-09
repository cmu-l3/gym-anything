#!/usr/bin/env python3
"""
Verifier for Compare Macrolide Antibiotics with Lorlatinib task.

Verification Strategy:
1. File Verification (40 pts):
   - Report file exists and was created during the task
   - Contains "Clarithromycin" and "Erythromycin"
   - Contains a comparison statement

2. Content Accuracy (30 pts):
   - Correctly identifies traffic light colors (Red/Amber/Yellow/Green)
   - Note: In Liverpool iChart, Clarithromycin + Lorlatinib is usually RED (Do Not Coadminister)
   - Erythromycin + Lorlatinib is usually AMBER (Potential Interaction)
   - Comparison should reflect this difference.

3. VLM Trajectory Verification (30 pts):
   - Verifies the agent actually navigated the app (Lorlatinib page -> Co-meds)
   - Prevents "lucky guess" gaming.
"""

import json
import tempfile
import os
import logging
import re
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_macrolide_comparison(traj, env_info, task_info):
    """
    Verify the agent correctly compared Clarithromycin and Erythromycin interactions with Lorlatinib.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Metadata / Ground Truth
    metadata = task_info.get('metadata', {})
    # Note: "Amber" is often used in the app, but users might write "Orange"
    expected_clarithromycin = ["red", "do not coadminister"]
    expected_erythromycin = ["amber", "orange", "yellow", "potential interaction"] 
    
    score = 0
    feedback_parts = []
    
    # ================================================================
    # 1. RETRIEVE AND PARSE RESULT FILE
    # ================================================================
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    content = result_data.get('file_content', '').lower()
    file_exists = result_data.get('file_exists', False)
    created_fresh = result_data.get('created_during_task', False)

    # ================================================================
    # 2. SCORING: FILE EXISTENCE (20 pts)
    # ================================================================
    if file_exists and created_fresh:
        score += 20
        feedback_parts.append("Report file created successfully.")
    elif file_exists:
        score += 5
        feedback_parts.append("Report file exists but timestamp suggests stale file.")
    else:
        feedback_parts.append("Report file NOT found.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # ================================================================
    # 3. SCORING: CONTENT ACCURACY (40 pts)
    # ================================================================
    
    # Check for drug names
    has_clarithro = "clarithromycin" in content
    has_erythro = "erythromycin" in content
    
    if has_clarithro and has_erythro:
        score += 10
        feedback_parts.append("Both drugs mentioned.")
    else:
        feedback_parts.append("Missing one or both drug names.")

    # Check for colors/interaction status
    # Heuristic: split content by lines or approximate proximity
    
    clarithro_correct = any(c in content for c in expected_clarithromycin)
    erythro_correct = any(c in content for c in expected_erythromycin)
    
    # Logic: Look for specific associations if possible, but simple keyword presence is a decent proxy 
    # if we enforce "Comparison" structure.
    
    if clarithro_correct:
        score += 10
        feedback_parts.append("Clarithromycin interaction identified correctly (Red/Severe).")
    
    if erythro_correct:
        score += 10
        feedback_parts.append("Erythromycin interaction identified correctly (Amber/Orange).")

    # Check comparison logic
    # If one is Red and one is Amber -> They are "Different"
    if "different" in content or "safer" in content or "less severe" in content:
        score += 10
        feedback_parts.append("Comparison statement present.")
    elif "same" in content:
        feedback_parts.append("Incorrect comparison (claimed same).")
    else:
        feedback_parts.append("No comparison statement found.")

    # ================================================================
    # 4. SCORING: VLM TRAJECTORY VERIFICATION (40 pts)
    # ================================================================
    # We need to ensure they didn't just guess the file content.
    # We look for evidence of the app being used.
    
    frames = sample_trajectory_frames(traj, n=6)
    
    vlm_prompt = """
    Analyze these screenshots from an Android app (Liverpool Cancer iChart).
    
    I need to verify if the user performed a drug interaction check.
    Look for:
    1. A list of cancer drugs (specifically 'Lorlatinib').
    2. A list of co-medications or categories (specifically 'Antibiotics' or 'Anti-infectives').
    3. Traffic light results (Red/Amber/Green banners).
    
    Did the user navigate to check interactions for Lorlatinib?
    Answer strictly with JSON: {"lorlatinib_seen": boolean, "antibiotics_checked": boolean, "results_seen": boolean}
    """
    
    vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
    
    if vlm_result and vlm_result.get('success'):
        parsed = vlm_result.get('parsed', {})
        
        if parsed.get('lorlatinib_seen', False):
            score += 15
            feedback_parts.append("VLM confirmed navigation to Lorlatinib.")
            
        if parsed.get('results_seen', False) or parsed.get('antibiotics_checked', False):
            score += 25
            feedback_parts.append("VLM confirmed interaction results were viewed.")
    else:
        # Fallback if VLM fails: give partial credit if file is perfect, 
        # but penalize for lack of visual proof if file is weak.
        feedback_parts.append("VLM verification inconclusive.")
        if score >= 50: 
            score += 20 # Benefit of doubt if text result is strong

    # ================================================================
    # FINAL VERDICT
    # ================================================================
    passed = score >= 60 and has_clarithro and has_erythro
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }