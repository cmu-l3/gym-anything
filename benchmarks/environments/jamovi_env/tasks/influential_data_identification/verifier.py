#!/usr/bin/env python3
import json
import os
import base64
import re
import pandas as pd
import numpy as np
import statsmodels.api as sm
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_influential_data(traj, env_info, task_info):
    """
    Verifies the influential data identification task.
    
    Strategy:
    1. Calculate Ground Truth: Load the dataset (via copy_from_env) and compute OLS + Cook's Distance.
    2. Parse Agent Report: Extract R^2, Max Cook's, and Student Code.
    3. Compare: Strict numerical comparison with tolerance.
    4. Anti-gaming: Ensure files were created during the task.
    5. VLM: Verify process via trajectory (optional but good for 'do nothing' detection).
    """
    
    # 1. Setup and helper access
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # Load result JSON
    import tempfile
    with tempfile.NamedTemporaryFile(suffix=".json") as f_json:
        try:
            copy_from_env("/tmp/task_result.json", f_json.name)
            f_json.seek(0)
            result_data = json.load(f_json)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {e}"}

    # 2. Retrieve Dataset for Ground Truth Calculation
    # We copy the exact file used in the env to ensure consistency
    dataset_path = result_data.get("dataset_path", "/home/ga/Documents/Jamovi/ExamAnxiety.csv")
    with tempfile.NamedTemporaryFile(suffix=".csv") as f_csv:
        try:
            copy_from_env(dataset_path, f_csv.name)
            df = pd.read_csv(f_csv.name)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve dataset for verification: {e}"}

    # 3. Calculate Ground Truth
    try:
        # Preprocessing: Ensure numeric types
        df['Exam'] = pd.to_numeric(df['Exam'], errors='coerce')
        df['Anxiety'] = pd.to_numeric(df['Anxiety'], errors='coerce')
        df['Revise'] = pd.to_numeric(df['Revise'], errors='coerce')
        df = df.dropna(subset=['Exam', 'Anxiety', 'Revise'])

        # Fit Model: Exam ~ Anxiety + Revise
        X = df[['Anxiety', 'Revise']]
        X = sm.add_constant(X)
        y = df['Exam']
        
        model = sm.OLS(y, X).fit()
        
        # Calculate Cook's Distance
        influence = model.get_influence()
        cooks_d = influence.cooks_distance[0]
        
        # Find Max
        max_idx = np.argmax(cooks_d)
        max_cooks_val = cooks_d[max_idx]
        
        # Get Student Code associated with max index
        # Reset index to match array position if necessary, but iloc should work
        influential_student_code = str(df.iloc[max_idx]['Code'])
        r_squared_truth = model.rsquared

        logger.info(f"Ground Truth - Student: {influential_student_code}, Cooks: {max_cooks_val}, R2: {r_squared_truth}")

    except Exception as e:
        logger.error(f"Ground truth calculation failed: {e}")
        return {"passed": False, "score": 0, "feedback": "Verification error: Could not calculate ground truth statistics."}

    # 4. Parse Agent Report
    score = 0
    feedback = []
    
    if not result_data.get("report_exists"):
        return {"passed": False, "score": 0, "feedback": "Report file not found."}
    
    if not result_data.get("report_created_during_task"):
        feedback.append("Warning: Report file timestamp predates task start (possible anti-gaming violation).")
    else:
        score += 10 # Points for creating file
        
    try:
        content_b64 = result_data.get("report_content_b64", "")
        content = base64.b64decode(content_b64).decode('utf-8')
        
        # Extract values using regex
        r2_match = re.search(r"model_r_squared:\s*([\d\.]+)", content)
        cooks_match = re.search(r"max_cooks_distance:\s*([\d\.]+)", content)
        code_match = re.search(r"student_code:\s*(.+)", content)
        
        agent_r2 = float(r2_match.group(1)) if r2_match else None
        agent_cooks = float(cooks_match.group(1)) if cooks_match else None
        agent_code = code_match.group(1).strip() if code_match else None
        
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to parse report content: {e}"}

    # 5. Score Comparison
    
    # R-Squared (20 pts)
    if agent_r2 is not None and abs(agent_r2 - r_squared_truth) < 0.01:
        score += 20
        feedback.append(f"R-Squared correct ({agent_r2}).")
    else:
        feedback.append(f"R-Squared incorrect. Expected ~{r_squared_truth:.3f}, got {agent_r2}.")

    # Max Cook's Distance (30 pts)
    if agent_cooks is not None and abs(agent_cooks - max_cooks_val) < 0.01:
        score += 30
        feedback.append(f"Max Cook's Distance correct ({agent_cooks}).")
    else:
        feedback.append(f"Max Cook's Distance incorrect. Expected ~{max_cooks_val:.3f}, got {agent_cooks}.")

    # Student Code (30 pts)
    if agent_code and str(agent_code) == influential_student_code:
        score += 30
        feedback.append(f"Identified correct student ({agent_code}).")
    else:
        feedback.append(f"Identified wrong student. Expected {influential_student_code}, got {agent_code}.")

    # Project File Existence (10 pts)
    if result_data.get("project_exists"):
        score += 10
        feedback.append("Project file saved.")
    else:
        feedback.append("Project file (.omv) not saved.")

    # 6. VLM Verification (Safety check)
    # Ensure they didn't just write a file without using the software
    frames = sample_trajectory_frames(traj, n=3)
    final_screen = get_final_screenshot(traj)
    
    # Simple check: did they open the regression panel?
    vlm_result = query_vlm(
        images=frames + [final_screen],
        prompt="Did the user interact with the 'Regression' or 'Analysis' menus in Jamovi, and is a data spreadsheet visible? Respond with a JSON object: {'analysis_attempted': boolean}."
    )
    
    if vlm_result.get("success"):
        if not vlm_result['parsed'].get('analysis_attempted', True):
            score = max(0, score - 20) # Penalize if it looks like they faked it
            feedback.append("VLM penalty: No visual evidence of analysis interaction.")
    
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }