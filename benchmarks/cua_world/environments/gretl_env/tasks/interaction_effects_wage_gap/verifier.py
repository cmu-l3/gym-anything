#!/usr/bin/env python3
"""
Verifier for interaction_effects_wage_gap task.

Checks:
1. Output file existence and timestamp.
2. Content parsing for correct model specification (dependent variable, regressors).
3. Numerical accuracy of coefficients (educ, female, exper, female_exper).
4. VLM verification of the workflow.
"""

import json
import os
import re
import tempfile
import logging
from typing import Dict, Any

# Import VLM utilities if available in the environment
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
except ImportError:
    # Mock for local testing or fallback
    def sample_trajectory_frames(traj, n=5): return []
    def get_final_screenshot(traj): return None
    def query_vlm(**kwargs): return {"success": False, "error": "VLM not available"}

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_gretl_output(content: str) -> Dict[str, float]:
    """
    Parses Gretl OLS output text to extract coefficients.
    
    Example output line:
    educ         0.09134    0.0056    16.31    1.23e-50 ***
    """
    coeffs = {}
    lines = content.split('\n')
    
    # Regex to capture variable name and the first number (coefficient)
    # Looks for lines starting with a word, followed by numbers
    # We look for specific variable names we care about
    target_vars = ['const', 'educ', 'female', 'exper', 'female_exper', 'lwage']
    
    for line in lines:
        line = line.strip()
        parts = line.split()
        if not parts:
            continue
            
        var_name = parts[0]
        
        # Check if this line is a coefficient line
        if var_name in target_vars and len(parts) >= 2:
            try:
                # The second column is usually the coefficient
                val = float(parts[1])
                coeffs[var_name] = val
            except ValueError:
                continue
                
        # Also check for dependent variable declaration
        if "Dependent variable:" in line:
            if "lwage" in line or "l_wage" in line:
                coeffs['dependent_var_check'] = 1.0
            elif "wage" in line and "l_" not in line and "log" not in line:
                 coeffs['dependent_var_check'] = 0.0 # Raw wage used error

    return coeffs

def verify_interaction_effects_wage_gap(traj, env_info, task_info):
    """
    Verifies the wage gap interaction task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    ground_truth = metadata.get('ground_truth', {
        "educ": 0.091,
        "female": -0.237,
        "exper": 0.014,
        "female_exper": -0.003
    })
    tolerance = metadata.get('tolerance', 0.005)

    score = 0
    feedback = []

    # 1. Check Task Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    if not task_result.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output file not found."}
    
    score += 10
    feedback.append("Output file exists.")

    if task_result.get("file_created_during_task", False):
        score += 10
        feedback.append("File created during task.")
    else:
        feedback.append("Warning: Output file timestamp is suspect.")

    # 2. Analyze Output Content
    temp_output = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env(task_result["output_path"], temp_output.name)
        with open(temp_output.name, 'r') as f:
            content = f.read()
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to read output file: {e}"}
    finally:
        if os.path.exists(temp_output.name):
            os.unlink(temp_output.name)

    coeffs = parse_gretl_output(content)
    
    # Check dependent variable (log wage vs wage)
    # Note: parse_gretl_output sets 'dependent_var_check' to 1.0 if correct
    if coeffs.get('dependent_var_check', 0) == 1.0:
        score += 20
        feedback.append("Correct dependent variable (log wage).")
    else:
        feedback.append("Incorrect dependent variable (likely raw wage).")

    # Check for interaction term
    if 'female_exper' in coeffs:
        score += 20
        feedback.append("Interaction term 'female_exper' present.")
    else:
        feedback.append("Missing interaction term 'female_exper'.")

    # Check coefficient accuracy
    accurate_count = 0
    total_checks = 0
    
    for var, expected in ground_truth.items():
        total_checks += 1
        if var in coeffs:
            actual = coeffs[var]
            if abs(actual - expected) <= tolerance:
                accurate_count += 1
            else:
                feedback.append(f"Value mismatch for {var}: got {actual}, expected ~{expected}")
        else:
            feedback.append(f"Missing coefficient for {var}")

    # Award points for accuracy (max 40)
    if total_checks > 0:
        accuracy_score = (accurate_count / total_checks) * 40
        score += accuracy_score
        if accurate_count == total_checks:
            feedback.append("All coefficients accurate.")

    # 3. VLM Verification
    # Check if the agent actually used the software interface
    frames = sample_trajectory_frames(traj, n=3)
    final_screen = get_final_screenshot(traj)
    
    vlm_prompt = (
        "Check these screenshots of the Gretl econometrics software. "
        "Does the user appear to be performing a regression analysis? "
        "Look for: 1. A model window or results output. 2. A dialog for creating variables or running OLS. "
        "Answer 'Yes' if the workflow looks correct for econometric analysis."
    )
    
    vlm_images = frames + ([final_screen] if final_screen else [])
    
    if vlm_images:
        vlm_result = query_vlm(images=vlm_images, prompt=vlm_prompt)
        if vlm_result.get("success", False) and "yes" in vlm_result.get("response", "").lower():
            # If program checks failed but VLM looks good, give partial credit? 
            # Or just use it as a sanity check. Here we verify workflow.
            feedback.append("VLM confirms workflow.")
        else:
            feedback.append("VLM could not confirm visual workflow.")

    passed = score >= 70 and 'female_exper' in coeffs
    
    return {
        "passed": passed,
        "score": int(score),
        "feedback": " ".join(feedback)
    }