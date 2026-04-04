#!/usr/bin/env python3
"""
Verifier for validate_model_calibration task.
Checks if the agent correctly extracted model results, calculated RMSE, and generated reports.
"""

import json
import os
import math
import logging
import csv
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_model_calibration(traj, env_info, task_info):
    """
    Verify the forensic calibration task.
    
    Criteria:
    1. CSV Output exists and was created during task. (10 pts)
    2. Model Extraction Accuracy: Agent's extracted Model WSE matches Ground Truth. (30 pts)
    3. Math Accuracy: Agent's calculated Residuals and RMSE match the data. (20 pts)
    4. Station Matching: Agent correctly matched observed stations to model stations. (20 pts)
    5. Plot exists. (10 pts)
    6. Summary text exists and contains RMSE. (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # 1. Retrieve Result JSON and Files
    temp_result_json = tempfile.mktemp(suffix=".json")
    temp_csv = tempfile.mktemp(suffix=".csv")
    temp_gt = tempfile.mktemp(suffix=".json")
    
    try:
        copy_from_env("/tmp/task_result.json", temp_result_json)
        with open(temp_result_json, 'r') as f:
            result_data = json.load(f)
            
        # Get paths to exported files inside container (for reference, though we need to copy them out)
        # The export script copied them to /tmp/verifier_files/ inside container
        # We need to copy specific filenames based on the json mapping
        
        files_map = result_data.get("files", {})
        
        # Copy Agent CSV
        has_csv = False
        if "analysis_csv" in files_map:
            # Note: copy_from_env takes (container_path, local_path)
            # The JSON contains the container path where export_result.sh put it
            copy_from_env(files_map["analysis_csv"], temp_csv)
            has_csv = True
            
        # Copy Ground Truth
        has_gt = False
        if "ground_truth" in files_map:
            copy_from_env(files_map["ground_truth"], temp_gt)
            has_gt = True
            
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve results: {str(e)}"}

    score = 0
    feedback = []
    
    # --- Check 1: Artifact Existence (30 pts total) ---
    if result_data.get("csv_created"):
        score += 10
        feedback.append("Analysis CSV created.")
    else:
        feedback.append("Analysis CSV missing.")

    if result_data.get("plot_created"):
        score += 10
        feedback.append("Calibration plot created.")
    else:
        feedback.append("Calibration plot missing.")

    if result_data.get("txt_created"):
        score += 10
        feedback.append("Summary text created.")
    else:
        feedback.append("Summary text missing.")

    # --- Check 2: Data Accuracy (70 pts total) ---
    if has_csv and has_gt:
        try:
            # Load Ground Truth
            with open(temp_gt, 'r') as f:
                gt_data = json.load(f)
            
            gt_points = {str(p['station']): p for p in gt_data['points']}
            expected_rmse = gt_data['expected_rmse']
            
            # Load Agent CSV
            agent_points = {}
            with open(temp_csv, 'r') as f:
                reader = csv.DictReader(f)
                headers = reader.fieldnames
                # Verify headers loosely
                required_cols = ['River_Station', 'Model_Max_WSE', 'Residual']
                if not all(any(h.lower() == r.lower() for h in headers) for r in required_cols):
                    feedback.append("CSV missing required columns.")
                
                for row in reader:
                    # Normalize keys
                    row_norm = {k.strip(): v for k, v in row.items()}
                    # Find station key
                    st_key = next((k for k in row_norm.keys() if 'station' in k.lower()), None)
                    wse_key = next((k for k in row_norm.keys() if 'model' in k.lower() and 'wse' in k.lower()), None)
                    
                    if st_key and wse_key:
                        agent_points[str(row_norm[st_key])] = float(row_norm[wse_key])
            
            # Verify Matching and Extraction
            matched_count = 0
            extraction_errors = []
            
            for st, gt_p in gt_points.items():
                if st in agent_points:
                    matched_count += 1
                    agent_val = agent_points[st]
                    gt_val = gt_p['model_wse']
                    if abs(agent_val - gt_val) > 0.05:
                        extraction_errors.append(f"{st}: Agent {agent_val} != GT {gt_val}")
            
            # Score Matching (20 pts)
            if matched_count >= len(gt_points) - 1: # Allow 1 miss
                score += 20
                feedback.append("River stations matched correctly.")
            elif matched_count > 0:
                score += int(20 * (matched_count / len(gt_points)))
                feedback.append(f"Partial station match ({matched_count}/{len(gt_points)}).")
            else:
                feedback.append("No stations matched correctly.")

            # Score Extraction Accuracy (30 pts)
            if len(extraction_errors) == 0 and matched_count > 0:
                score += 30
                feedback.append("Model results extracted accurately.")
            elif matched_count > 0:
                # Partial credit based on error rate
                err_rate = len(extraction_errors) / matched_count
                pts = max(0, 30 * (1 - err_rate))
                score += int(pts)
                feedback.append(f"Extraction errors found in {len(extraction_errors)} stations.")
                
            # Score RMSE Reporting (20 pts)
            reported_txt = result_data.get("rmse_reported_text", "")
            # Try to find a float in the text
            import re
            floats = re.findall(r"[-+]?\d*\.\d+|\d+", reported_txt)
            rmse_correct = False
            if floats:
                for num in floats:
                    try:
                        val = float(num)
                        if abs(val - expected_rmse) < 0.1: # 0.1 ft tolerance
                            rmse_correct = True
                            break
                    except:
                        continue
            
            if rmse_correct:
                score += 20
                feedback.append(f"RMSE calculated correctly ({expected_rmse:.3f}).")
            else:
                feedback.append(f"RMSE incorrect or not found in summary. Expected ~{expected_rmse:.3f}")
                
        except Exception as e:
            feedback.append(f"Error verifying data: {str(e)}")
            logger.exception("Verification error")
    else:
        feedback.append("Cannot verify accuracy - CSV or Ground Truth missing.")

    # Cleanup
    for f in [temp_result_json, temp_csv, temp_gt]:
        if os.path.exists(f):
            os.remove(f)

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }