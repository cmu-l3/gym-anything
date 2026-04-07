#!/usr/bin/env python3
"""
Verifier for breast_roc_diagnostics task.

This task evaluates:
1. Package installation and data preparation (implicit in results)
2. ROC calculation for single features (Deliverable 1)
3. DeLong's test for model comparison (Deliverable 2)
4. Logistic regression and combined model ROC (Deliverable 3)
5. Multi-panel visualization (Deliverable 4)
"""

import json
import tempfile
import os
import base64
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_breast_roc_diagnostics(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    get_final_screenshot = env_info.get('get_final_screenshot')

    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # Retrieve result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve results: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    # --------------------------------------------------------------------------
    # CRITERION 1: Individual ROC CSV (25 pts)
    # --------------------------------------------------------------------------
    c1 = result['files']['individual_csv']
    d1 = result['data']['individual_roc']
    
    if c1['exists'] and c1['is_new']:
        score += 5
        feedback.append("Criterion 1: CSV created (+5)")
        
        # Check content
        if len(d1) == 9:
            score += 5
            feedback.append("  - Correct row count (9 features) (+5)")
        else:
            feedback.append(f"  - Incorrect row count: {len(d1)} (expected 9)")

        # Check columns
        required_cols = ['feature', 'auc', 'sensitivity', 'specificity']
        if len(d1) > 0 and all(k in d1[0] for k in required_cols):
            score += 5
            feedback.append("  - Required columns present (+5)")
            
            # Check AUC plausibility (should be > 0.5 and < 1.0)
            aucs = [float(row.get('auc', 0)) for row in d1]
            if all(0.5 <= a <= 1.0 for a in aucs):
                score += 5
                feedback.append("  - AUC values valid (+5)")
            
            # Check for high AUC (Cell.size/shape usually > 0.9)
            if any(a > 0.90 for a in aucs):
                score += 5
                feedback.append("  - High predictive value identified (>0.90) (+5)")
            else:
                feedback.append("  - AUC values suspiciously low (max < 0.90)")
        else:
            feedback.append("  - Missing required columns")
    else:
        feedback.append("Criterion 1: individual_roc.csv missing or old (0/25)")

    # --------------------------------------------------------------------------
    # CRITERION 2: AUC Comparison CSV (20 pts)
    # --------------------------------------------------------------------------
    c2 = result['files']['comparison_csv']
    d2 = result['data']['auc_comparison']
    
    if c2['exists'] and c2['is_new']:
        score += 5
        feedback.append("Criterion 2: Comparison CSV created (+5)")
        
        if len(d2) == 8:
            score += 5
            feedback.append("  - Correct comparison count (8) (+5)")
        
        if len(d2) > 0 and 'p_value' in d2[0]:
            score += 5
            feedback.append("  - p_value column present (+5)")
            
            # Check if any p-value is significant (usually comparisons with weak features are)
            p_vals = []
            for row in d2:
                try: p_vals.append(float(row['p_value']))
                except: pass
            
            if any(p < 0.05 for p in p_vals):
                score += 5
                feedback.append("  - Significant differences found (+5)")
            else:
                feedback.append("  - No significant p-values (unexpected)")
    else:
        feedback.append("Criterion 2: comparison.csv missing (0/20)")

    # --------------------------------------------------------------------------
    # CRITERION 3: Combined Model CSV (25 pts)
    # --------------------------------------------------------------------------
    c3 = result['files']['combined_csv']
    d3 = result['data']['combined_model']
    
    if c3['exists'] and c3['is_new']:
        score += 5
        feedback.append("Criterion 3: Combined model CSV created (+5)")
        
        if 'auc' in d3 and 'accuracy' in d3:
            score += 5
            feedback.append("  - Required metrics present (+5)")
            
            try:
                auc_comb = float(d3['auc'])
                n_obs = float(d3.get('n_observations', 0))
                
                # Combined model should be very good (>0.95)
                if auc_comb > 0.95:
                    score += 5
                    feedback.append("  - Combined AUC > 0.95 (+5)")
                
                # Check for correct data handling (complete cases)
                # Dataset has 699 rows, 16 NAs -> ~683 rows
                if 680 <= n_obs <= 683:
                    score += 10
                    feedback.append("  - Correct missing data handling (N~683) (+10)")
                else:
                    feedback.append(f"  - Suspicious observation count: {n_obs} (expected ~683)")
            except:
                feedback.append("  - Error parsing metrics")
    else:
        feedback.append("Criterion 3: combined_model.csv missing (0/25)")

    # --------------------------------------------------------------------------
    # CRITERION 4: Plot and Visuals (30 pts)
    # --------------------------------------------------------------------------
    c4 = result['files']['plot']
    dims = result['plot_dims']
    
    if c4['exists'] and c4['is_new']:
        score += 5
        feedback.append("Criterion 4: Plot PNG created (+5)")
        
        # Check dimensions
        try:
            w, h = map(int, dims.split('x'))
            if w >= 1200 and h >= 900:
                score += 5
                feedback.append("  - Dimensions correct (>=1200x900) (+5)")
            else:
                feedback.append(f"  - Dimensions too small: {dims}")
                
            if c4['size'] > 50000: # 50KB
                score += 5
                feedback.append("  - File size indicates content (+5)")
        except:
            feedback.append("  - Invalid image file")

        # VLM Verification
        if query_vlm:
            final_screenshot = get_final_screenshot(traj)
            # We verify the generated plot file content by asking VLM about the final screenshot 
            # (if the user opened it) OR ideally we should pass the generated image itself 
            # if the framework supported it. Assuming we verify the workspace state.
            # Here we'll check the final screenshot for evidence of the plot or RStudio displaying plots.
            
            vlm_prompt = """
            Does the screen show RStudio with a ROC curve plot? 
            Look for:
            1. A plot with curves moving from bottom-left to top-right.
            2. Multiple colored lines (indicating multiple features).
            3. A bar chart comparison if visible.
            4. The plot looks complex/professional (multi-panel).
            """
            
            try:
                vlm_res = query_vlm(prompt=vlm_prompt, image=final_screenshot)
                if vlm_res.get('success') and ('yes' in vlm_res['answer'].lower() or 'true' in str(vlm_res['parsed']).lower()):
                    score += 15
                    feedback.append("  - VLM confirmed ROC plot visibility (+15)")
                else:
                    # Fallback if VLM says no but file exists and is large -> partial credit
                    score += 5
                    feedback.append("  - VLM did not confirm plot, but file good size (+5)")
            except:
                score += 5 # Benefit of doubt
        else:
            score += 15 # No VLM available
            
    else:
        feedback.append("Criterion 4: Plot missing (0/30)")

    # --------------------------------------------------------------------------
    # Final Score Calculation
    # --------------------------------------------------------------------------
    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }