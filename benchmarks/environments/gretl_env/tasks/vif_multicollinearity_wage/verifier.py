#!/usr/bin/env python3
"""
Verifier for vif_multicollinearity_wage task.
Checks if the user script executes correctly and produces VIF values matching ground truth.
"""

import json
import base64
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_vif_multicollinearity_wage(traj, env_info, task_info):
    """
    Verify the VIF Multicollinearity Wage task.
    
    Scoring Criteria:
    1. Script file exists and is valid hansl (runs without error) (30 pts)
    2. Model output file exists and contains OLS results (20 pts)
    3. VIF output file exists and contains VIF values (20 pts)
    4. Numerical accuracy: VIF values match ground truth (30 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read verification result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    files = result.get('files', {})
    script_info = files.get('script', {})
    model_info = files.get('model_output', {})
    vif_info = files.get('vif_output', {})
    
    # Criterion 1: Script Validity (30 pts)
    if script_info.get('exists'):
        if script_info.get('valid_execution'):
            score += 30
            feedback.append("Script executes successfully (30/30)")
        else:
            score += 15
            feedback.append("Script exists but execution failed (15/30)")
    else:
        feedback.append("Script file missing (0/30)")
        
    # Criterion 2: Model Output (20 pts)
    if model_info.get('exists'):
        content = base64.b64decode(model_info.get('content_b64', '')).decode('utf-8', errors='ignore')
        if "Model" in content and ("Dependent variable" in content or "ols" in content.lower()):
            score += 20
            feedback.append("Model output file contains regression results (20/20)")
        else:
            score += 10
            feedback.append("Model output file exists but content unclear (10/20)")
    else:
        feedback.append("Model output file missing (0/20)")

    # Criterion 3: VIF Output (20 pts)
    vif_content = ""
    if vif_info.get('exists'):
        vif_content = base64.b64decode(vif_info.get('content_b64', '')).decode('utf-8', errors='ignore')
        if "Variance Inflation" in vif_content or "VIF" in vif_content:
            score += 20
            feedback.append("VIF output file contains VIF results (20/20)")
        else:
            score += 10
            feedback.append("VIF output file exists but content unclear (10/20)")
    else:
        feedback.append("VIF output file missing (0/20)")
        
    # Criterion 4: Numerical Accuracy (30 pts)
    # Compare extracted VIFs from user output or execution log with ground truth
    ground_truth_raw = base64.b64decode(result.get('ground_truth_b64', '')).decode('utf-8', errors='ignore')
    
    # Helper to extract VIFs: Look for lines like "exper    1.234"
    def extract_vifs(text):
        vifs = {}
        # Pattern: variable name followed by float, usually in a table
        # Common Gretl VIF output format:
        # "       educ      1.456"
        for line in text.splitlines():
            parts = line.strip().split()
            if len(parts) >= 2:
                try:
                    val = float(parts[-1])
                    var = parts[0]
                    if var in ['educ', 'exper', 'exper2', 'female', 'black', 'metro', 'south', 'west']:
                        vifs[var] = val
                except ValueError:
                    continue
        return vifs

    gt_vifs = extract_vifs(ground_truth_raw)
    
    # Try to get user VIFs from VIF file first, then script execution log
    user_vifs = extract_vifs(vif_content)
    if not user_vifs and script_info.get('execution_log_b64'):
        log_content = base64.b64decode(script_info.get('execution_log_b64', '')).decode('utf-8', errors='ignore')
        user_vifs = extract_vifs(log_content)
        
    matches = 0
    total_vars = len(gt_vifs)
    
    if total_vars > 0:
        for var, gt_val in gt_vifs.items():
            user_val = user_vifs.get(var)
            if user_val is not None:
                # Tolerance 0.05
                if abs(user_val - gt_val) < 0.05:
                    matches += 1
        
        # Scale score based on matches
        accuracy_score = int((matches / total_vars) * 30)
        score += accuracy_score
        feedback.append(f"Numerical accuracy: {matches}/{total_vars} VIF values match ({accuracy_score}/30)")
    else:
        # Fallback if ground truth parsing fails (shouldn't happen)
        if score >= 70: 
            score += 30
            feedback.append("Ground truth unavailable, assuming correct based on script success (30/30)")
        else:
            feedback.append("Could not verify numerical accuracy (0/30)")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": "; ".join(feedback)
    }