#!/usr/bin/env python3
"""
Verifier for Assess Migraine Medication Safety task.

Checks:
1. Report file existence and validity.
2. Correct traffic light colors identified for 3 interactions.
3. Correct identification of the safest option.
4. VLM verification of trajectory (app navigation).
"""

import json
import tempfile
import os
import logging
import re
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_migraine_safety(traj, env_info, task_info):
    """
    Verify the migraine safety assessment task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Metadata / Expectations
    metadata = task_info.get('metadata', {})
    expected_colors = metadata.get('expected_colors', {
        "Sumatriptan": ["red", "orange"],
        "Ibuprofen": ["yellow", "orange"],
        "Paracetamol": ["green", "grey"]
    })
    expected_safest = metadata.get('safest_option', "Paracetamol")

    score = 0
    max_score = 100
    feedback_parts = []
    
    # ------------------------------------------------------------------
    # 1. File & Content Verification (Programmatic) - 60 Points
    # ------------------------------------------------------------------
    
    # Retrieve files
    report_content = ""
    file_exists = False
    
    with tempfile.TemporaryDirectory() as temp_dir:
        local_report = os.path.join(temp_dir, "report.txt")
        local_json = os.path.join(temp_dir, "result.json")
        
        try:
            # Get JSON metadata
            copy_from_env("/sdcard/task_result.json", local_json)
            with open(local_json, 'r') as f:
                result_meta = json.load(f)
                
            # Get Report File
            if result_meta.get("file_exists", False):
                copy_from_env("/sdcard/migraine_safety_report.txt", local_report)
                with open(local_report, 'r', encoding='utf-8', errors='ignore') as f:
                    report_content = f.read()
                file_exists = True
                score += 10
                feedback_parts.append("Report file created.")
            else:
                feedback_parts.append("Report file NOT found.")
                
        except Exception as e:
            logger.error(f"Error copying/reading files: {e}")
            feedback_parts.append(f"Error retrieving task output: {str(e)}")

    # Parse Content if exists
    if file_exists:
        content_lower = report_content.lower()
        
        # Helper to find color for drug
        def check_drug_color(drug_name, valid_colors):
            # Regex to find line like "Procarbazine + Sumatriptan: Red"
            pattern = rf"{drug_name}.*?:\s*([a-z]+)"
            match = re.search(pattern, content_lower, re.IGNORECASE)
            if match:
                found_color = match.group(1).strip()
                if found_color in valid_colors:
                    return True, found_color
                return False, found_color
            return False, "not found"

        # Check Sumatriptan (Expected Red/Orange)
        passed, val = check_drug_color("sumatriptan", expected_colors["Sumatriptan"])
        if passed:
            score += 15
            feedback_parts.append(f"Sumatriptan identified correctly ({val}).")
        else:
            feedback_parts.append(f"Sumatriptan incorrect (found: {val}, expected: {expected_colors['Sumatriptan']}).")

        # Check Ibuprofen (Expected Yellow/Orange)
        passed, val = check_drug_color("ibuprofen", expected_colors["Ibuprofen"])
        if passed:
            score += 15
            feedback_parts.append(f"Ibuprofen identified correctly ({val}).")
        else:
            feedback_parts.append(f"Ibuprofen incorrect (found: {val}, expected: {expected_colors['Ibuprofen']}).")

        # Check Paracetamol (Expected Green/Grey)
        passed, val = check_drug_color("paracetamol", expected_colors["Paracetamol"])
        if passed:
            score += 10
            feedback_parts.append(f"Paracetamol identified correctly ({val}).")
        else:
            feedback_parts.append(f"Paracetamol incorrect (found: {val}, expected: {expected_colors['Paracetamol']}).")

        # Check Safest Option
        safest_pattern = r"safest.*?:.*?(paracetamol)"
        if re.search(safest_pattern, content_lower, re.IGNORECASE):
            score += 10
            feedback_parts.append("Safest option (Paracetamol) correctly identified.")
        else:
            feedback_parts.append("Safest option NOT correctly identified.")

    # ------------------------------------------------------------------
    # 2. VLM Trajectory Verification (Visual) - 40 Points
    # ------------------------------------------------------------------
    
    # Sample frames to check workflow
    frames = sample_trajectory_frames(traj, n=5)
    
    vlm_prompt = """
    You are verifying an agent's interaction with the 'Liverpool Cancer iChart' app.
    The goal was to check interactions for Procarbazine with Sumatriptan, Ibuprofen, and Paracetamol.
    
    Look at the sequence of screenshots. Answer the following:
    1. Is the Liverpool Cancer iChart app visible?
    2. Do you see 'Procarbazine' selected or searched?
    3. Do you see any traffic light interaction results (Red, Yellow, Green/Grey banners)?
    4. Did the agent navigate to check specific drugs (Sumatriptan, Ibuprofen, Paracetamol)?
    
    Return JSON:
    {
        "app_visible": boolean,
        "procarbazine_seen": boolean,
        "interaction_results_seen": boolean,
        "multiple_checks_seen": boolean
    }
    """
    
    try:
        vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
        parsed = vlm_result.get("parsed", {})
        
        vlm_score = 0
        if parsed.get("app_visible"): vlm_score += 10
        if parsed.get("procarbazine_seen"): vlm_score += 10
        if parsed.get("interaction_results_seen"): vlm_score += 10
        if parsed.get("multiple_checks_seen"): vlm_score += 10
        
        score += vlm_score
        feedback_parts.append(f"Visual verification score: {vlm_score}/40")
        
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        # Fallback: if file content is perfect, give partial VLM credit (benefit of doubt)
        if score >= 60:
            score += 20
            feedback_parts.append("VLM failed, added partial fallback credit.")

    # ------------------------------------------------------------------
    # Final Decision
    # ------------------------------------------------------------------
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }