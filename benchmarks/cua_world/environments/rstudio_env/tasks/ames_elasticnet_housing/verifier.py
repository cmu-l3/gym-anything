#!/usr/bin/env python3
"""
Verifier for Ames Elastic Net Housing Task
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_ames_elasticnet(traj, env_info, task_info):
    """
    Verify the Ames Housing Elastic Net task.
    """
    # 1. Load result JSON from container
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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

    # 2. VLM Verification
    query_vlm = env_info.get('query_vlm')
    vlm_score = 0
    vlm_feedback = ""
    
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final_screen = get_final_screenshot(traj)
        
        prompt = """
        You are verifying a data science task in RStudio.
        
        1. Look at the trajectory: Did the user install packages and write R code?
        2. Look at the final screenshot: Is there a multi-panel plot visible (diagnostic plots)?
        
        Return JSON:
        {
            "code_writing_visible": boolean,
            "diagnostic_plot_visible": boolean,
            "plot_quality": "low" | "medium" | "high"
        }
        """
        
        try:
            vlm_resp = query_vlm(images=frames + [final_screen], prompt=prompt)
            parsed = vlm_resp.get('parsed', {})
            
            if parsed.get('code_writing_visible'):
                vlm_score += 10
                vlm_feedback += "VLM confirmed code writing. "
            
            if parsed.get('diagnostic_plot_visible'):
                vlm_score += 10
                vlm_feedback += "VLM confirmed diagnostic plot visibility. "
                
        except Exception as e:
            logger.error(f"VLM error: {e}")

    # 3. Scoring Logic
    score = 0
    feedback = []

    # Criterion 1: Preprocessing Summary (15 pts)
    if result.get('preproc_exists'):
        if result.get('preproc_rows', 0) >= 20:
            score += 15
            feedback.append("Preprocessing summary created and sufficient (15/15)")
        else:
            score += 5
            feedback.append("Preprocessing summary incomplete (<20 rows) (5/15)")
    else:
        feedback.append("Preprocessing summary missing (0/15)")

    # Criterion 2: Model Comparison (25 pts)
    if result.get('model_exists'):
        if result.get('model_rows', 0) >= 4: # Header + 3 rows
            score += 10
            feedback.append("Model comparison CSV exists (10/10)")
            
            if result.get('rmse_valid'):
                score += 10
                feedback.append("RMSE values in plausible range (10/10)")
            else:
                feedback.append("RMSE values implausible (0/10)")
                
            if result.get('sparsity_valid'):
                score += 5
                feedback.append("Sparsity ordering correct (5/5)")
            else:
                feedback.append("Sparsity ordering unusual (0/5)")
        else:
            feedback.append("Model comparison CSV missing rows (0/25)")
    else:
        feedback.append("Model comparison CSV missing (0/25)")

    # Criterion 3: Top Predictors (15 pts)
    if result.get('predictors_exists'):
        score += 5
        if result.get('has_key_predictor'):
            score += 10
            feedback.append("Top predictors CSV valid and contains key features (15/15)")
        else:
            feedback.append("Top predictors CSV misses key features (Overall_Qual/Gr_Liv_Area) (5/15)")
    else:
        feedback.append("Top predictors CSV missing (0/15)")

    # Criterion 4: Diagnostic Plot (15 pts)
    if result.get('plot_exists'):
        kb = result.get('plot_size_kb', 0)
        if kb > 30:
            score += 15
            feedback.append("Diagnostic plot created and valid size (15/15)")
        else:
            score += 5
            feedback.append(f"Diagnostic plot too small ({kb}KB) (5/15)")
    else:
        feedback.append("Diagnostic plot missing (0/15)")

    # Criterion 5: Script (10 pts)
    if result.get('script_modified') and result.get('script_has_glmnet'):
        score += 10
        feedback.append("R script modified and uses glmnet (10/10)")
    else:
        feedback.append("R script missing or empty (0/10)")

    # Add VLM score (20 pts max)
    score += vlm_score
    feedback.append(vlm_feedback)

    # Final check
    passed = score >= 60 and result.get('model_exists')
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback)
    }