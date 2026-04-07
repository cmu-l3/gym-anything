#!/usr/bin/env python3
"""
Verifier for bayesian_pk_theophylline task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_bayesian_pk(traj, env_info, task_info):
    """
    Verifies the Bayesian PK analysis task.
    
    Criteria:
    1. Deliverables exist and were created during task (Anti-gaming).
    2. Population parameters are biologically plausible (Slope is negative).
    3. Convergence is achieved (Rhat < 1.1).
    4. Model comparison was performed.
    5. Plots are generated and valid.
    """
    
    # 1. Setup - Load data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    files = result.get("files", {})
    metrics = result.get("metrics", {})
    script_analysis = result.get("script_analysis", {})

    # Criterion 1: Population Parameters CSV (20 pts)
    # -----------------------------------------------------
    p_csv = files.get("params_csv", {})
    if p_csv.get("exists") and p_csv.get("new"):
        score += 5
        feedback.append("Population params CSV created (+5)")
        
        # Check logic
        beta_time = metrics.get("beta_time_est")
        if beta_time is not None:
            # Expected range: -0.15 to -0.02
            if -0.15 <= beta_time <= -0.02:
                score += 15
                feedback.append(f"Elimination rate constant plausible ({beta_time}) (+15)")
            else:
                feedback.append(f"Elimination rate constant out of range ({beta_time}) (0)")
        else:
            feedback.append("Could not parse 'Time' parameter from CSV (0)")
    else:
        feedback.append("Population params CSV missing or old (0)")

    # Criterion 2: Convergence (15 pts)
    # -----------------------------------------------------
    c_csv = files.get("conv_csv", {})
    if c_csv.get("exists") and c_csv.get("new"):
        score += 5
        feedback.append("Convergence CSV created (+5)")
        
        max_rhat = metrics.get("max_rhat", 999)
        # Allow slightly loose check since agent can't control randomness perfectly
        if max_rhat < 1.15: 
            score += 10
            feedback.append(f"Convergence achieved (Max Rhat {max_rhat} < 1.15) (+10)")
        else:
            feedback.append(f"Poor convergence detected (Max Rhat {max_rhat}) (0)")
    else:
        feedback.append("Convergence CSV missing or old (0)")

    # Criterion 3: Model Comparison (20 pts)
    # -----------------------------------------------------
    l_csv = files.get("loo_csv", {})
    if l_csv.get("exists") and l_csv.get("new"):
        score += 5
        feedback.append("Model comparison CSV created (+5)")
        
        if metrics.get("loo_models_count", 0) >= 2:
            score += 10
            feedback.append("Compared at least 2 models (+10)")
        if metrics.get("loo_valid"):
            score += 5
            feedback.append("LOO values look valid (+5)")
    else:
        feedback.append("Model comparison CSV missing (0)")

    # Criterion 4: Visualizations (30 pts)
    # -----------------------------------------------------
    # PPC Plot
    ppc = files.get("ppc_png", {})
    if ppc.get("exists") and ppc.get("new"):
        if ppc.get("size", 0) > 20000: # > 20KB
            score += 15
            feedback.append("Posterior predictive plot created and valid size (+15)")
        else:
            score += 5
            feedback.append("Posterior predictive plot too small (+5)")
    else:
        feedback.append("Posterior predictive plot missing (0)")

    # Fits Plot
    fits = files.get("fits_png", {})
    if fits.get("exists") and fits.get("new"):
        if fits.get("size", 0) > 40000: # > 40KB (usually larger for multi-panel)
            score += 15
            feedback.append("Individual fits plot created and valid size (+15)")
        else:
            score += 5
            feedback.append("Individual fits plot too small (+5)")
    else:
        feedback.append("Individual fits plot missing (0)")

    # Criterion 5: Script Quality (15 pts)
    # -----------------------------------------------------
    script = files.get("script", {})
    if script.get("exists") and script.get("new"):
        score += 5
        if script_analysis.get("has_bayes_pkg"):
            score += 5
            feedback.append("Script uses Bayesian packages (+5)")
        if script_analysis.get("has_loo"):
            score += 5
            feedback.append("Script uses LOO (+5)")
    else:
        feedback.append("Script not modified (0)")

    # VLM Verification (Trajectory-based)
    # If main score is borderline, we can use VLM to verify intent
    # For now, we rely on file evidence as primary signal
    
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }