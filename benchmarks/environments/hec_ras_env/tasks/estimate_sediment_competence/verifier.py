#!/usr/bin/env python3
"""
Verifier for estimate_sediment_competence task.
"""

import json
import csv
import os
import math
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_sediment_competence(traj, env_info, task_info):
    """
    Verify the sediment competence analysis.
    
    Criteria:
    1. CSV output exists and has correct columns.
    2. Extracted Shear Stress matches Ground Truth (within tolerance).
    3. Critical Diameter calculation is correct based on the formula.
    4. Stability classification is correct based on the threshold (2.0 in).
    5. Summary file identifies the critical station.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Constants from task description
    CONSTANTS = {
        "gamma_w": 62.4,
        "gamma_s": 165.36,
        "tau_star_c": 0.047
    }
    THRESHOLD = 2.0  # inches
    
    # Files to retrieve
    files_to_copy = {
        "result_meta": "/tmp/task_result.json",
        "ground_truth": "/tmp/ground_truth.json",
        "agent_csv": "/tmp/agent_sediment.csv",
        "agent_summary": "/tmp/agent_summary.txt"
    }
    
    data = {}
    
    # Copy files
    with tempfile.TemporaryDirectory() as tmpdir:
        for key, path in files_to_copy.items():
            local_path = os.path.join(tmpdir, key)
            try:
                copy_from_env(path, local_path)
                if os.path.exists(local_path):
                    if key.endswith('json'):
                        with open(local_path, 'r') as f:
                            data[key] = json.load(f)
                    else:
                        # For CSV/TXT, read as text
                        with open(local_path, 'r', encoding='utf-8', errors='ignore') as f:
                            data[key + "_content"] = f.read()
                        data[key + "_path"] = local_path
            except Exception as e:
                logger.warning(f"Could not copy {key}: {e}")

    # --- SCORING ---
    score = 0
    feedback = []
    
    # 1. Check File Existence (20 pts)
    meta = data.get("result_meta", {})
    if meta.get("csv_exists"):
        score += 10
        feedback.append("CSV file created.")
    else:
        feedback.append("CSV file MISSING.")
        return {"passed": False, "score": 0, "feedback": "Main output CSV missing."}
        
    if meta.get("summary_exists"):
        score += 10
        feedback.append("Summary file created.")
    else:
        feedback.append("Summary file missing.")

    # 2. Check CSV Content and Calculations (60 pts)
    # Parse CSV
    agent_data = []
    try:
        csv_path = data.get("agent_csv_path")
        if csv_path:
            with open(csv_path, 'r') as f:
                reader = csv.DictReader(f)
                headers = reader.fieldnames
                # Check columns
                required_cols = ["River_Station", "Shear_Stress_lb_sq_ft", "Critical_Diameter_in", "Stability_Status"]
                if not all(col in headers for col in required_cols):
                    feedback.append(f"Missing required columns. Found: {headers}")
                else:
                    for row in reader:
                        agent_data.append(row)
    except Exception as e:
        feedback.append(f"Error reading CSV: {e}")
        return {"passed": False, "score": score, "feedback": "\n".join(feedback)}

    # Parse Ground Truth
    gt_data = data.get("ground_truth", {}).get("shear_data", {})
    if not gt_data or "error" in data.get("ground_truth", {}):
        feedback.append("Warning: Could not load ground truth data for verification.")
        # Fallback: Check internal consistency only
        gt_data = {} 
    
    valid_rows = 0
    correct_shear = 0
    correct_calc = 0
    correct_logic = 0
    
    total_rows = len(agent_data)
    
    if total_rows == 0:
        feedback.append("CSV is empty.")
    else:
        for row in agent_data:
            rs = row.get("River_Station", "").strip()
            
            try:
                # 2a. Verify Shear Stress Extraction (vs Ground Truth)
                shear_val = float(row.get("Shear_Stress_lb_sq_ft", 0))
                
                if rs in gt_data:
                    gt_shear = gt_data[rs]
                    # Tolerance 5%
                    if math.isclose(shear_val, gt_shear, rel_tol=0.05):
                        correct_shear += 1
                elif not gt_data:
                    # If GT failed, skip this check
                    correct_shear += 1 
                
                # 2b. Verify Calculation (Internal Consistency)
                # Dc = [ Shear / (0.047 * (165.36 - 62.4)) ] * 12
                # Denom = 0.047 * 102.96 = 4.83912
                # Factor = 12 / 4.83912 = 2.47979
                
                expected_dc = shear_val * 2.47979
                agent_dc = float(row.get("Critical_Diameter_in", 0))
                
                if math.isclose(agent_dc, expected_dc, rel_tol=0.02):
                    correct_calc += 1
                
                # 2c. Verify Classification Logic
                status = row.get("Stability_Status", "").upper()
                expected_status = "UNSTABLE" if agent_dc > THRESHOLD else "STABLE"
                
                if status == expected_status:
                    correct_logic += 1
                
                valid_rows += 1
                
            except ValueError:
                continue

        # Award points based on percentage of valid rows
        if valid_rows > 0:
            # Shear Stress Accuracy (20 pts)
            if correct_shear / valid_rows > 0.8: score += 20
            elif correct_shear / valid_rows > 0.5: score += 10
            
            # Formula Accuracy (20 pts)
            if correct_calc / valid_rows > 0.9: score += 20
            elif correct_calc / valid_rows > 0.5: score += 10
            
            # Logic Accuracy (20 pts)
            if correct_logic / valid_rows > 0.9: score += 20
            elif correct_logic / valid_rows > 0.5: score += 10
            
            feedback.append(f"Analyzed {valid_rows} rows. Shear Accuracy: {correct_shear}/{valid_rows}. Calc Accuracy: {correct_calc}/{valid_rows}. Logic: {correct_logic}/{valid_rows}.")
        else:
            feedback.append("No valid numeric data found in CSV rows.")

    # 3. Check Summary File (20 pts)
    summary_content = data.get("agent_summary_content", "")
    if summary_content:
        # Check if it mentions a river station
        # We need to know which one is actually max.
        if gt_data:
            max_rs = max(gt_data, key=gt_data.get)
            if max_rs in summary_content or max_rs.replace(" ", "") in summary_content.replace(" ", ""):
                score += 20
                feedback.append(f"Summary correctly identified max shear station: {max_rs}")
            else:
                feedback.append(f"Summary failed to identify max shear station ({max_rs}).")
                score += 5 # Partial credit for existence
        else:
             score += 10 # Credit for existence if GT missing
    
    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback)
    }