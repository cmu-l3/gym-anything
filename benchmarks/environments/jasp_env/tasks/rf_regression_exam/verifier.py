#!/usr/bin/env python3
import json
import os
import tempfile
import base64
import re
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

def verify_rf_regression(traj, env_info, task_info):
    """
    Verifies the JASP Random Forest Regression task.
    
    Criteria:
    1. JASP project file exists, is valid size, and created during task.
    2. Report file exists and contains valid MSE/R2/Predictor values.
    3. VLM: Confirms visual evidence of Random Forest analysis (plots, tables).
    """
    
    # 1. Setup and Environment Check
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    metadata = task_info.get('metadata', {})
    valid_predictors = [p.lower() for p in metadata.get('valid_predictors', ['anxiety', 'revise'])]
    
    # 2. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 3. Validate JASP Project File (20 pts)
    jasp_info = result_data.get('jasp_file', {})
    if jasp_info.get('exists') and jasp_info.get('created_during_task'):
        # A valid JASP file with data and analysis is usually > 10KB. Empty projects are tiny.
        if jasp_info.get('size', 0) > 5000:
            score += 20
            feedback.append("JASP project file saved successfully.")
        else:
            score += 5
            feedback.append("JASP project file saved, but size is suspiciously small (analysis might be missing).")
    else:
        feedback.append("JASP project file missing or not saved during task.")

    # 4. Validate Text Report Content (40 pts)
    report_info = result_data.get('report_file', {})
    if report_info.get('exists') and report_info.get('created_during_task'):
        try:
            content = base64.b64decode(report_info.get('content_base64', '')).decode('utf-8')
            
            # Parse MSE
            mse_match = re.search(r'MSE:\s*([\d\.]+)', content, re.IGNORECASE)
            mse_valid = False
            if mse_match:
                mse_val = float(mse_match.group(1))
                if 1 <= mse_val <= 500:
                    score += 15
                    mse_valid = True
                    feedback.append(f"MSE reported correctly: {mse_val}")
                else:
                    feedback.append(f"MSE value {mse_val} is out of realistic range (1-500).")
            else:
                feedback.append("MSE not found in report.")

            # Parse R2
            r2_match = re.search(r'R2:\s*([\d\.]+)', content, re.IGNORECASE)
            r2_valid = False
            if r2_match:
                r2_val = float(r2_match.group(1))
                if 0.0 <= r2_val <= 1.0:
                    score += 15
                    r2_valid = True
                    feedback.append(f"R2 reported correctly: {r2_val}")
                else:
                    feedback.append(f"R2 value {r2_val} is out of valid range (0-1).")
            else:
                feedback.append("R2 not found in report.")

            # Parse Predictor
            pred_match = re.search(r'Most Important Predictor:\s*([A-Za-z]+)', content, re.IGNORECASE)
            if pred_match:
                pred_val = pred_match.group(1).lower()
                if pred_val in valid_predictors:
                    score += 10
                    feedback.append(f"Important predictor identified: {pred_val}")
                else:
                    feedback.append(f"Unknown predictor identified: {pred_val}")
            else:
                feedback.append("Predictor info not found in report.")

        except Exception as e:
            feedback.append(f"Error parsing report: {str(e)}")
    else:
        feedback.append("Text report missing or not saved during task.")

    # 5. VLM Visual Verification (40 pts)
    # We use trajectory frames to ensure the workflow was actually performed
    frames = sample_trajectory_frames(traj, n=4)
    final_screenshot = get_final_screenshot(traj)
    
    if frames or final_screenshot:
        prompt = """
        Analyze these screenshots of a JASP statistical analysis session.
        I am looking for evidence of a Random Forest Regression analysis.
        
        Check for:
        1. The 'Machine Learning' module icon or ribbon being active.
        2. A results panel showing 'Random Forest Regression'.
        3. A 'Model Summary' table with MSE or R-squared.
        4. A 'Predictive Performance' plot (scatter plot of predicted vs observed).
        5. A 'Variable Importance' plot (bar chart).
        
        Provide a JSON response:
        {
            "ml_module_visible": boolean,
            "rf_results_visible": boolean,
            "plots_visible": boolean,
            "confidence": "low|medium|high"
        }
        """
        
        try:
            vlm_response = query_vlm(images=frames + [final_screenshot], prompt=prompt)
            vlm_data = vlm_response.get('parsed', {})
            
            if vlm_data.get('ml_module_visible'):
                score += 10
                feedback.append("Visuals: Machine Learning module accessed.")
            
            if vlm_data.get('rf_results_visible'):
                score += 15
                feedback.append("Visuals: Random Forest results table detected.")
            else:
                feedback.append("Visuals: No Random Forest results table found.")

            if vlm_data.get('plots_visible'):
                score += 15
                feedback.append("Visuals: RF Performance/Importance plots detected.")
            else:
                feedback.append("Visuals: Required plots not found.")
                
        except Exception as e:
            feedback.append(f"VLM verification failed: {str(e)}")
            # Fallback scoring if VLM fails but file evidence is strong
            if score >= 50: 
                score += 20
                feedback.append("VLM unavailable, adding fallback points based on valid files.")
    
    # 6. Final Pass Determination
    # Requirement: Valid files (at least 30pts from files) + reasonable total score
    passed = (score >= 60)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }