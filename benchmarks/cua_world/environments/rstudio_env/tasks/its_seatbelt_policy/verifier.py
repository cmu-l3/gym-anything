#!/usr/bin/env python3
"""
Verifier for Interrupted Time Series (ITS) Seatbelt Policy Task.

Verifies:
1. Model Results CSV: Existence, structure, inclusion of law/seasonality terms.
2. Diagnostics CSV: Durbin-Watson statistic, correct observation count (192).
3. Plausibility: Level change estimate should be negative (approx -100 to -300).
4. Plot: Existence, file size (indicative of content), and VLM visual check.
5. Anti-gaming: File timestamps must be after task start.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_its_seatbelt_policy(traj, env_info, task_info):
    """
    Verify the ITS analysis of the UK Seatbelts dataset.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    get_final_screenshot = env_info.get('get_final_screenshot')

    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    max_score = 100
    feedback = []

    # --- 1. Model CSV Verification (25 points) ---
    model_res = result.get('model_csv', {})
    if model_res.get('status') == 'new':
        score += 10
        feedback.append("Model CSV created (+10)")
        
        if model_res.get('has_law_term'):
            score += 5
            feedback.append("Model includes intervention (law) term (+5)")
        else:
            feedback.append("Model missing intervention term")
            
        if model_res.get('has_seasonality'):
            score += 5
            feedback.append("Model includes seasonality terms (+5)")
        else:
            feedback.append("Model missing seasonality controls")
            
        if model_res.get('has_p_value'):
            score += 5
            feedback.append("Model includes p-values (+5)")
    else:
        feedback.append(f"Model CSV missing or not new (Status: {model_res.get('status')})")

    # --- 2. Diagnostics CSV Verification (25 points) ---
    diag_res = result.get('diagnostics_csv', {})
    if diag_res.get('status') == 'new':
        score += 10
        feedback.append("Diagnostics CSV created (+10)")
        
        if diag_res.get('has_durbin_watson'):
            score += 5
            feedback.append("Durbin-Watson statistic present (+5)")
        
        n_obs = diag_res.get('n_observations', 0)
        if n_obs == 192:
            score += 5
            feedback.append("Correct observation count (192) (+5)")
        else:
            feedback.append(f"Incorrect observation count: {n_obs} (Expected 192)")
            
        # Check Plausibility of Level Change
        # The seatbelt law reduced deaths, so coefficient should be negative.
        # Literature suggests reduction of ~100-200.
        try:
            est = float(diag_res.get('level_change_estimate', 0))
            if -350 <= est <= -20:
                score += 5
                feedback.append(f"Level change estimate plausible ({est:.2f}) (+5)")
            else:
                feedback.append(f"Level change estimate implausible ({est:.2f}) - check model specification")
        except ValueError:
            feedback.append("Could not parse level change estimate")
    else:
        feedback.append("Diagnostics CSV missing or not new")

    # --- 3. Plot Verification (20 points) ---
    plot_res = result.get('plot', {})
    plot_size = plot_res.get('size_bytes', 0)
    
    if plot_res.get('status') == 'new':
        score += 10
        feedback.append("Plot PNG created (+10)")
        
        # A simple empty plot is small (~5KB). A complex plot with counterfactuals > 30KB.
        if plot_size > 30000:
            score += 10
            feedback.append(f"Plot file size substantial ({plot_size} bytes) (+10)")
        elif plot_size > 5000:
            score += 5
            feedback.append("Plot file size minimal (+5)")
        else:
            feedback.append("Plot file too small/empty")
    else:
        feedback.append("Plot PNG missing or not new")

    # --- 4. Script Verification (10 points) ---
    script_res = result.get('script', {})
    if script_res.get('status') == 'new': # Modified during task
        score += 5
        feedback.append("R script modified (+5)")
    
    if script_res.get('has_modeling_code'):
        score += 5
        feedback.append("R script contains modeling code (+5)")

    # --- 5. VLM Verification (20 points) ---
    # We check the final screenshot for the plot content
    vlm_score = 0
    final_screenshot = get_final_screenshot(traj)
    
    if final_screenshot and query_vlm:
        prompt = """
        You are verifying an Interrupted Time Series (ITS) plot in RStudio.
        Look for a time series plot showing:
        1. Data points (monthly dots/lines).
        2. A vertical line marking the intervention (around 1983).
        3. A change in the trend/level after the vertical line.
        4. Ideally, a dashed 'counterfactual' line showing what would happen without the intervention.
        
        Does this image contain such a plot?
        Respond in JSON: {"has_its_plot": bool, "has_intervention_line": bool, "has_counterfactual": bool}
        """
        try:
            vlm_out = query_vlm(image=final_screenshot, prompt=prompt)
            parsed = vlm_out.get('parsed', {})
            
            if parsed.get('has_its_plot'):
                vlm_score += 10
                feedback.append("VLM: ITS plot detected (+10)")
            
            if parsed.get('has_intervention_line'):
                vlm_score += 5
                feedback.append("VLM: Intervention line detected (+5)")
                
            if parsed.get('has_counterfactual'):
                vlm_score += 5
                feedback.append("VLM: Counterfactual line detected (+5)")
                
        except Exception as e:
            feedback.append(f"VLM verification failed: {str(e)}")
            # Fallback: if plot file exists and is large, give partial VLM credit
            if plot_size > 50000:
                vlm_score += 10
                feedback.append("VLM fallback: Large plot file exists (+10)")

    score += vlm_score

    # Final Pass/Fail
    passed = score >= 60
    
    # Gate check: Must have at least the model CSV or plot
    if not (model_res.get('status') == 'new' or plot_res.get('status') == 'new'):
        passed = False
        feedback.append("GATE FAIL: Neither model results nor plot were produced.")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }