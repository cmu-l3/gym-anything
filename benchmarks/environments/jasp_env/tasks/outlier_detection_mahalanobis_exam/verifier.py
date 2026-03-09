#!/usr/bin/env python3
import json
import os
import tempfile
import zipfile
import pandas as pd
import numpy as np
from scipy.spatial import distance

def verify_outlier_detection(traj, env_info, task_info):
    """
    Verifies the JASP Outlier Detection task.
    
    Steps:
    1. Replicate ground truth calculation of Mahalanobis distance on 'ExamAnxiety.csv'.
    2. Check if agent's reported outlier ID matches ground truth.
    3. Verify JASP file exists, is a valid zip, and contains Linear Regression analysis with Mahalanobis enabled.
    """
    
    # 1. Setup and Copy Files
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    temp_dir = tempfile.mkdtemp()
    result_json_path = os.path.join(temp_dir, "task_result.json")
    jasp_file_path = os.path.join(temp_dir, "OutlierAnalysis.jasp")
    dataset_path = os.path.join(temp_dir, "ExamAnxiety.csv")
    
    try:
        # Copy basic result info
        copy_from_env("/tmp/task_result.json", result_json_path)
        with open(result_json_path, 'r') as f:
            result_data = json.load(f)
            
        # Copy Dataset for Ground Truth Calculation
        copy_from_env(result_data.get("dataset_path", "/home/ga/Documents/JASP/ExamAnxiety.csv"), dataset_path)
        
        # Copy JASP output file if it exists
        if result_data.get("jasp_file_exists"):
            copy_from_env(result_data.get("jasp_file_path"), jasp_file_path)
            
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task files: {str(e)}"}

    # 2. Ground Truth Calculation
    try:
        df = pd.read_csv(dataset_path)
        # Mahalanobis requires numeric data. Predictors: Anxiety, Revise
        predictors = df[['Anxiety', 'Revise']].dropna()
        
        # Calculate Mahalanobis Distance
        # D^2 = (x - mu)^T * S^-1 * (x - mu)
        cov_inv = np.linalg.inv(predictors.cov())
        mean = predictors.mean()
        
        def calculate_mahal(row):
            diff = row - mean
            return np.dot(np.dot(diff, cov_inv), diff.T)
            
        df['mahal'] = predictors.apply(calculate_mahal, axis=1)
        
        # Find max
        max_row = df.loc[df['mahal'].idxmax()]
        ground_truth_code = str(max_row['Code']).strip()
        
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verifier Error: Could not calculate ground truth: {str(e)}"}

    # 3. Scoring
    score = 0
    feedback = []
    
    # Criterion A: Report File Content (40 pts)
    agent_answer = str(result_data.get("report_content", "")).strip()
    if agent_answer == ground_truth_code:
        score += 40
        feedback.append(f"Correct outlier identified (Code: {ground_truth_code}).")
    else:
        feedback.append(f"Incorrect outlier ID. Expected: {ground_truth_code}, Got: '{agent_answer}'.")

    # Criterion B: JASP File Analysis (60 pts)
    jasp_valid = False
    analysis_found = False
    mahalanobis_enabled = False
    
    if result_data.get("jasp_file_exists") and result_data.get("jasp_file_created_during_task"):
        try:
            if zipfile.is_zipfile(jasp_file_path):
                jasp_valid = True
                score += 10 # File validity
                
                with zipfile.ZipFile(jasp_file_path, 'r') as z:
                    # JASP stores analysis specs in embedded JSONs, usually inside the zip structure
                    # We look for files ending in .json within the archive
                    for filename in z.namelist():
                        if filename.endswith("results.json") or filename.endswith("analysis.json") or filename == "index.json":
                            try:
                                content = json.loads(z.read(filename).decode('utf-8'))
                                # Search recursively for "Regression" and "mahalanobis"
                                content_str = json.dumps(content).lower()
                                
                                if "regression" in content_str and "linear" in content_str:
                                    analysis_found = True
                                
                                # Check for Mahalanobis toggle
                                # Keys might vary by version, but usually contains "mahalanobis" in options
                                if "mahalanobis" in content_str or "mahalanobisdistance" in content_str:
                                    mahalanobis_enabled = True
                            except:
                                continue
            else:
                feedback.append("JASP file is not a valid zip archive.")
        except Exception as e:
            feedback.append(f"Error inspecting JASP file: {str(e)}")
    
    if jasp_valid:
        if analysis_found:
            score += 20
            feedback.append("Linear Regression analysis found.")
        else:
            feedback.append("Linear Regression analysis NOT found in file.")
            
        if mahalanobis_enabled:
            score += 30
            feedback.append("Mahalanobis distance option verified.")
        else:
            feedback.append("Mahalanobis distance option NOT enabled in analysis settings.")
    else:
        feedback.append("JASP file not saved or invalid.")

    # 4. Final Result
    passed = (score >= 70) and (agent_answer == ground_truth_code)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }