#!/usr/bin/env python3
"""
Verifier for rsm_chemical_optimization task.

Verification Logic:
1. Script Verification (20 pts):
   - File exists and modified during task.
   - Contains 'rsm' library load and 'SO' model usage.
2. Result Accuracy (50 pts):
   - Optimal Time approx 86.8 (20 pts)
   - Optimal Temp approx 176.3 (20 pts)
   - Predicted Yield approx 87.4 (10 pts)
3. Visualization (30 pts):
   - Contour plot exists & valid (15 pts)
   - Surface plot exists & valid (15 pts)

Adversarial Checks:
- Must install 'rsm' package (cannot use pre-calc values without it likely).
- Checks file timestamps.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_rsm_optimization(traj, env_info, task_info):
    """
    Verify the RSM optimization results.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # Load ground truth from metadata
    metadata = task_info.get('metadata', {}).get('ground_truth', {})
    gt_time = metadata.get('optimal_time', 86.8)
    gt_temp = metadata.get('optimal_temp', 176.3)
    gt_yield = metadata.get('predicted_yield', 87.4)
    tol_input = metadata.get('tolerance_inputs', 1.0)
    tol_yield = metadata.get('tolerance_yield', 2.0)

    # Fetch result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []

    # 1. Script & Package Verification (20 pts)
    script_info = result.get('script', {})
    script_analysis = result.get('script_content_analysis', {})
    rsm_installed = result.get('rsm_installed', False)

    if script_info.get('exists') and script_info.get('created_during'):
        if rsm_installed:
            score += 10
            feedback.append("Script created and 'rsm' package installed (+10)")
        else:
            feedback.append("Script created but 'rsm' package NOT installed (0)")
        
        # Check for model usage
        if script_analysis.get('has_rsm_library') and script_analysis.get('has_so_function'):
            score += 10
            feedback.append("Script uses rsm library and SO() function (+10)")
        else:
            feedback.append("Script does not appear to use rsm::SO() model (0)")
    else:
        feedback.append("Script not found or not modified during task (0)")

    # 2. Result Accuracy (50 pts)
    csv_info = result.get('results_csv', {})
    csv_data = result.get('csv_data', {})
    
    if csv_info.get('exists') and csv_info.get('created_during'):
        try:
            # Parse values
            pred_time = float(csv_data.get('optimal_time', -999))
            pred_temp = float(csv_data.get('optimal_temp', -999))
            pred_yield = float(csv_data.get('predicted_yield', -999))

            # Verify Time
            if abs(pred_time - gt_time) <= tol_input:
                score += 20
                feedback.append(f"Optimal Time correct ({pred_time} ~ {gt_time}) (+20)")
            else:
                feedback.append(f"Optimal Time incorrect ({pred_time} vs {gt_time}) (0)")

            # Verify Temp
            if abs(pred_temp - gt_temp) <= tol_input:
                score += 20
                feedback.append(f"Optimal Temp correct ({pred_temp} ~ {gt_temp}) (+20)")
            else:
                feedback.append(f"Optimal Temp incorrect ({pred_temp} vs {gt_temp}) (0)")

            # Verify Yield
            if abs(pred_yield - gt_yield) <= tol_yield:
                score += 10
                feedback.append(f"Predicted Yield correct ({pred_yield} ~ {gt_yield}) (+10)")
            else:
                feedback.append(f"Predicted Yield incorrect ({pred_yield} vs {gt_yield}) (0)")

        except (ValueError, TypeError):
            feedback.append("CSV exists but values could not be parsed as numbers (0)")
    else:
        feedback.append("Results CSV missing or old (0)")

    # 3. Visualization (30 pts)
    contour = result.get('contour_plot', {})
    surface = result.get('surface_plot', {})

    # Contour Plot
    if contour.get('exists') and contour.get('created_during'):
        if contour.get('size', 0) > 10240: # >10KB
            score += 15
            feedback.append("Contour plot exists and valid size (+15)")
        else:
            score += 5
            feedback.append("Contour plot exists but suspiciously small (<10KB) (+5)")
    else:
        feedback.append("Contour plot missing (0)")

    # Surface Plot
    if surface.get('exists') and surface.get('created_during'):
        if surface.get('size', 0) > 10240: # >10KB
            score += 15
            feedback.append("Surface plot exists and valid size (+15)")
        else:
            score += 5
            feedback.append("Surface plot exists but suspiciously small (<10KB) (+5)")
    else:
        feedback.append("Surface plot missing (0)")

    # Final Evaluation
    passed = (score >= 60)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }