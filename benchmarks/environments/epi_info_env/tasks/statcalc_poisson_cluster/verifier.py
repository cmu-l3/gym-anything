#!/usr/bin/env python3
"""
Verifier for StatCalc Poisson Cluster Evaluation task.

Verifies:
1. Output file existence and timestamp (Anti-gaming)
2. Content accuracy: Expected (3.6), Observed (8), Probability range
3. VLM Trajectory: Confirms StatCalc UI was accessed and used
"""

import json
import os
import tempfile
import re
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_statcalc_poisson_cluster(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy function missing"}

    metadata = task_info.get('metadata', {})
    expected_prob_min = metadata.get('expected_prob_min', 0.020)
    expected_prob_max = metadata.get('expected_prob_max', 0.040)
    
    score = 0
    feedback = []
    
    # =========================================================
    # 1. Retrieve and Check Output File (40 points)
    # =========================================================
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\workspace\\task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve results: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    content = result_data.get('output_content_preview', '')
    
    if not result_data.get('output_exists'):
        return {"passed": False, "score": 0, "feedback": "Output file not found"}
    
    score += 10 # File exists
    
    if result_data.get('file_created_during_task'):
        score += 10 # Created during task
    else:
        feedback.append("File timestamp indicates it was not created during this session")
        
    # Check Content
    content_lower = content.lower()
    
    # Check Inputs (10 pts)
    if "3.6" in content and "8" in content:
        score += 10
    else:
        feedback.append("File missing correct input values (Observed: 8, Expected: 3.6)")

    # Check Probability (10 pts)
    # Look for patterns like 0.0267, 0.026, 0.027, 2.67%
    prob_found = False
    # Regex for float numbers
    floats = re.findall(r"0\.\d+|[1-9]\.\d+", content)
    for f_str in floats:
        try:
            val = float(f_str)
            if expected_prob_min <= val <= expected_prob_max:
                prob_found = True
                break
        except:
            pass
            
    if prob_found:
        score += 10
    else:
        feedback.append(f"Probability value not found in expected range [{expected_prob_min}, {expected_prob_max}]")

    # =========================================================
    # 2. VLM Verification (60 points)
    # =========================================================
    frames = sample_trajectory_frames(traj, n=4)
    if not frames:
        feedback.append("No trajectory frames available for verification")
    else:
        prompt = """
        Analyze these screenshots of a user using Epi Info 7 StatCalc.
        I need to verify they performed a Poisson probability calculation.
        
        Look for:
        1. The 'StatCalc' window (distinct from main menu).
        2. A section or tab labeled 'Poisson' or 'Probability'.
        3. Input fields showing '8' (Observed) and '3.6' (Expected).
        4. A result displayed (likely ~0.0267).
        
        Did the user correctly access the Poisson calculator and enter the values?
        Respond with JSON: {"success": true/false, "confidence": 0-100, "details": "string"}
        """
        
        vlm_res = query_vlm(images=frames, prompt=prompt)
        parsed = vlm_res.get('parsed', {})
        
        if parsed.get('success', False):
            score += 60
        else:
            # Partial credit if they at least opened StatCalc
            if "StatCalc" in str(parsed.get('details', '')):
                score += 20
                feedback.append("Opened StatCalc but inputs/results not clearly visible")
            else:
                feedback.append("VLM could not verify StatCalc usage")

    # Conclusion Logic Check
    # If they wrote "significant" and the prob was low, that's good.
    if "not statistically significant" not in content_lower and "statistically significant" in content_lower:
        # Bonus/Tie-breaker check, implicit in score
        pass

    passed = score >= 80
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback) if feedback else "Task completed successfully"
    }