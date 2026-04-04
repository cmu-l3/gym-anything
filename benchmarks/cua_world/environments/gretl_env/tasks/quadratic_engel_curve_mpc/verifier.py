#!/usr/bin/env python3
"""
Verifier for quadratic_engel_curve_mpc task.

Checks:
1. Output file exists and was created during the task.
2. Output file contains the correct MPC value (approx 12.60).
3. VLM verification of the workflow (variable creation, regression).
"""

import json
import os
import tempfile
import logging
import re
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_quadratic_engel_curve_mpc(traj, env_info, task_info):
    """
    Verify the quadratic Engel curve estimation and MPC calculation.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_mpc = metadata.get('expected_mpc_value', 12.597)
    tolerance = metadata.get('tolerance', 0.1)

    score = 0
    feedback_parts = []
    
    # ================================================================
    # 1. Retrieve Task Result JSON
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
            
    # ================================================================
    # 2. Check Output File Existence & Timestamp (20 pts)
    # ================================================================
    output_exists = result.get('output_exists', False)
    file_created = result.get('file_created_during_task', False)
    
    if output_exists:
        if file_created:
            score += 20
            feedback_parts.append("Output file created successfully.")
        else:
            score += 5
            feedback_parts.append("Output file exists but was not created during task (stale?).")
    else:
        feedback_parts.append("Output file not found.")

    # ================================================================
    # 3. Verify MPC Value (40 pts)
    # ================================================================
    value_correct = False
    if output_exists:
        try:
            # Clean content: remove non-numeric chars except dot/minus
            content = result.get('output_content', '').strip()
            # Extract first float found
            matches = re.findall(r"[-+]?\d*\.\d+|\d+", content)
            if matches:
                mpc_val = float(matches[0])
                error = abs(mpc_val - expected_mpc)
                if error <= tolerance:
                    score += 40
                    value_correct = True
                    feedback_parts.append(f"MPC value {mpc_val} is correct (expected ~{expected_mpc}).")
                elif error <= tolerance * 5: # Partial credit for being close
                    score += 20
                    feedback_parts.append(f"MPC value {mpc_val} is close but outside tolerance (expected ~{expected_mpc}).")
                else:
                    feedback_parts.append(f"MPC value {mpc_val} is incorrect (expected ~{expected_mpc}).")
            else:
                feedback_parts.append("Could not parse numeric value from output file.")
        except Exception as e:
            feedback_parts.append(f"Error parsing output file: {e}")

    # ================================================================
    # 4. VLM Verification of Workflow (40 pts)
    # ================================================================
    # We look for evidence of:
    # - Variable creation (income_sq)
    # - Regression output (OLS window)
    
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    images = frames + ([final_screen] if final_screen else [])
    
    if images:
        prompt = """
        Analyze these screenshots of a Gretl statistics session.
        I am looking for evidence of the following workflow:
        1. A variable named 'income_sq' (or similar squared term) was created/added to the variable list.
        2. An OLS regression was run (results window visible).
        3. The regression included a squared term (e.g. 'income_sq', 'sq_income').
        
        Respond in JSON:
        {
            "variable_created": true/false,
            "regression_run": true/false,
            "squared_term_used": true/false,
            "confidence": "high/medium/low"
        }
        """
        
        try:
            vlm_res = query_vlm(images=images, prompt=prompt)
            parsed = vlm_res.get('parsed', {})
            
            vlm_score = 0
            if parsed.get('variable_created'): vlm_score += 15
            if parsed.get('regression_run'): vlm_score += 15
            if parsed.get('squared_term_used'): vlm_score += 10
            
            score += vlm_score
            feedback_parts.append(f"VLM verification score: {vlm_score}/40.")
            
        except Exception as e:
            logger.warning(f"VLM query failed: {e}")
            feedback_parts.append("VLM verification failed (framework error).")
            # Fallback: if value was exactly correct, give full points
            if value_correct:
                score += 40
                feedback_parts.append("Awarding VLM points based on correct result.")
    else:
        feedback_parts.append("No screenshots available for VLM verification.")

    # ================================================================
    # Final Scoring
    # ================================================================
    passed = (score >= 70) and value_correct
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }