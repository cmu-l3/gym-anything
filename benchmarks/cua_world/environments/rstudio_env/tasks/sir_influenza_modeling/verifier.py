#!/usr/bin/env python3
"""
Verifier for SIR Influenza Modeling Task.

Criteria:
1. Output CSV exists and contains valid parameters (Beta, Gamma, R0).
2. Parameters are within scientifically plausible ranges for this dataset.
3. Plot exists and is a valid image.
4. Code uses the required libraries (deSolve).
5. VLM verification of the plot content (epidemic curve).
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_sir_modeling(traj, env_info, task_info):
    """
    Verify the SIR modeling task.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # Get metadata ranges
    meta = task_info.get('metadata', {})
    beta_range = meta.get('expected_beta_range', [1.4, 2.1])
    gamma_range = meta.get('expected_gamma_range', [0.3, 0.6])
    r0_range = meta.get('expected_R0_range', [2.5, 5.0])

    # 1. Parameter Verification (45 points)
    beta = float(result.get('beta', 0))
    gamma = float(result.get('gamma', 0))
    r0 = float(result.get('r0', 0))
    
    # Check Beta
    if beta_range[0] <= beta <= beta_range[1]:
        score += 15
        feedback.append(f"Beta ({beta:.4f}) is accurate")
    else:
        feedback.append(f"Beta ({beta:.4f}) out of expected range {beta_range}")

    # Check Gamma
    if gamma_range[0] <= gamma <= gamma_range[1]:
        score += 15
        feedback.append(f"Gamma ({gamma:.4f}) is accurate")
    else:
        feedback.append(f"Gamma ({gamma:.4f}) out of expected range {gamma_range}")

    # Check R0
    if r0_range[0] <= r0 <= r0_range[1]:
        score += 15
        feedback.append(f"R0 ({r0:.2f}) is accurate")
    else:
        feedback.append(f"R0 ({r0:.2f}) out of expected range {r0_range}")

    # 2. File Artifacts & Process (30 points)
    if result.get('csv_exists') and result.get('csv_created_during_task'):
        score += 10
        feedback.append("Parameters CSV created")
    
    if result.get('plot_exists') and result.get('plot_created_during_task'):
        # Check size
        if result.get('plot_size_bytes', 0) > 10000: # > 10KB
            score += 10
            feedback.append("Plot created and has content")
        else:
            feedback.append("Plot created but file is suspiciously small")
    
    if result.get('uses_desolve'):
        score += 10
        feedback.append("Code uses deSolve package")
    else:
        feedback.append("Code missing 'deSolve' keyword")

    # 3. VLM Verification (25 points)
    if query_vlm:
        # Get final screenshot from trajectory or directly use the plot if we could copy it
        # Here we use the final screenshot context
        from gym_anything.vlm import get_final_screenshot
        final_screen = get_final_screenshot(traj)
        
        prompt = """
        The user was fitting an SIR epidemic model to data. 
        Look for a plot showing:
        1. A scatter of data points (the outbreak data).
        2. A smooth curve line (the model fit).
        3. The curve should go up and then down (epidemic bell curve).
        
        Does the screen show such a plot?
        """
        
        vlm_res = query_vlm(prompt=prompt, image=final_screen)
        
        if vlm_res.get('success'):
            # Simple keyword check in reasoning if parsed not available, or assume success implies yes for binary questions
            # Ideally verify 'yes' in response
            if "yes" in vlm_res.get('response', '').lower() or vlm_res.get('parsed', {}).get('is_epidemic_plot'):
                score += 25
                feedback.append("VLM confirms valid epidemic plot visible")
            else:
                feedback.append("VLM did not detect clear epidemic plot")
        else:
            # Fallback if VLM fails: give points if file size is good
            if result.get('plot_size_bytes', 0) > 30000:
                score += 25
                feedback.append("VLM unavailable, trusting plot file size")
    else:
        # Fallback
        if result.get('plot_size_bytes', 0) > 30000:
            score += 25
            feedback.append("VLM unavailable, trusting plot file size")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }