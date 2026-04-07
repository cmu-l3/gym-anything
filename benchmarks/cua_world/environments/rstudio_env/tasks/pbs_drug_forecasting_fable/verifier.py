#!/usr/bin/env python3
"""
Verifier for PBS Drug Forecasting Task.

Evaluation Criteria:
1. Forecast CSV (l01_forecast_values.csv):
   - Exists and created during task.
   - Contains 36 months of data (3 years).
   - Values are in the correct magnitude (~200k), indicating proper aggregation.
2. Model Accuracy CSV (l01_model_accuracy.csv):
   - Exists.
   - Compares at least 2 models.
3. Plots (Decomposition & Forecast):
   - Files exist and are valid PNGs.
   - VLM verification of visual content.
4. Process:
   - Script modified.
   - VLM check of RStudio workflow.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_pbs_forecasting(traj, env_info, task_info):
    """Verify the forecasting task execution and results."""
    
    # 1. Setup - Load Results
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

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
    
    # 2. Programmatic Verification (60 points total)

    # Criterion: Forecast CSV (25 pts)
    # - Exists: 5 pts
    # - Length 36 (+/- 2): 10 pts
    # - Magnitude > 50k (aggregation check): 10 pts
    
    forecast_rows = result.get('forecast_rows', 0)
    forecast_val = result.get('forecast_mean_val', 0)
    
    if result.get('forecast_csv_exists'):
        score += 5
        feedback.append("Forecast CSV exists (+5)")
        
        if 34 <= forecast_rows <= 38:
            score += 10
            feedback.append(f"Forecast horizon correct ({forecast_rows} months) (+10)")
        else:
            feedback.append(f"Forecast horizon incorrect ({forecast_rows} rows, expected 36)")
            
        # Total L01 scripts are roughly 200k/month. Subgroups are 10k-50k.
        # If mean > 100k, they likely aggregated correctly.
        if forecast_val > 100000:
            score += 10
            feedback.append(f"Forecast values in expected range (Mean: {forecast_val:.0f}) (+10)")
        elif forecast_val > 0:
            feedback.append(f"Forecast values too low ({forecast_val:.0f}). Did you aggregate the data? (0/10)")
        else:
            feedback.append("Forecast values invalid/zero.")
    else:
        feedback.append("Forecast CSV not found.")

    # Criterion: Accuracy Table (15 pts)
    if result.get('accuracy_csv_exists'):
        score += 5
        feedback.append("Accuracy table exists (+5)")
        if result.get('accuracy_models_count', 0) >= 2:
            score += 10
            feedback.append(f"Model comparison found ({result['accuracy_models_count']} models) (+10)")
        else:
            feedback.append("Accuracy table does not compare multiple models.")
    else:
        feedback.append("Accuracy table not found.")

    # Criterion: Plot Existence (10 pts)
    plots_found = 0
    if result.get('decomp_plot_exists'): plots_found += 1
    if result.get('forecast_plot_exists'): plots_found += 1
    
    if plots_found == 2:
        score += 10
        feedback.append("Both required plots exist (+10)")
    elif plots_found == 1:
        score += 5
        feedback.append("One plot found (+5)")
    else:
        feedback.append("No plots found.")

    # Criterion: Script Modification (10 pts)
    if result.get('script_modified'):
        score += 10
        feedback.append("Analysis script was modified (+10)")
    else:
        feedback.append("Analysis script was not modified.")


    # 3. VLM Verification (40 points total)
    # Using trajectory to verify workflow and plot content
    
    query_vlm = env_info.get('query_vlm')
    get_final_screenshot = env_info.get('get_final_screenshot')
    
    if query_vlm:
        # We really want to verify the plots look like plots.
        # Since we can't easily pull the image files out to the VLM (unless we copy them),
        # we rely on the final screenshot or trajectory frames showing the Plots pane in RStudio.
        
        # We'll use the final screenshot which likely captures the RStudio state
        final_screenshot = get_final_screenshot(traj)
        
        prompt = """
        You are verifying an RStudio data analysis task.
        Look at the screenshot.
        1. Is RStudio open?
        2. Is there a plot visible in the 'Plots' pane (usually bottom right)?
        3. Does the plot look like a time series forecast (historical data + future predictions with intervals) OR a decomposition (multiple panels)?
        4. Is there R code visible in the editor that uses 'fpp3', 'fable', 'model', or 'forecast'?
        
        Return JSON:
        {
            "rstudio_visible": bool,
            "plot_visible": bool,
            "plot_looks_correct": bool,
            "code_relevant": bool
        }
        """
        
        try:
            vlm_out = query_vlm(prompt=prompt, image=final_screenshot)
            parsed = vlm_out.get('parsed', {})
            
            if parsed.get('rstudio_visible'):
                score += 10
                feedback.append("VLM: RStudio visible (+10)")
            
            if parsed.get('plot_visible') and parsed.get('plot_looks_correct'):
                score += 20
                feedback.append("VLM: Valid time series plot detected (+20)")
            elif parsed.get('plot_visible'):
                score += 10
                feedback.append("VLM: Plot detected but unsure of content (+10)")
                
            if parsed.get('code_relevant'):
                score += 10
                feedback.append("VLM: Relevant forecasting code detected (+10)")
                
        except Exception as e:
            feedback.append(f"VLM verification failed: {e}")
            # Fallback points if VLM fails but programmatic passed hard checks
            if score >= 50:
                score += 20
                feedback.append("Fallback: Programmatic evidence strong, awarding partial VLM points")

    # Final Score Calculation
    passed = score >= 60 and result.get('forecast_csv_exists') and result.get('forecast_rows', 0) > 30

    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback)
    }