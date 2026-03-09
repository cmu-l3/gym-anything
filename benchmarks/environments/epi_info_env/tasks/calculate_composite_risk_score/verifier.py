#!/usr/bin/env python3
import json
import os
import tempfile
import pandas as pd
import numpy as np
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

def verify_calculate_composite_risk_score(traj, env_info, task_info):
    """
    Verifies that the agent correctly calculated the clinical risk score.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    score = 0
    feedback = []
    
    # 1. Retrieve Result JSON
    fd, json_path = tempfile.mkstemp(suffix='.json')
    os.close(fd)
    try:
        copy_from_env("C:\\tmp\\task_result.json", json_path)
        with open(json_path, 'r') as f:
            result_meta = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task metadata: {e}"}
    finally:
        if os.path.exists(json_path): os.unlink(json_path)

    # 2. Retrieve Data Files (Input and Output)
    input_tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.csv').name
    output_tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.csv').name
    
    try:
        # Get Input Data (Ground Truth)
        copy_from_env("C:\\Users\\Docker\\Documents\\TaskData\\cleveland_heart_clean.csv", input_tmp)
        df_truth = pd.read_csv(input_tmp)
        
        # Get Agent Output
        if result_meta.get('output_exists'):
            copy_from_env("C:\\Users\\Docker\\Documents\\TaskData\\patient_risk_scores.csv", output_tmp)
            df_agent = pd.read_csv(output_tmp)
            agent_file_valid = True
            score += 20 # File created
            feedback.append("Output file created.")
        else:
            df_agent = None
            agent_file_valid = False
            feedback.append("Output file not found.")

    except Exception as e:
        feedback.append(f"Error reading data files: {e}")
        agent_file_valid = False

    # 3. Calculate Expected Scores (Re-implement logic)
    # Logic: Age>=60 (+2) else Age>=45 (+1); Sex=1 (+1); Chol>=240 (+1); SysBP>=140 (+1)
    if df_truth is not None and not df_truth.empty:
        expected_scores = []
        for _, row in df_truth.iterrows():
            s = 0
            # Age
            if row['Age'] >= 60:
                s += 2
            elif row['Age'] >= 45:
                s += 1
            # Sex
            if row['Sex'] == 1:
                s += 1
            # Chol
            if row['Cholesterol'] >= 240:
                s += 1
            # BP
            if row['SysBP'] >= 140:
                s += 1
            expected_scores.append(s)
        
        df_truth['ExpectedRisk'] = expected_scores
    
    # 4. Compare Values
    if agent_file_valid and df_agent is not None:
        # Check columns
        if 'PatientID' in df_agent.columns and 'RiskScore' in df_agent.columns:
            score += 10
            feedback.append("Correct columns found.")
            
            # Merge to compare
            try:
                # Ensure types
                df_agent['PatientID'] = pd.to_numeric(df_agent['PatientID'], errors='coerce')
                df_agent['RiskScore'] = pd.to_numeric(df_agent['RiskScore'], errors='coerce')
                
                merged = pd.merge(df_truth, df_agent, on='PatientID', how='inner', suffixes=('_true', '_agent'))
                
                if len(merged) < len(df_truth) * 0.9:
                    feedback.append(f"Warning: Output contains only {len(merged)}/{len(df_truth)} records.")
                else:
                    score += 10 # Completeness
                
                # Compare scores
                matches = merged['ExpectedRisk'] == merged['RiskScore']
                accuracy = matches.mean()
                
                if accuracy >= 0.95:
                    score += 50
                    feedback.append(f"Risk scores are accurate ({accuracy:.1%}).")
                elif accuracy >= 0.70:
                    score += 25
                    feedback.append(f"Risk scores are partially accurate ({accuracy:.1%}). Check logic.")
                else:
                    feedback.append(f"Risk scores are inaccurate ({accuracy:.1%}).")
                    
            except Exception as e:
                feedback.append(f"Error comparing data: {e}")
        else:
            feedback.append("Missing required columns (PatientID, RiskScore).")
    
    # 5. VLM Verification (Workflow)
    # We want to see the Classic Analysis window and PGM editor usage
    frames = sample_trajectory_frames(traj, n=5)
    final_screen = get_final_screenshot(traj)
    
    vlm_prompt = """
    You are verifying an Epi Info 7 task. The user should be using the 'Classic Analysis' module.
    
    Look for:
    1. The 'Classic Analysis' window (often has a command tree on the left, output area on right).
    2. Commands like 'READ', 'DEFINE', 'ASSIGN', 'IF', or 'WRITE' in the program editor or log.
    3. A spreadsheet-like view of data.
    
    Does the user appear to be performing data analysis or writing a script?
    """
    
    vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
    
    if vlm_result.get("success") and "yes" in vlm_result.get("result", "").lower():
        score += 10
        feedback.append("VLM confirms analysis workflow.")
    
    # Clean up
    if os.path.exists(input_tmp): os.unlink(input_tmp)
    if os.path.exists(output_tmp): os.unlink(output_tmp)

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }