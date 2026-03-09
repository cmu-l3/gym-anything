#!/usr/bin/env python3
"""
Verifier for assess_overbank_flood_depth task.

Checks:
1. CSV output file exists and was created during the task.
2. CSV format (headers) is correct.
3. Content matches ground truth calculated from HDF file:
    - Correct 5 most upstream stations identified
    - Left Bank Station identification
    - Ground elevation interpolation
    - WSE extraction
    - Depth calculation logic
"""

import json
import csv
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_assess_overbank_flood_depth(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load task metadata tolerances
    metadata = task_info.get('metadata', {})
    tol_elev = metadata.get('tolerance_elevation_ft', 0.1)
    tol_depth = metadata.get('tolerance_depth_ft', 0.1)

    # 1. Retrieve Result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Check File Existence & Timestamp
    if not result_data.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output CSV file not found."}
    
    if not result_data.get("file_created_during_task", False):
        return {"passed": False, "score": 0, "feedback": "Output CSV file was not created/modified during the task session."}

    # 3. Retrieve and Load Ground Truth
    ground_truth = []
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(result_data["ground_truth_path"], temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            ground_truth = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load verification ground truth: {e}"}
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)
            
    if not ground_truth:
        return {"passed": False, "score": 0, "feedback": "System error: Ground truth generation failed."}

    # 4. Retrieve and Load User CSV
    user_rows = []
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    try:
        copy_from_env(result_data["csv_path"], temp_csv.name)
        with open(temp_csv.name, 'r') as f:
            reader = csv.DictReader(f)
            # Normalize headers: strip whitespace, handle case if needed
            if reader.fieldnames:
                reader.fieldnames = [h.strip() for h in reader.fieldnames]
            for row in reader:
                user_rows.append(row)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read output CSV: {e}"}
    finally:
        if os.path.exists(temp_csv.name):
            os.unlink(temp_csv.name)

    # --- SCORING ---
    score = 0
    feedback_parts = []
    
    # Criterion: CSV Format (10 pts)
    required_cols = ["River_Station", "Left_Bank_Station_ft", "Target_Station_ft", "Ground_Elev_ft", "Max_WSE_ft", "Flood_Depth_ft"]
    headers_ok = False
    if user_rows:
        keys = user_rows[0].keys()
        missing = [c for c in required_cols if c not in keys]
        if not missing:
            score += 10
            headers_ok = True
            feedback_parts.append("CSV format correct")
        else:
            feedback_parts.append(f"Missing columns: {missing}")
    else:
        feedback_parts.append("CSV is empty")
        return {"passed": False, "score": 0, "feedback": "CSV file is empty"}

    if not headers_ok:
        return {"passed": False, "score": score, "feedback": ", ".join(feedback_parts)}

    # Map user rows by River Station for comparison
    user_map = {row["River_Station"].strip(): row for row in user_rows if "River_Station" in row}
    
    # Criterion: Correct Cross-Sections (15 pts)
    # Ground truth contains the 5 expected upstream stations
    gt_stations = set(gt["river_station"] for gt in ground_truth)
    user_stations = set(user_map.keys())
    
    common_stations = gt_stations.intersection(user_stations)
    if len(common_stations) == 5:
        score += 15
        feedback_parts.append("Correct cross-sections identified")
    elif len(common_stations) >= 3:
        score += 10
        feedback_parts.append(f"Mostly correct stations ({len(common_stations)}/5)")
    else:
        feedback_parts.append(f"Wrong cross-sections selected (Found {len(common_stations)}/5 expected)")

    # Analyze data accuracy (remaining 75 pts distributed)
    # We sum errors across the 5 stations
    total_stations_checked = 0
    correct_lbs = 0
    correct_ground = 0
    correct_wse = 0
    correct_depth = 0
    
    for gt in ground_truth:
        rs = gt["river_station"]
        if rs not in user_map:
            continue
            
        row = user_map[rs]
        total_stations_checked += 1
        
        try:
            # Bank Station Check
            u_lbs = float(row["Left_Bank_Station_ft"])
            if abs(u_lbs - gt["left_bank_station"]) < 0.1:
                correct_lbs += 1
            
            # Ground Elev Check
            u_ground = float(row["Ground_Elev_ft"])
            if abs(u_ground - gt["ground_elev"]) < tol_elev:
                correct_ground += 1
            elif gt["ground_elev"] == -999.0: # Agent should report invalid/missing
                # Accept anything reasonable if ground truth says it's out of bounds, 
                # but typically this task design ensures they are in bounds.
                pass 
                
            # WSE Check
            u_wse = float(row["Max_WSE_ft"])
            if abs(u_wse - gt["max_wse"]) < 0.1:
                correct_wse += 1
                
            # Depth Check
            u_depth = float(row["Flood_Depth_ft"])
            if abs(u_depth - gt["flood_depth"]) < tol_depth:
                correct_depth += 1
                
        except ValueError:
            pass # Parsing error counts as failure for that point
            
    # Scale points based on count (max 5)
    # Pts: Bank=15, Ground=25, WSE=15, Depth=20
    
    if total_stations_checked > 0:
        score += int(15 * (correct_lbs / 5))
        score += int(25 * (correct_ground / 5))
        score += int(15 * (correct_wse / 5))
        score += int(20 * (correct_depth / 5))
        
        feedback_parts.append(f"Accuracy: Bank {correct_lbs}/5, Ground {correct_ground}/5, WSE {correct_wse}/5, Depth {correct_depth}/5")
    else:
        feedback_parts.append("No matching stations to score data accuracy")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }