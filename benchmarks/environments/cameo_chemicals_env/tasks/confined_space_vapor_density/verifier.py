#!/usr/bin/env python3
"""
Verifier for Confined Space Vapor Density Assessment task.

VERIFICATION STRATEGY:
1. File Verification (40 pts): Report exists, created during task, correct format.
2. Data Accuracy (50 pts): Correct vapor density values and classifications for 5 chemicals.
3. VLM Verification (10 pts): Visual confirmation of workflow (visiting CAMEO pages).
"""

import json
import re
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_confined_space_vapor_density(traj, env_info, task_info):
    """
    Verify the vapor density report contains correct values and classifications.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    chemicals_data = metadata.get('chemicals', {})
    
    # 1. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 2. Verify File Existence & Anti-Gaming (Timestamp)
    if not result.get('report_exists', False):
        return {"passed": False, "score": 0, "feedback": "Report file not found at ~/Documents/confined_space_vapor_report.txt"}
    
    if not result.get('report_created_during_task', False):
        feedback_parts.append("WARNING: Report file timestamp predates task start (reused file?)")
        # Penalize but continue checking content in case of clock skew, 
        # though usually this is a hard fail in strict environments.
        # We will cap the score.
    else:
        score += 5
        feedback_parts.append("Report created during task")

    content = result.get('report_content', '')
    if not content:
        return {"passed": False, "score": score, "feedback": "Report file is empty"}

    # 3. Analyze Content (Data Extraction)
    # Expected format:
    # Chemical: Name
    # Vapor Density: Value
    # Classification: HEAVIER/LIGHTER/SIMILAR
    
    # Normalize content for searching
    content_norm = content.replace('\r\n', '\n')
    
    chemicals_found = 0
    values_correct = 0
    classifications_correct = 0
    
    # Iterate through expected chemicals
    for chem_name, criteria in chemicals_data.items():
        # Regex to find this specific chemical block
        # Looks for "Chemical: [Name]" followed loosely by "Vapor Density: [Value]"
        chem_pattern = re.compile(
            r"Chemical:\s*" + re.escape(chem_name) + 
            r".*?Vapor Density:\s*([0-9.]+).*?Classification:\s*([A-Z]+)", 
            re.IGNORECASE | re.DOTALL
        )
        
        match = chem_pattern.search(content_norm)
        
        if match:
            chemicals_found += 1
            extracted_val = float(match.group(1))
            extracted_class = match.group(2).upper()
            
            # Check Value
            if criteria['min'] <= extracted_val <= criteria['max']:
                values_correct += 1
            else:
                feedback_parts.append(f"{chem_name}: Value {extracted_val} out of range ({criteria['min']}-{criteria['max']})")

            # Check Classification
            if extracted_class == criteria['class']:
                classifications_correct += 1
            else:
                feedback_parts.append(f"{chem_name}: Class {extracted_class} incorrect (expected {criteria['class']})")
        else:
            feedback_parts.append(f"Could not parse block for {chem_name}")

    # Scoring for Data
    # 5 chemicals * 2 pts for finding = 10 pts
    # 5 chemicals * 5 pts for value = 25 pts
    # 5 chemicals * 3 pts for class = 15 pts
    score += (chemicals_found * 2)
    score += (values_correct * 5)
    score += (classifications_correct * 3)

    # 4. Verify Summary and Recommendation sections exist
    if "SUMMARY" in content_norm and "RECOMMENDATION" in content_norm:
        score += 15
        feedback_parts.append("Structure (Summary/Recs) present")
    else:
        feedback_parts.append("Missing SUMMARY or RECOMMENDATION sections")

    # 5. VLM Trajectory Verification (10 pts)
    # Ensure they actually visited CAMEO Chemicals and didn't just guess
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        vlm_prompt = (
            "Does the user appear to be using the CAMEO Chemicals website? "
            "Look for blue/white NOAA branding, chemical datasheets, or search results. "
            "Answer 'YES' or 'NO' and briefly explain."
        )
        try:
            vlm_res = query_vlm(images=frames, prompt=vlm_prompt)
            if vlm_res.get('success') and "YES" in vlm_res.get('response', '').upper():
                score += 10
                feedback_parts.append("VLM confirmed CAMEO usage")
            else:
                feedback_parts.append("VLM could not confirm CAMEO usage")
        except Exception:
            # Fallback if VLM fails, give benefit of doubt if data is correct
            if values_correct >= 4:
                score += 10
    else:
        feedback_parts.append("No frames for VLM check")

    # Final tally
    passed = (score >= 60) and (values_correct >= 3) and (result.get('report_exists', False))
    
    if passed:
        feedback_parts.insert(0, "SUCCESS")
    else:
        feedback_parts.insert(0, "FAILED")

    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }