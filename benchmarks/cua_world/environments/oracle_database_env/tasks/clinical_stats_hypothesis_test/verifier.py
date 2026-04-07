#!/usr/bin/env python3
"""
Verifier for Clinical Statistical Hypothesis Testing task.

Verification Logic:
1. Calculates ground truth statistics dynamically from the raw data dump exported from the DB.
   This ensures robustness against minor dataset variations or version changes.
   - P-Value (T-Test independent)
   - Pearson Correlation
   - Group Averages
2. Compares agent's stored results in `STUDY_RESULTS` against ground truth.
3. Checks for existence and logic of `PATIENT_COHORTS_VW`.

Dependencies: scipy (for t-test/correlation) - installed via pip if missing.
"""

import json
import os
import tempfile
import logging
import math
import sys
import subprocess

# Ensure scipy is available for statistical verification
try:
    from scipy import stats
    import numpy as np
except ImportError:
    subprocess.check_call([sys.executable, "-m", "pip", "install", "scipy", "numpy"])
    from scipy import stats
    import numpy as np

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_clinical_stats(traj, env_info, task_info):
    """
    Verify the clinical statistics task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result file
    with tempfile.TemporaryDirectory() as tmpdir:
        result_path = os.path.join(tmpdir, "task_result.json")
        try:
            copy_from_env("/tmp/task_result.json", result_path)
            with open(result_path, 'r') as f:
                result_data = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}

    # Extract Data
    agent_results = result_data.get("agent_results", {})
    raw_data = result_data.get("raw_data_dump", [])
    view_def = result_data.get("view_definition", "").upper()
    
    if not raw_data:
        return {"passed": False, "score": 0, "feedback": "CRITICAL: No raw data found in export. Database may be empty."}

    # --- 1. Calculate Ground Truth ---
    # Parse data into lists
    # Diagnosis > 0 is DISEASE, == 0 is NORMAL
    
    disease_hr = []
    normal_hr = []
    
    ages = []
    chols = []
    
    for row in raw_data:
        # Correlation Data (Age vs Chol) - filter out None
        if row['age'] is not None and row['chol'] is not None:
            ages.append(row['age'])
            chols.append(row['chol'])
            
        # T-Test Data (Thalach by Diagnosis) - filter out None
        if row['thalach'] is not None and row['diagnosis'] is not None:
            if row['diagnosis'] > 0:
                disease_hr.append(row['thalach'])
            else:
                normal_hr.append(row['thalach'])

    # Calculate Stats
    # Averages
    gt_avg_disease = np.mean(disease_hr) if disease_hr else 0
    gt_avg_normal = np.mean(normal_hr) if normal_hr else 0
    
    # Correlation (Pearson)
    if len(ages) > 1:
        gt_corr, _ = stats.pearsonr(ages, chols)
    else:
        gt_corr = 0
        
    # T-Test (Independent, Two-sided)
    # Note: Oracle's STATS_T_TEST_INDEP assumes pooled variance by default unless specified otherwise,
    # but usually behaves like a standard t-test. We'll check tolerance.
    # scipy.stats.ttest_ind defaults to equal_var=True (pooled variance).
    if len(disease_hr) > 1 and len(normal_hr) > 1:
        t_stat, gt_p_value = stats.ttest_ind(disease_hr, normal_hr, equal_var=True)
    else:
        gt_p_value = 1.0

    logger.info(f"Ground Truth: AvgD={gt_avg_disease}, AvgN={gt_avg_normal}, Corr={gt_corr}, P={gt_p_value}")

    # --- 2. Scoring ---
    score = 0
    feedback = []
    tolerances = task_info.get("metadata", {}).get("tolerances", {})
    tol_p = tolerances.get("p_value", 0.0001)
    tol_c = tolerances.get("correlation", 0.0001)
    tol_a = tolerances.get("average", 0.01)

    # Criterion 1: View Existence & Logic (25 pts)
    if result_data.get("view_exists"):
        score += 10
        feedback.append("View PATIENT_COHORTS_VW created.")
        
        # Check logic: look for CASE/DECODE or WHERE logic mapping >0 to Disease
        if "DISEASE" in view_def and "NORMAL" in view_def:
            score += 15
            feedback.append("View logic appears correct (labels found).")
        else:
            feedback.append("View created but logic unclear (missing 'DISEASE'/'NORMAL' labels).")
    else:
        feedback.append("View PATIENT_COHORTS_VW missing.")

    # Criterion 2: Results Table Structure (5 pts)
    if result_data.get("table_exists"):
        score += 5
        feedback.append("Table STUDY_RESULTS exists.")
    else:
        feedback.append("Table STUDY_RESULTS missing.")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

    # Criterion 3: Averages (20 pts)
    # Check AVG_HR_DISEASE
    val_d = agent_results.get("AVG_HR_DISEASE")
    if val_d is not None and abs(val_d - gt_avg_disease) < tol_a:
        score += 10
        feedback.append(f"Avg HR Disease correct ({val_d}).")
    else:
        feedback.append(f"Avg HR Disease incorrect (Agent: {val_d}, GT: {gt_avg_disease:.4f}).")

    # Check AVG_HR_NORMAL
    val_n = agent_results.get("AVG_HR_NORMAL")
    if val_n is not None and abs(val_n - gt_avg_normal) < tol_a:
        score += 10
        feedback.append(f"Avg HR Normal correct ({val_n}).")
    else:
        feedback.append(f"Avg HR Normal incorrect (Agent: {val_n}, GT: {gt_avg_normal:.4f}).")

    # Criterion 4: Correlation (20 pts)
    val_corr = agent_results.get("CORRELATION_AGE_CHOL")
    if val_corr is not None and abs(val_corr - gt_corr) < tol_c:
        score += 20
        feedback.append(f"Correlation correct ({val_corr}).")
    else:
        feedback.append(f"Correlation incorrect (Agent: {val_corr}, GT: {gt_corr:.4f}).")

    # Criterion 5: P-Value (30 pts)
    val_p = agent_results.get("P_VALUE_HR_DIFF")
    # P-values can be tiny, check absolute diff or if both are very small (<1e-10)
    if val_p is not None:
        if abs(val_p - gt_p_value) < tol_p:
            score += 30
            feedback.append(f"P-Value correct ({val_p}).")
        elif val_p < 1e-5 and gt_p_value < 1e-5:
             # Both essentially zero
             score += 30
             feedback.append("P-Value correct (both < 1e-5).")
        else:
            feedback.append(f"P-Value incorrect (Agent: {val_p}, GT: {gt_p_value:.6f}).")
    else:
        feedback.append("P-Value missing.")

    passed = score >= 65
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }