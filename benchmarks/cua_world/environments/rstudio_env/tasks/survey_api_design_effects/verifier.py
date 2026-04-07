#!/usr/bin/env python3
"""
Verifier for Survey Analysis Task (survey_api_design_effects@1).
Verifies survey estimates, design effects, and regression results using real data ranges.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_survey_analysis(traj, env_info, task_info):
    """
    Verify the survey analysis task.
    
    Scoring Criteria:
    1. Estimates CSV (30 pts): Exists, correct columns, mean in range.
    2. Design Effects CSV (20 pts): Exists, Cluster Deff > Stratified Deff.
    3. Regression CSV (20 pts): Exists, 'meals' coef negative and significant.
    4. Plot & Script (30 pts): Plot size, script uses survey package, VLM check.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON
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
    
    files = result.get('files', {})
    data = result.get('data_validation', {})
    script_analysis = result.get('script_analysis', {})

    # --- Criterion 1: Domain Estimates (30 pts) ---
    if files.get('estimates_csv') == 'new':
        score += 5
        feedback.append("Estimates CSV created.")
        
        if data.get('estimates', {}).get('valid'):
            score += 5
            # Check Mean Range (Elementary Stratified should be ~648)
            strat_mean = data['estimates'].get('strat_elem_mean', 0)
            if 635 <= strat_mean <= 665:
                score += 10
                feedback.append(f"Stratified Mean ({strat_mean:.1f}) in correct range.")
            else:
                feedback.append(f"Stratified Mean ({strat_mean:.1f}) out of expected range (635-665).")
            
            # Check Standard Errors: Cluster SE usually > Stratified SE
            clus_se = data['estimates'].get('clus_elem_se', 0)
            strat_se = data['estimates'].get('strat_elem_se', 0)
            if clus_se > strat_se and strat_se > 0:
                score += 10
                feedback.append("Standard Errors reflect design (Cluster > Stratified).")
            else:
                feedback.append(f"SE check failed: Cluster SE ({clus_se:.2f}) vs Strat SE ({strat_se:.2f}).")
        else:
            feedback.append("Estimates CSV format invalid.")
    else:
        feedback.append("Estimates CSV not created.")

    # --- Criterion 2: Design Effects (20 pts) ---
    if files.get('deff_csv') == 'new':
        score += 5
        if data.get('deff', {}).get('valid'):
            strat_deff = data['deff'].get('strat_deff', 0)
            clus_deff = data['deff'].get('clus_deff', 0)
            
            # Stratified Deff should be low (~0.9-1.2), Cluster Deff high (>1.5)
            if clus_deff > 1.5:
                score += 10
                feedback.append(f"Cluster Deff ({clus_deff:.2f}) indicates design effect.")
            else:
                feedback.append(f"Cluster Deff ({clus_deff:.2f}) too low.")
                
            if strat_deff < clus_deff:
                score += 5
                feedback.append("Stratified Deff < Cluster Deff (correct).")
    else:
        feedback.append("Design Effects CSV not created.")

    # --- Criterion 3: Regression (20 pts) ---
    if files.get('regression_csv') == 'new':
        score += 5
        if data.get('regression', {}).get('valid'):
            meals_coef = data['regression'].get('meals_coef', 0)
            meals_p = data['regression'].get('meals_p', 1.0)
            
            # Meals (poverty) should be negatively correlated
            if -5.0 <= meals_coef <= -2.0:
                score += 10
                feedback.append(f"Regression coef for meals ({meals_coef:.2f}) in range.")
            else:
                feedback.append(f"Regression coef ({meals_coef:.2f}) out of range.")
                
            if meals_p < 0.05:
                score += 5
                feedback.append("Regression effect is significant.")
    else:
        feedback.append("Regression CSV not created.")

    # --- Criterion 4: Script & Plot (30 pts) ---
    if files.get('plot_png') == 'new':
        plot_size = data.get('plot_size_kb', 0)
        if plot_size > 20:
            score += 10
            feedback.append("Analysis plot created and valid size.")
        else:
            score += 5
            feedback.append("Analysis plot created but very small.")
    
    # Script check
    if files.get('script') != 'missing':
        if script_analysis.get('has_svydesign', 0) > 0:
            score += 10
            feedback.append("Script uses svydesign().")
        if script_analysis.get('has_svyglm', 0) > 0:
            score += 10
            feedback.append("Script uses svyglm().")

    # VLM Check (Optional integration if query_vlm available)
    query_vlm = env_info.get('query_vlm')
    final_screenshot = env_info.get('get_final_screenshot', lambda t: None)(traj)
    
    if query_vlm and final_screenshot and score >= 40: # Only check if basic programmatic pass
        # Bonus points or confirmation
        pass 

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }