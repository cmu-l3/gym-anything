#!/usr/bin/env python3
import json
import os
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

def verify_meuse_kriging_spatial(traj, env_info, task_info):
    """
    Verifies the Meuse Kriging Spatial task.
    
    Scoring Breakdown (100 pts):
    1. Variogram Model CSV (20 pts): Exists, new, plausible values.
    2. Kriging Predictions CSV (25 pts): Exists, new, correct ~3103 rows.
    3. Cross-Validation CSV (20 pts): Exists, new, correct ~155 rows.
    4. Map Image (20 pts): Exists, new, size check.
    5. R Script (15 pts): Exists, modified, contains key function calls.
    
    Pass Threshold: 60 pts.
    """
    
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    score = 0
    feedback = []
    
    # --- Criterion 1: Variogram CSV (20 pts) ---
    var = data.get('variogram', {})
    var_info = var.get('info', {})
    
    if var.get('exists') and var.get('is_new'):
        score += 8
        feedback.append("Variogram CSV created (+8)")
        
        if var_info.get('valid') and var_info.get('has_cols'):
            score += 6
            feedback.append("Variogram CSV has valid format (+6)")
            
            # Value checks (Physical plausibility)
            # Nugget for log(zinc) is usually small (< 0.2)
            # Range is usually between 200m and 2000m
            nug = var_info.get('nugget', 999)
            rng = var_info.get('range', 0)
            
            if 0 <= nug <= 0.5 and 100 <= rng <= 3000:
                score += 6
                feedback.append(f"Variogram params plausible (nug={nug:.2f}, rng={rng:.0f}) (+6)")
            else:
                feedback.append(f"Variogram params suspicious (nug={nug:.2f}, rng={rng:.0f})")
        else:
            feedback.append("Variogram CSV missing required columns/invalid")
    else:
        feedback.append("Variogram CSV not found or not new")

    # --- Criterion 2: Kriging Predictions CSV (25 pts) ---
    pred = data.get('predictions', {})
    pred_info = pred.get('info', {})
    
    if pred.get('exists') and pred.get('is_new'):
        score += 8
        feedback.append("Prediction CSV created (+8)")
        
        # Row count check (meuse.grid has 3103 rows)
        rows = pred_info.get('rows', 0)
        if 2800 <= rows <= 3400:
            score += 10
            feedback.append(f"Prediction grid size correct ({rows} rows) (+10)")
        else:
            feedback.append(f"Prediction grid size incorrect ({rows} rows, exp ~3103)")
            
        if pred_info.get('has_pred') and pred_info.get('has_var'):
            score += 7
            feedback.append("Prediction CSV has pred/var columns (+7)")
    else:
        feedback.append("Prediction CSV not found")

    # --- Criterion 3: Cross-Validation CSV (20 pts) ---
    cv = data.get('cv', {})
    cv_info = cv.get('info', {})
    
    if cv.get('exists') and cv.get('is_new'):
        score += 8
        feedback.append("CV results created (+8)")
        
        # Row count check (meuse has 155 obs)
        rows = cv_info.get('rows', 0)
        if 150 <= rows <= 160:
            score += 7
            feedback.append(f"CV row count correct ({rows}) (+7)")
        else:
            feedback.append(f"CV row count incorrect ({rows})")
            
        # Residual check (mean residual should be close to 0 for unbiased kriging)
        mean_res = abs(cv_info.get('mean_residual', 999))
        if mean_res < 0.2:
            score += 5
            feedback.append("CV residuals indicate unbiased model (+5)")
        else:
            feedback.append(f"High mean residual ({mean_res:.2f})")
    else:
        feedback.append("CV results not found")

    # --- Criterion 4: Map Image (20 pts) ---
    map_res = data.get('map', {})
    
    if map_res.get('exists') and map_res.get('is_new'):
        score += 10
        feedback.append("Map image created (+10)")
        
        size_kb = map_res.get('size', 0) / 1024
        if size_kb > 50:
            score += 10
            feedback.append(f"Map image size substantial ({int(size_kb)}KB) (+10)")
        elif size_kb > 10:
            score += 5
            feedback.append("Map image small but exists (+5)")
        else:
            feedback.append("Map image extremely small/empty")
            
        # Optional: VLM Check here if we want to be strict about the 4 panels
        # But for now file size is a decent proxy for "not empty"
    else:
        feedback.append("Map image not found")

    # --- Criterion 5: R Script (15 pts) ---
    script = data.get('script', {})
    if script.get('exists') and script.get('is_new'):
        score += 5
        feedback.append("Analysis script modified (+5)")
        
        if script.get('has_keywords'):
            score += 10
            feedback.append("Script contains kriging functions (+10)")
        else:
            feedback.append("Script missing 'variogram' or 'krige' calls")
    else:
        feedback.append("Script not found or not modified")
        
    # --- Final VLM Verification (Safety Check) ---
    # We define a "fail" condition if the score is high but VLM sees nothing relevant
    # Only run if passing to verify
    if score >= 60 and env_info.get('query_vlm'):
        query_vlm = env_info.get('query_vlm')
        frames = sample_trajectory_frames(traj, 5)
        final_shot = get_final_screenshot(traj)
        
        # Check if RStudio is actually visible doing work
        prompt = "Is RStudio visible in these images? Do you see code or plots related to spatial data or maps?"
        vlm_res = query_vlm(prompt=prompt, images=frames + [final_shot])
        
        # If VLM explicitly says NO meaningful content, we might flag it
        # (Implementation omitted for brevity, relying on file artifacts primarily)

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }