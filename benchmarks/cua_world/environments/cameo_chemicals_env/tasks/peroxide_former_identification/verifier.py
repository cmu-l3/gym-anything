#!/usr/bin/env python3
"""
Verifier for peroxide_former_identification task.

Verification Strategy:
1. Programmatic: Parse the output text file for correct classifications of 8 chemicals.
2. VLM: Check trajectory frames to ensure the agent actually used the website (anti-gaming).
"""

import json
import os
import tempfile
import logging
import re
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_peroxide_audit(traj, env_info, task_info):
    """
    Verify the peroxide audit report.
    """
    # 1. Setup and helper functions
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    metadata = task_info.get('metadata', {})
    ground_truth = metadata.get('ground_truth', {})
    output_path = metadata.get('output_path', '/home/ga/Desktop/peroxide_audit_report.txt')

    score = 0
    max_score = 100
    feedback_parts = []
    
    # 2. Retrieve Task Metadata JSON
    task_result = {}
    with tempfile.NamedTemporaryFile(suffix='.json') as tmp_json:
        try:
            copy_from_env("/tmp/task_result.json", tmp_json.name)
            # Re-open to read because copy_from_env might overwrite
            with open(tmp_json.name, 'r') as f:
                task_result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task status: {str(e)}"}

    # 3. Check Basic File Existence & Anti-Gaming (15 pts)
    if not task_result.get('file_exists', False):
        return {"passed": False, "score": 0, "feedback": "Report file not found at ~/Desktop/peroxide_audit_report.txt"}

    if not task_result.get('file_created_during_task', False):
        return {"passed": False, "score": 0, "feedback": "Report file was not created/modified during the task window (anti-gaming failure)"}

    score += 15
    feedback_parts.append("File created successfully (+15)")

    # 4. specific Chemical Verification (65 pts)
    # 8 chemicals total. 8 pts per correct classification + 1 bonus for perfect score = 65.
    
    # Retrieve the actual report content
    report_content = ""
    with tempfile.NamedTemporaryFile(suffix='.txt') as tmp_txt:
        try:
            copy_from_env(output_path, tmp_txt.name)
            with open(tmp_txt.name, 'r', errors='ignore') as f:
                report_content = f.read()
        except Exception as e:
            return {"passed": False, "score": score, "feedback": f"Failed to read report content: {str(e)}"}

    # Parse content
    report_lower = report_content.lower()
    
    chemicals_correct = 0
    chemicals_checked = 0
    
    for chem_name, expected_status in ground_truth.items():
        chem_name_lower = chem_name.lower()
        expected_lower = expected_status.lower()
        
        # We look for the chemical name and the status in the text
        # Simple heuristic: find the line with the chemical, check if it contains the status
        
        # Split into lines to associate status with specific chemical
        lines = report_lower.split('\n')
        found_chem = False
        correct_chem = False
        
        for line in lines:
            if chem_name_lower in line:
                found_chem = True
                if expected_lower in line:
                    correct_chem = True
                    break
                # Special check: if expected is "not a peroxide former", make sure "not" is present
                # if expected is "peroxide former", make sure "not" is ABSENT (unless it says "is a peroxide former")
                # The exact string match 'peroxide former' vs 'not a peroxide former' handles this safely 
                # because 'not a peroxide former' contains 'peroxide former'.
                
                # Let's trust the "expected_lower in line" logic if the agent followed format.
                # If agent wrote "Acetone: NOT A PEROXIDE FORMER", line contains "not a peroxide former". Correct.
                # If agent wrote "Ether: PEROXIDE FORMER", line contains "peroxide former". Correct.
                # If agent wrote "Acetone: PEROXIDE FORMER", it matches "peroxide former" but misses "not".
                
                if expected_lower == "not a peroxide former":
                    # handled by direct match
                    pass
                elif expected_lower == "peroxide former":
                    # Check if they said "not"
                    if "not a peroxide former" in line:
                        correct_chem = False # They said NOT, but it IS
                    elif "peroxide former" in line:
                        correct_chem = True
        
        chemicals_checked += 1
        if correct_chem:
            chemicals_correct += 1
            score += 8
        elif found_chem:
             feedback_parts.append(f"Wrong classification for {chem_name}")
        else:
             feedback_parts.append(f"Missing {chem_name}")

    if chemicals_correct == 8:
        score += 1 # Bonus for perfect report
        feedback_parts.append("All 8 chemicals classified correctly (+65)")
    else:
        feedback_parts.append(f"{chemicals_correct}/8 chemicals correct")

    # 5. VLM Verification (20 pts)
    # Did the agent actually use CAMEO Chemicals?
    
    frames = sample_trajectory_frames(traj, n=4)
    if not frames:
        feedback_parts.append("No trajectory frames available for VLM check")
    else:
        vlm_prompt = """
        Review these screenshots of a computer agent's activity.
        The task was to look up chemicals on the 'CAMEO Chemicals' website.
        
        1. Do you see the CAMEO Chemicals website (blue/white theme, NOAA logo)?
        2. Do you see a chemical datasheet or search results page?
        3. Is there evidence of browsing different chemicals?
        
        Answer JSON: {"cameo_visible": bool, "datasheets_viewed": bool, "confidence": float}
        """
        
        try:
            vlm_res = query_vlm(images=frames, prompt=vlm_prompt)
            parsed = vlm_res.get('parsed', {})
            
            if parsed.get('cameo_visible', False) or parsed.get('datasheets_viewed', False):
                score += 20
                feedback_parts.append("VLM confirmed CAMEO usage (+20)")
            else:
                feedback_parts.append("VLM did not observe CAMEO Chemicals website usage")
                
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
            # Do not penalize for API errors, but don't award points
            feedback_parts.append("VLM check skipped due to error")

    # Final scoring logic
    # Pass if >= 60 points AND at least 4 chemicals were correct (prevents passing empty file with just VLM points)
    passed = (score >= 60) and (chemicals_correct >= 4)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }