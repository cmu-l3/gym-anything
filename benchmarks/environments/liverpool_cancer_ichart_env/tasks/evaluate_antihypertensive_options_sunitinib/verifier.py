#!/usr/bin/env python3
"""
Verifier for Sunitinib Antihypertensive Evaluation task.
"""

import json
import tempfile
import os
import logging
import re
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_antihypertensive_evaluation(traj, env_info, task_info):
    """
    Verify the agent correctly evaluated Diltiazem, Ramipril, and Bisoprolol
    interactions with Sunitinib.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_drugs = metadata.get('drugs_to_check', [])
    
    # Initialize scoring
    score = 0
    max_score = 100
    feedback_parts = []
    
    # ------------------------------------------------------------------
    # 1. Retrieve and Check Files (50 points)
    # ------------------------------------------------------------------
    
    # Get JSON result
    task_result = {}
    with tempfile.NamedTemporaryFile(suffix='.json') as f:
        try:
            copy_from_env("/sdcard/task_result.json", f.name)
            f.seek(0)
            task_result = json.load(f)
        except Exception as e:
            logger.error(f"Failed to load task result: {e}")

    # Get Report Content
    report_content = ""
    with tempfile.NamedTemporaryFile(suffix='.txt') as f:
        try:
            copy_from_env("/sdcard/sunitinib_bp_report.txt", f.name)
            f.seek(0)
            report_content = f.read().decode('utf-8', errors='ignore')
        except Exception as e:
            logger.error(f"Failed to load report: {e}")

    # Check existence and timing
    if task_result.get("output_exists") and task_result.get("file_created_during_task"):
        score += 10
        feedback_parts.append("Report file created successfully.")
    else:
        return {"passed": False, "score": 0, "feedback": "Report file not created or timestamp invalid."}

    # Verify Report Content (40 points)
    # We look for lines like "Diltiazem: [Color]"
    content_lower = report_content.lower()
    
    if "sunitinib" in content_lower:
        score += 5
    else:
        feedback_parts.append("Report missing cancer drug name (Sunitinib).")

    drugs_found = 0
    correct_colors = 0
    
    for drug in expected_drugs:
        name = drug['name'].lower()
        valid_colors = drug['valid_colors']
        
        # Regex to find "DrugName: Color" pattern
        # Matches: "Diltiazem: Orange" or "Diltiazem - Orange" etc.
        pattern = re.compile(rf"{name}.*?[:\-]\s*([a-z]+)", re.IGNORECASE)
        match = pattern.search(report_content)
        
        if match:
            drugs_found += 1
            reported_color = match.group(1).lower()
            if reported_color in valid_colors:
                correct_colors += 1
                score += 10  # 10 pts per correct drug
                feedback_parts.append(f"{drug['name']}: Correct ({reported_color}).")
            else:
                score += 5   # Partial credit for finding drug but wrong color
                feedback_parts.append(f"{drug['name']}: Wrong color '{reported_color}' (Expected: {valid_colors}).")
        else:
            feedback_parts.append(f"{drug['name']}: Not found in report.")

    if drugs_found < 3:
        feedback_parts.append("Not all required drugs were reported.")

    # ------------------------------------------------------------------
    # 2. VLM Trajectory Verification (50 points)
    # ------------------------------------------------------------------
    
    frames = sample_trajectory_frames(traj, n=6)
    final_screen = get_final_screenshot(traj)
    
    vlm_prompt = """
    Analyze these screenshots of a user using the 'Liverpool Cancer iChart' Android app.
    The user task was to check interactions for Sunitinib with Diltiazem, Ramipril, and Bisoprolol.
    
    Look for:
    1. Navigation to 'Sunitinib' in the cancer drug list.
    2. Navigation to co-medication categories (e.g., 'Calcium Channel Blockers', 'ACE Inhibitors', 'Beta Blockers', or 'Cardiovascular').
    3. Any visibility of the drugs 'Diltiazem', 'Ramipril', or 'Bisoprolol' in the lists.
    4. Any interaction result banners (Red/Orange/Yellow/Green colors).
    
    Did the user actually navigate the app to find this information?
    """
    
    vlm_result = query_vlm(
        images=frames + [final_screen],
        prompt=vlm_prompt
    )
    
    vlm_passed = False
    if vlm_result and vlm_result.get("success"):
        parsed = vlm_result.get("parsed", {})
        # Assuming VLM returns a boolean or we parse the text logic (using simple text check for now if parsed isn't structured)
        # In a real system, we'd ask for JSON output from VLM. Let's assume positive sentiment or specific keywords.
        # For this template, we give points if VLM output is generally positive or not error.
        # Ideally, use the JSON prompt pattern:
        pass
    
    # Refined VLM Check with JSON
    vlm_json_prompt = """
    Did the agent perform the interaction check workflow?
    Respond with JSON:
    {
        "sunitinib_seen": boolean,
        "co_meds_seen": boolean,
        "workflow_score": integer (0-10)
    }
    """
    vlm_json = query_vlm(images=frames, prompt=vlm_json_prompt).get('parsed', {})
    
    workflow_score = vlm_json.get('workflow_score', 0)
    if vlm_json.get('sunitinib_seen'):
        score += 10
    if vlm_json.get('co_meds_seen'):
        score += 10
    
    # Scale remaining points based on workflow quality
    score += (workflow_score / 10.0) * 15

    # ------------------------------------------------------------------
    # Final Result
    # ------------------------------------------------------------------
    passed = (score >= 80) and (drugs_found == 3)
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " ".join(feedback_parts)
    }