#!/usr/bin/env python3
"""
Verifier for HSB Multilevel Modeling task.

Evaluates:
1. Output file existence and timestamps (Anti-gaming).
2. Data validity of CSVs (rows, columns, statistical plausibility).
3. Plot file quality.
4. VLM verification of the coding workflow.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_hsb_multilevel_modeling(traj, env_info, task_info):
    """
    Verify the HSB multilevel modeling task.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # 1. Load results from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            res = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # --- Criterion 1: R Script (10 pts) ---
    if res['script']['exists'] and res['script']['is_new']:
        # Basic check: did they save the file?
        score += 10
        feedback.append("R script saved (+10)")
    elif res['script']['exists']:
        feedback.append("R script exists but was not modified (0/10)")
    else:
        feedback.append("R script missing (0/10)")

    # --- Criterion 2: Model Comparison CSV (25 pts) ---
    comp = res.get('comparison_csv', {})
    comp_data = res.get('comparison_data', {})
    
    if comp.get('is_new'):
        c_score = 0
        if comp_data.get('rows', 0) >= 3:
            c_score += 10
            feedback.append("Comparison table has >= 3 models (+10)")
        else:
            feedback.append(f"Comparison table has {comp_data.get('rows', 0)} rows (expected >=3)")

        icc = comp_data.get('null_icc_value', 0)
        # HSB data ICC is approx 0.18
        if 0.10 <= icc <= 0.30:
            c_score += 15
            feedback.append(f"Null model ICC ({icc:.3f}) is correct (+15)")
        elif icc > 0:
             c_score += 5
             feedback.append(f"ICC value present but out of range ({icc:.3f}) (+5)")
        else:
            feedback.append("ICC value missing or invalid")
            
        score += c_score
    else:
        feedback.append("Model comparison CSV missing or not created during task")

    # --- Criterion 3: Fixed Effects CSV (25 pts) ---
    fixed = res.get('fixed_csv', {})
    fixed_data = res.get('fixed_data', {})
    
    if fixed.get('is_new'):
        f_score = 0
        checks = fixed_data.get('coef_checks', {})
        
        # SES should be positive (approx +2.39)
        if checks.get('ses', 0) > 0:
            f_score += 8
            feedback.append("SES effect is positive (+8)")
            
        # Minority should be negative (approx -2.39)
        if checks.get('minority', 0) < 0:
            f_score += 8
            feedback.append("Minority effect is negative (+8)")
            
        # Sector (Catholic) should be positive (approx +1.22)
        if checks.get('sector', 0) > 0:
             f_score += 9
             feedback.append("Catholic Sector effect is positive (+9)")
             
        score += f_score
    else:
        feedback.append("Fixed effects CSV missing or not created during task")

    # --- Criterion 4: Plots (20 pts each) ---
    # Caterpillar Plot
    cat_plot = res.get('caterpillar_plot', {})
    if cat_plot.get('is_new') and cat_plot.get('size', 0) > 15000: # >15KB
        score += 20
        feedback.append("Caterpillar plot created (+20)")
    else:
        feedback.append("Caterpillar plot missing or too small")

    # SES Plot
    ses_plot = res.get('ses_plot', {})
    if ses_plot.get('is_new') and ses_plot.get('size', 0) > 10000: # >10KB
        score += 20
        feedback.append("SES effects plot created (+20)")
    else:
        feedback.append("SES effects plot missing or too small")

    # --- VLM Workflow Verification (Optional but good for robustness) ---
    # If score is borderline, or just to verify "effort", we can query VLM
    # We only use this for logging/feedback unless we want to award bonus points
    # Let's keep it simple: verification is primarily programmatic as requested
    
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }