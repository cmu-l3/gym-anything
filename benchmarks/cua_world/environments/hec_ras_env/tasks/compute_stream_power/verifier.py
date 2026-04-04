#!/usr/bin/env python3
"""
Verifier for compute_stream_power task.
Compares agent's CSV output against ground truth generated from the HDF file.
"""

import json
import os
import tempfile
import csv
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_compute_stream_power(traj, env_info, task_info):
    """
    Verify the stream power calculation.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Points allocation
    # 1. Script & Files exist: 20 pts
    # 2. CSV Structure valid: 10 pts
    # 3. Numerical Accuracy (Flow, WSE, Slope, Power): 50 pts
    # 4. Summary File Accuracy: 20 pts
    
    score = 0
    feedback = []
    
    # --- Step 1: Load Task Result ---
    task_result = {}
    with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as f:
        try:
            copy_from_env("/tmp/task_result.json", f.name)
            f.seek(0)
            task_result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
        finally:
            try: os.unlink(f.name) 
            except: pass

    # Basic checks
    if not task_result.get("script_exists"):
        feedback.append("Python script not found.")
    else:
        score += 5
        feedback.append("Python script found.")

    if not task_result.get("csv_exists"):
        feedback.append("Output CSV not found.")
        return {"passed": False, "score": score, "feedback": " ".join(feedback)}
    
    score += 10 # CSV exists
    
    if not task_result.get("file_created_during_task"):
        feedback.append("Warning: Output file timestamp is before task start.")
        # We don't fail immediately but penalty applied via score accumulation
    else:
        score += 5 # Created during task

    # --- Step 2: Load Ground Truth ---
    gt_data = {}
    with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as f:
        try:
            copy_from_env("/tmp/ground_truth.json", f.name)
            f.seek(0)
            gt_data = json.load(f)
        except:
            feedback.append("Error loading ground truth data.")
        finally:
            try: os.unlink(f.name)
            except: pass
            
    if "error" in gt_data:
        return {"passed": False, "score": score, "feedback": f"Ground truth generation failed: {gt_data['error']}"}

    # --- Step 3: Load Agent CSV ---
    agent_data = []
    with tempfile.NamedTemporaryFile(delete=False, suffix='.csv') as f:
        try:
            copy_from_env("/tmp/agent_output.csv", f.name)
            with open(f.name, 'r') as csvfile:
                reader = csv.DictReader(csvfile)
                # Normalize headers
                reader.fieldnames = [name.lower().strip() for name in reader.fieldnames]
                for row in reader:
                    agent_data.append(row)
        except Exception as e:
            feedback.append(f"Failed to read agent CSV: {str(e)}")
        finally:
            try: os.unlink(f.name)
            except: pass

    if not agent_data:
        return {"passed": False, "score": score, "feedback": "Agent CSV is empty or invalid. " + " ".join(feedback)}
    
    # Check headers
    first_row = agent_data[0]
    required_cols = ['station', 'flow_cfs', 'wse_ft', 'ws_slope', 'streampower']
    missing_cols = [c for c in required_cols if not any(c in k for k in first_row.keys())]
    
    if missing_cols:
        feedback.append(f"Missing columns in CSV: {missing_cols}")
        score -= 5
    else:
        score += 10 # Structure valid

    # --- Step 4: Numerical Comparison ---
    # Convert agent data to dict keyed by station for easy lookup
    # Using 'station' column
    
    agent_lookup = {}
    for row in agent_data:
        try:
            # Find the station key
            st_key = next(k for k in row.keys() if 'station' in k)
            st_val = float(row[st_key])
            agent_lookup[st_val] = row
        except:
            continue
            
    # Compare against GT
    gt_stations = gt_data.get("stations", [])
    gt_stream_power = gt_data.get("stream_power", [])
    
    matched_count = 0
    total_error_sp = 0
    total_error_wse = 0
    
    for i, st in enumerate(gt_stations):
        # Find closest station in agent data (allow small floating point diff)
        closest_st = None
        min_diff = float('inf')
        
        for ast in agent_lookup.keys():
            diff = abs(st - ast)
            if diff < 0.1: # Tolerance for station matching
                closest_st = ast
                min_diff = diff
                break
        
        if closest_st is not None:
            matched_count += 1
            row = agent_lookup[closest_st]
            
            # Find columns
            sp_key = next((k for k in row.keys() if 'power' in k), None)
            wse_key = next((k for k in row.keys() if 'wse' in k), None)
            
            if sp_key and wse_key:
                try:
                    agent_sp = float(row[sp_key])
                    agent_wse = float(row[wse_key])
                    
                    gt_sp = gt_stream_power[i]
                    gt_wse = gt_data["wse"][i]
                    
                    # Calculate errors
                    # Stream power error (normalized by value + 1 to avoid div zero)
                    total_error_sp += abs(agent_sp - gt_sp) / (abs(gt_sp) + 1.0)
                    total_error_wse += abs(agent_wse - gt_wse)
                except ValueError:
                    pass

    # Scoring Numerical Accuracy
    n_pts = len(gt_stations)
    if matched_count < n_pts * 0.8:
        feedback.append(f"Matched only {matched_count}/{n_pts} stations.")
    else:
        score += 10 # Good coverage
        
        avg_error_sp = total_error_sp / matched_count
        avg_error_wse = total_error_wse / matched_count
        
        if avg_error_wse < 0.1: # Very close WSE
            score += 20
        elif avg_error_wse < 0.5:
            score += 10
            
        if avg_error_sp < 0.1: # 10% error margin for derived calc
            score += 20
        elif avg_error_sp < 0.25:
            score += 10
        else:
            feedback.append(f"Stream power calculation inaccurate (Avg Error: {avg_error_sp:.2f}).")

    # --- Step 5: Summary File Check ---
    if task_result.get("summary_exists"):
        summary_content = ""
        with tempfile.NamedTemporaryFile(delete=False, suffix='.txt') as f:
            try:
                copy_from_env("/tmp/agent_summary.txt", f.name)
                with open(f.name, 'r') as tf:
                    summary_content = tf.read()
            except: pass
            finally:
                try: os.unlink(f.name)
                except: pass
        
        # Parse Summary
        # Expected: Max_StreamPower_Value: X
        gt_max_sp = gt_data.get("max_sp_val", 0)
        gt_peak_flow = gt_data.get("peak_flow_downstream", 0)
        
        found_val = False
        found_flow = False
        
        for line in summary_content.split('\n'):
            if "Max_StreamPower_Value" in line:
                try:
                    val = float(line.split(':')[1].strip())
                    if abs(val - gt_max_sp) / (gt_max_sp + 1) < 0.05:
                        found_val = True
                except: pass
            if "Peak_Flow_cfs" in line:
                try:
                    val = float(line.split(':')[1].strip())
                    if abs(val - gt_peak_flow) / (gt_peak_flow + 1) < 0.05:
                        found_flow = True
                except: pass
        
        if found_val: score += 10
        else: feedback.append("Summary: Max Stream Power value incorrect or missing.")
        
        if found_flow: score += 10
        else: feedback.append("Summary: Peak Flow value incorrect or missing.")
    else:
        feedback.append("Summary file missing.")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }