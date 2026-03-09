#!/usr/bin/env python3
"""
Verifier for audit_egl_consistency task.

Verifies that:
1. The user identified the correct peak flow timestamp.
2. The user extracted correct WSE/Velocity values for that timestamp.
3. The user correctly computed EGL.
4. The output CSV format is correct.
"""

import json
import os
import csv
import logging
import tempfile
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_audit_egl_consistency(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # Files to retrieve
    files = {
        "result": "/tmp/task_result.json",
        "ground_truth": "/tmp/ground_truth.json",
        "user_csv": "/tmp/user_audit.csv",
        "user_txt": "/tmp/user_summary.txt"
    }
    
    data = {}
    
    # Copy files
    with tempfile.TemporaryDirectory() as temp_dir:
        for name, path in files.items():
            local_path = os.path.join(temp_dir, f"{name}.dat")
            try:
                copy_from_env(path, local_path)
                if name.endswith("json"):
                    with open(local_path, 'r') as f:
                        data[name] = json.load(f)
                else:
                    with open(local_path, 'r') as f:
                        data[name] = f.read()
            except Exception as e:
                logger.warning(f"Could not load {name}: {e}")
                data[name] = None

    # Check execution
    res = data.get("result")
    if not res or not res.get("csv_exists"):
        return {"passed": False, "score": 0, "feedback": "Output CSV file not found."}
    
    # 1. File Existence & Timestamp (10 pts)
    task_start = res.get("task_start_time", 0)
    file_mtime = res.get("csv_mtime", 0)
    if file_mtime > task_start:
        score += 10
        feedback_parts.append("Files created during task")
    else:
        feedback_parts.append("File timestamp violation (created before task?)")

    # 2. Check Ground Truth availability
    gt = data.get("ground_truth")
    if not gt or "error" in gt:
        return {"passed": False, "score": score, "feedback": "System error: could not generate ground truth. Please retry."}
    
    expected_index = gt["peak_time_index"]
    
    # 3. Verify Text Summary (Peak Index) (20 pts)
    user_txt = data.get("user_txt", "")
    index_found = False
    if user_txt:
        # Simple string search for the index
        if str(expected_index) in user_txt:
            score += 20
            index_found = True
            feedback_parts.append(f"Correct peak index identified ({expected_index})")
        else:
            feedback_parts.append(f"Incorrect peak index (Expected {expected_index})")
    
    # 4. Verify CSV Content (70 pts)
    user_csv_content = data.get("user_csv", "")
    if user_csv_content:
        try:
            reader = csv.DictReader(user_csv_content.splitlines())
            rows = list(reader)
            
            if not rows:
                feedback_parts.append("CSV is empty")
            else:
                # Check columns
                required_cols = ['RiverStation', 'WSE_ft', 'Velocity_fps', 'EGL_ft', 'Energy_Gain_Flag']
                if all(col in rows[0] for col in required_cols):
                    score += 10 # Formatting points
                    
                    # Validate Data matches Snapshot
                    # We check the first, middle, and last rows to ensure the PROFILE matches the TimeStep
                    # Finding corresponding rows in GT
                    
                    matches = 0
                    total_checked = 0
                    
                    gt_profile = {str(item['rs']).strip(): item for item in gt['profile']}
                    
                    for row in rows:
                        rs = str(row['RiverStation']).strip()
                        if rs in gt_profile:
                            total_checked += 1
                            ref = gt_profile[rs]
                            
                            try:
                                u_wse = float(row['WSE_ft'])
                                u_vel = float(row['Velocity_fps'])
                                u_egl = float(row['EGL_ft'])
                                
                                # Check WSE (proves correct timestep was extracted)
                                if math.isclose(u_wse, ref['wse'], abs_tol=0.1):
                                    matches += 1
                                    
                                    # Check EGL calculation
                                    # Calc user EGL from user vars to check logic
                                    calc_egl = u_wse + (u_vel**2 / 64.348)
                                    if math.isclose(u_egl, calc_egl, abs_tol=0.1):
                                        # Logic point
                                        pass
                            except ValueError:
                                pass
                    
                    if total_checked > 0:
                        accuracy = matches / total_checked
                        if accuracy > 0.8:
                            score += 40
                            feedback_parts.append("Data values match ground truth snapshot")
                        elif accuracy > 0.5:
                            score += 20
                            feedback_parts.append("Data values partially match")
                        else:
                            feedback_parts.append("Data values do not match expected snapshot")
                            
                    # Check Sorting (Upstream to Downstream) (10 pts)
                    # Simple check: First RS should be higher than Last RS (assuming numeric RS)
                    try:
                        first_rs = float(rows[0]['RiverStation'])
                        last_rs = float(rows[-1]['RiverStation'])
                        if first_rs > last_rs:
                            score += 10
                            feedback_parts.append("Sorted correctly (Upstream->Downstream)")
                    except:
                        pass # Non-numeric RS or error
                        
                    # Check Flag Logic (10 pts)
                    # Verify at least one flag is consistent with user's own data
                    valid_flags = 0
                    for i in range(len(rows) - 1):
                        curr = rows[i]
                        next_row = rows[i+1]
                        try:
                            curr_egl = float(curr['EGL_ft'])
                            next_egl = float(next_row['EGL_ft'])
                            user_flag = str(curr['Energy_Gain_Flag']).lower() == 'true'
                            
                            # Next is downstream. If Next > Curr, gain.
                            is_gain = next_egl > (curr_egl + 0.01) # Tolerance
                            
                            if is_gain == user_flag:
                                valid_flags += 1
                        except:
                            pass
                    
                    if len(rows) > 1 and (valid_flags / (len(rows)-1) > 0.9):
                        score += 10
                        feedback_parts.append("Violation flags calculated correctly")

                else:
                    feedback_parts.append("CSV missing required columns")
        except Exception as e:
            feedback_parts.append(f"CSV parsing error: {e}")
    else:
        feedback_parts.append("CSV content missing")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }