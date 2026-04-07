#!/usr/bin/env python3
"""Verifier for evaluate_pv_lcoe_risk_monte_carlo task.

Performs robust multi-criteria evaluation including:
1. File verification (timestamp and structure)
2. Statistical validation (P50/P90 math checks)
3. Script structural analysis (prevent hardcoding)
4. Trajectory verification (VLM check on agent actions)
"""

import json
import tempfile
import os
import logging
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def _analyze_python_script(copy_from_env) -> Dict[str, bool]:
    """Copy and analyze the agent's python script to ensure it's not a hardcoded fake."""
    script_path = "/home/ga/Documents/SAM_Projects/monte_carlo_lcoe.py"
    temp = tempfile.NamedTemporaryFile(delete=False, suffix='.py')
    
    analysis = {
        'script_readable': False,
        'has_numpy': False,
        'has_pysam': False,
        'has_loop': False,
        'has_seed': False,
        'has_percentile': False,
        'has_json_dump': False
    }
    
    try:
        copy_from_env(script_path, temp.name)
        with open(temp.name, 'r') as f:
            code = f.read()
            
        analysis['script_readable'] = True
        
        # Look for essential structural components
        code_lower = code.lower()
        if 'import numpy' in code_lower or 'from numpy' in code_lower:
            analysis['has_numpy'] = True
            
        if 'import pysam' in code_lower or 'from pysam' in code_lower or 'pvwatts' in code_lower:
            analysis['has_pysam'] = True
            
        if 'for ' in code_lower or 'while ' in code_lower:
            analysis['has_loop'] = True
            
        if 'seed(42)' in code_lower or 'seed = 42' in code_lower:
            analysis['has_seed'] = True
            
        if 'percentile' in code_lower:
            analysis['has_percentile'] = True
            
        if 'json.dump' in code_lower or 'write' in code_lower:
            analysis['has_json_dump'] = True
            
    except Exception as e:
        logger.warning(f"Script analysis failed: {e}")
    finally:
        if os.path.exists(temp.name):
            os.unlink(temp.name)
            
    return analysis


def verify_evaluate_pv_lcoe_risk_monte_carlo(traj, env_info, task_info) -> Dict[str, Any]:
    """Verify the Monte Carlo risk analysis task.

    Scoring (100 pts total):
    - Python script exists & modified: 15 pts
    - JSON results exist & modified: 15 pts
    - Structural script checks (prevented hardcoding): 20 pts
    - Valid iteration count (500): 10 pts
    - P50 LCOE in mathematically correct range: 20 pts
    - P90 LCOE in mathematically correct range and > P50: 20 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata constraints
    metadata = task_info.get('metadata', {})
    expected_iterations = metadata.get('expected_iterations', 500)
    p50_min = metadata.get('expected_p50_min', 0.040)
    p50_max = metadata.get('expected_p50_max', 0.065)
    p90_min = metadata.get('expected_p90_min', 0.055)
    p90_max = metadata.get('expected_p90_max', 0.085)

    # Read the exported test results
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. File existence and anti-gaming modification checks (30 points)
    script_ok = result.get('script_exists') and result.get('script_modified')
    json_ok = result.get('json_exists') and result.get('json_modified')
    
    if script_ok:
        score += 15
        feedback_parts.append("Script created")
    else:
        feedback_parts.append("Script missing/old")
        
    if json_ok:
        score += 15
        feedback_parts.append("JSON created")
    else:
        feedback_parts.append("JSON missing/old")

    # 2. Structural Script Analysis (20 points)
    script_analysis = _analyze_python_script(copy_from_env)
    structural_score = 0
    
    if script_analysis['has_numpy']: structural_score += 4
    if script_analysis['has_pysam']: structural_score += 4
    if script_analysis['has_loop']: structural_score += 4
    if script_analysis['has_seed']: structural_score += 4
    if script_analysis['has_percentile']: structural_score += 4
    
    score += structural_score
    if structural_score == 20:
        feedback_parts.append("Script structure valid")
    else:
        feedback_parts.append(f"Script structure partial ({structural_score}/20)")
        
    # 3. Value Checks
    iterations = result.get('iterations', 0)
    p50_lcoe = result.get('p50_lcoe', 0.0)
    p90_lcoe = result.get('p90_lcoe', 0.0)
    
    # Check Iterations (10 points)
    if iterations == expected_iterations:
        score += 10
        feedback_parts.append("Iterations correct")
    elif iterations > 0:
        feedback_parts.append(f"Wrong iterations: {iterations}")
        
    # Check P50 LCOE (20 points)
    if p50_min <= p50_lcoe <= p50_max:
        score += 20
        feedback_parts.append(f"P50 LCOE valid (${p50_lcoe:.4f})")
    elif p50_lcoe > 0:
        feedback_parts.append(f"P50 LCOE out of bounds (${p50_lcoe:.4f})")
        
    # Check P90 LCOE (20 points)
    # P90 should be mathematically larger than P50 since it represents the 90th percentile of costs
    if p90_min <= p90_lcoe <= p90_max and p90_lcoe > p50_lcoe:
        score += 20
        feedback_parts.append(f"P90 LCOE valid (${p90_lcoe:.4f})")
    elif p90_lcoe > 0:
        if p90_lcoe <= p50_lcoe:
            feedback_parts.append("Logic error: P90 cost <= P50 cost")
        else:
            feedback_parts.append(f"P90 LCOE out of bounds (${p90_lcoe:.4f})")

    # VLM Trajectory Check (Optional reinforcement)
    vlm_feedback = ""
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames
            frames = sample_trajectory_frames(traj, n=4)
            if frames:
                vlm_prompt = (
                    "Look at these screenshots from an agent's trajectory. "
                    "Did the agent use a code editor or terminal to write a Python script involving numpy, PySAM, or a Monte Carlo simulation? "
                    "Reply ONLY with 'YES' or 'NO'."
                )
                vlm_resp = query_vlm(prompt=vlm_prompt, images=frames)
                if vlm_resp and vlm_resp.get("success"):
                    resp_text = vlm_resp.get("response", "").strip().upper()
                    if "YES" in resp_text:
                        vlm_feedback = "VLM verified coding activity"
                    else:
                        vlm_feedback = "VLM couldn't verify coding activity"
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")

    if vlm_feedback:
        feedback_parts.append(vlm_feedback)

    # Determine pass/fail
    # Must get at least 75 points and have created the actual files
    key_criteria_met = json_ok and script_ok and (p50_lcoe > 0)
    passed = score >= 75 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }