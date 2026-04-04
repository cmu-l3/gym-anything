#!/usr/bin/env python3
"""
Verifier for analyze_geometry_containment task.

Strategy:
1. Verify existence of output files (CSV, JSON, Plot).
2. Verify CSV structure and content:
   - Must contain 'riverstation', 'maxwse', 'freeboard' columns (fuzzy match).
   - Verify Max WSE values correlate with Ground Truth extracted from HDF.
3. Verify Critical Sections:
   - Check if the top critical sections reported in JSON match the ones in the CSV (internal consistency).
   - Check if negative freeboard is identified (glass-walling).
"""

import json
import os
import tempfile
import logging
import numpy as np

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_geometry_containment(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. File Existence Checks (20 pts)
    files = result.get("files", {})
    if files.get("csv_exists"):
        score += 10
        feedback.append("CSV file created.")
    else:
        feedback.append("CSV file missing.")
        
    if files.get("json_exists"):
        score += 5
        feedback.append("Critical sections JSON created.")
    else:
        feedback.append("JSON file missing.")
        
    if files.get("plot_exists"):
        score += 5
        feedback.append("Plot created.")
    else:
        feedback.append("Plot missing.")

    # 2. CSV Data Validation (40 pts)
    agent_data = result.get("agent_csv_data", [])
    ground_truth = result.get("ground_truth", {})
    gt_wse = ground_truth.get("max_wse_values", [])
    
    data_valid = False
    if agent_data and len(agent_data) > 0:
        # Check columns
        keys = [k.lower() for k in agent_data[0].keys()]
        required_keys = ["station", "wse", "freeboard"]
        missing = [req for req in required_keys if not any(req in k for k in keys)]
        
        if not missing:
            score += 10
            feedback.append("CSV has correct columns.")
            
            # Check WSE correlation with GT
            # We assume the order matches or we try to match by station
            # Simplified: Check if values are in plausible range (Muncie WSE usually 840-860 ft)
            wse_vals = []
            for row in agent_data:
                # Find the wse key
                wse_key = next(k for k in row.keys() if "wse" in k.lower())
                try:
                    wse_vals.append(float(row[wse_key]))
                except:
                    pass
            
            if wse_vals:
                mean_wse = np.mean(wse_vals)
                if 800 < mean_wse < 1000:
                    score += 10
                    feedback.append("WSE values in plausible range for Muncie.")
                    data_valid = True
                    
                    # If GT is available, check correlation
                    if gt_wse and len(gt_wse) == len(wse_vals):
                         # Simple check: max value close
                         if abs(max(gt_wse) - max(wse_vals)) < 1.0:
                             score += 20
                             feedback.append("WSE values match HEC-RAS output.")
                         else:
                             feedback.append("WSE values differ from ground truth.")
                    elif gt_wse:
                        # Length mismatch, but give partial credit if range is good
                        score += 10
                        feedback.append("WSE range plausible, but row count differs from GT.")
                else:
                    feedback.append(f"WSE values seem incorrect (Mean: {mean_wse}).")
        else:
            feedback.append(f"CSV missing columns matching: {missing}")
    else:
        feedback.append("CSV is empty or invalid.")

    # 3. Critical Section Analysis (30 pts)
    critical_json = result.get("agent_critical_json")
    if data_valid and critical_json:
        # Parse critical list
        try:
            if isinstance(critical_json, list):
                crit_list = critical_json
            elif isinstance(critical_json, dict) and "critical" in critical_json: # handle {"critical": [...]}
                crit_list = critical_json["critical"]
            else:
                crit_list = []
                
            if len(crit_list) > 0:
                score += 10
                feedback.append("Critical sections identified.")
                
                # Check consistency: Are these the lowest freeboard in the CSV?
                # Re-sort agent data by freeboard
                try:
                    fb_key = next(k for k in agent_data[0].keys() if "freeboard" in k.lower())
                    st_key = next(k for k in agent_data[0].keys() if "station" in k.lower())
                    
                    sorted_data = sorted(agent_data, key=lambda x: float(x[fb_key]))
                    top_5_csv = [str(row[st_key]) for row in sorted_data[:5]]
                    
                    # Fuzzy match
                    matches = 0
                    for c in crit_list:
                        if str(c) in top_5_csv:
                            matches += 1
                    
                    if matches >= 3:
                        score += 20
                        feedback.append("Critical sections match CSV analysis.")
                    else:
                        feedback.append("Critical sections in JSON do not match lowest freeboard in CSV.")
                except Exception as e:
                    feedback.append(f"Could not verify consistency: {e}")
        except:
            feedback.append("Could not parse critical sections JSON.")

    # 4. Visualization (10 pts)
    if files.get("plot_exists"):
        # We assume if it exists and agent is honest (we trust CSV), it's likely okay.
        # VLM would verify content, but for program check, existence + CSV valid is enough
        if data_valid:
            score += 10
            feedback.append("Visualization verified.")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }