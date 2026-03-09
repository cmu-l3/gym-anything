#!/usr/bin/env python3
"""
Verifier for compute_flood_arrival_time task.

Verification Logic:
1. Load Agent CSV and Ground Truth CSV.
2. Verify Column structure.
3. Compare Invert Elevations (verifies correct geometry extraction).
4. Compare Arrival Times (verifies correct time-series analysis and logic).
5. Anti-gaming: File creation time and completeness.
"""

import json
import csv
import os
import shutil
import tempfile
import math
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_compute_flood_arrival_time(traj, env_info, task_info):
    """
    Verify the agent's flood arrival time calculation against ground truth.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy failed"}

    score = 0
    feedback = []
    
    # Temp directory for processing
    temp_dir = tempfile.mkdtemp()
    
    try:
        # 1. Fetch files
        agent_csv_path = os.path.join(temp_dir, "agent_output.csv")
        gt_csv_path = os.path.join(temp_dir, "ground_truth.csv")
        result_json_path = os.path.join(temp_dir, "result.json")
        
        try:
            copy_from_env("/tmp/task_result/agent_output.csv", agent_csv_path)
            copy_from_env("/tmp/task_result/ground_truth.csv", gt_csv_path)
            copy_from_env("/tmp/task_result/result.json", result_json_path)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result files: {str(e)}"}
            
        # 2. Check Result JSON Metadata
        try:
            with open(result_json_path, 'r') as f:
                meta = json.load(f)
        except:
            meta = {}
            
        if not meta.get("output_exists", False):
            return {"passed": False, "score": 0, "feedback": "Output CSV file not found."}
            
        if not meta.get("created_during_task", False):
            feedback.append("WARNING: Output file timestamp indicates it wasn't created during the task window.")
            # We penalize but don't fail immediately if content is perfect (could be clock skew, though unlikely)
            score -= 20 
        else:
            score += 10 # File created correctly
            
        # 3. Load and Compare Data
        try:
            agent_data = load_csv_to_dict(agent_csv_path)
            gt_data = load_csv_to_dict(gt_csv_path)
        except Exception as e:
            return {"passed": False, "score": score, "feedback": f"Failed to parse CSV files: {str(e)}"}
            
        if not agent_data:
            return {"passed": False, "score": score, "feedback": "Agent CSV is empty or malformed."}
            
        # Check Columns
        required_cols = {'River_Station', 'Invert_Elev_ft', 'Arrival_Time_hrs'}
        first_row = list(agent_data.values())[0]
        if not required_cols.issubset(first_row.keys()):
            return {
                "passed": False, 
                "score": score, 
                "feedback": f"Missing required columns. Found: {list(first_row.keys())}, Expected: {required_cols}"
            }
        score += 10 # Columns correct
        
        # Compare Rows
        matches_invert = 0
        matches_time = 0
        total_rows = len(gt_data)
        
        # We allow for some floating point tolerance
        TOL_INVERT = 0.1 # ft
        TOL_TIME = 0.2   # hours (approx 12 min)
        
        missing_stations = 0
        
        for rs, gt_row in gt_data.items():
            if rs not in agent_data:
                missing_stations += 1
                continue
                
            agent_row = agent_data[rs]
            
            # Check Invert
            try:
                ag_inv = float(agent_row['Invert_Elev_ft'])
                gt_inv = float(gt_row['Invert_Elev_ft'])
                if abs(ag_inv - gt_inv) <= TOL_INVERT:
                    matches_invert += 1
            except ValueError:
                pass
                
            # Check Time
            try:
                ag_time = float(agent_row['Arrival_Time_hrs'])
                gt_time = float(gt_row['Arrival_Time_hrs'])
                
                # Handle -1 case (no flood)
                if gt_time < 0:
                    if ag_time < 0 or ag_time == -1:
                        matches_time += 1
                else:
                    if abs(ag_time - gt_time) <= TOL_TIME:
                        matches_time += 1
            except ValueError:
                pass

        # Calculate Scores
        # Invert Accuracy (30 pts max)
        invert_pct = matches_invert / total_rows if total_rows > 0 else 0
        score += int(30 * invert_pct)
        
        # Time Accuracy (50 pts max)
        time_pct = matches_time / total_rows if total_rows > 0 else 0
        score += int(50 * time_pct)
        
        feedback.append(f"Analyzed {total_rows} cross-sections.")
        feedback.append(f"Invert Elevation Accuracy: {invert_pct:.1%}")
        feedback.append(f"Arrival Time Accuracy: {time_pct:.1%}")
        
        if missing_stations > 0:
            feedback.append(f"Missing {missing_stations} cross-sections from output.")
            
        passed = score >= 80
        return {
            "passed": passed,
            "score": score,
            "feedback": " ".join(feedback)
        }
        
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)

def load_csv_to_dict(path):
    """Load CSV into a dict keyed by River_Station."""
    data = {}
    with open(path, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            # Normalize keys (strip whitespace)
            clean_row = {k.strip(): v for k, v in row.items()}
            if 'River_Station' in clean_row:
                data[clean_row['River_Station']] = clean_row
    return data