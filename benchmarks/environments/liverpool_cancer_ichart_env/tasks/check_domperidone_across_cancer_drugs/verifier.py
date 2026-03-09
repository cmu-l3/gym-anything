#!/usr/bin/env python3
"""
Verifier for check_domperidone_across_cancer_drugs task.

This verifier uses a hybrid approach:
1. Programmatic: Checks the text report for expected keywords (drug names, colors).
2. VLM: Analyzes trajectory screenshots to verify the agent actually visited
   the interaction screens for all three drugs.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_domperidone_check(traj, env_info, task_info):
    """
    Verify the agent checked Domperidone against Pazopanib, Panobinostat, and Vandetanib.
    """
    # 1. Setup and retrieve result file
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Infrastructure error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_drugs = metadata.get('cancer_drugs', ["Pazopanib", "Panobinostat", "Vandetanib"])
    
    # Copy JSON result from Android environment
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result JSON: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve task result from device."}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Programmatic Verification of Report Content (40 points)
    score = 0
    feedback_log = []
    
    report_exists = result_data.get("report_exists", False)
    report_content = result_data.get("report_content", "").lower()
    
    if report_exists and len(report_content) > 20:
        score += 10
        feedback_log.append("Report file created.")
        
        # Check for drug names
        drugs_found = 0
        for drug in expected_drugs:
            if drug.lower() in report_content:
                drugs_found += 1
        
        if drugs_found == 3:
            score += 15
            feedback_log.append("All 3 cancer drugs mentioned in report.")
        else:
            score += (drugs_found * 5)
            feedback_log.append(f"Found {drugs_found}/3 cancer drugs in report.")

        # Check for color keywords (Red, Amber, Yellow, Green, Gray/Grey)
        # We expect at least 3 color occurrences or distinct color mentions
        color_keywords = ["red", "amber", "orange", "yellow", "green", "grey", "gray", "do not", "caution"]
        found_colors = [c for c in color_keywords if c in report_content]
        
        if len(found_colors) >= 1:
            score += 10
            feedback_log.append("Interaction classifications found in report.")
        
        # Check for Domperidone mention
        if "domperidone" in report_content:
            score += 5
            feedback_log.append("Domperidone mentioned.")
    else:
        feedback_log.append("Report file missing or empty.")

    # 3. VLM Verification of Trajectory (60 points)
    # We need to confirm the agent actually looked at the interactions in the app
    
    frames = sample_trajectory_frames(traj, n=8)  # Sample 8 frames to catch the sequence
    
    vlm_prompt = f"""
    You are verifying an agent's workflow in the 'Liverpool Cancer iChart' Android app.
    The agent was supposed to check interactions for Domperidone with three specific cancer drugs:
    1. Pazopanib
    2. Panobinostat
    3. Vandetanib
    
    Look at the sequence of screenshots. 
    
    Question 1: Did the agent search for or view the 'Pazopanib' interaction page?
    Question 2: Did the agent search for or view the 'Panobinostat' interaction page?
    Question 3: Did the agent search for or view the 'Vandetanib' interaction page?
    Question 4: Did you see 'Domperidone' selected or listed as a co-medication in any frame?
    
    Return JSON:
    {{
        "visited_pazopanib": boolean,
        "visited_panobinostat": boolean,
        "visited_vandetanib": boolean,
        "checked_domperidone": boolean,
        "confidence": "low|medium|high"
    }}
    """
    
    vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
    vlm_data = vlm_result.get('parsed', {}) if vlm_result else {}
    
    vlm_score = 0
    if vlm_data.get('visited_pazopanib'): vlm_score += 15
    if vlm_data.get('visited_panobinostat'): vlm_score += 15
    if vlm_data.get('visited_vandetanib'): vlm_score += 15
    if vlm_data.get('checked_domperidone'): vlm_score += 15
    
    score += vlm_score
    
    # Detailed VLM feedback
    if vlm_score < 60:
        missing = []
        if not vlm_data.get('visited_pazopanib'): missing.append("Pazopanib")
        if not vlm_data.get('visited_panobinostat'): missing.append("Panobinostat")
        if not vlm_data.get('visited_vandetanib'): missing.append("Vandetanib")
        if not vlm_data.get('checked_domperidone'): missing.append("Domperidone Selection")
        feedback_log.append(f"VLM verification failed to see: {', '.join(missing)}")
    else:
        feedback_log.append("VLM verified all drugs were visited.")

    # Final Evaluation
    passed = score >= 60 and report_exists and vlm_data.get('checked_domperidone')
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_log)
    }