#!/usr/bin/env python3
"""
Verifier for compute_cumulative_erosive_impulse task.
Compares agent's CSV results against ground truth calculated from the HDF file.
"""

import json
import os
import tempfile
import csv
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_compute_cumulative_erosive_impulse(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback = []
    
    # 1. Retrieve Task Result and Ground Truth from container
    result_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    gt_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    agent_csv_file = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    
    try:
        # Copy JSONs
        copy_from_env("/tmp/task_result.json", result_file.name)
        copy_from_env("/tmp/ground_truth.json", gt_file.name)
        
        with open(result_file.name, 'r') as f:
            task_res = json.load(f)
            
        with open(gt_file.name, 'r') as f:
            gt_data = json.load(f)
            
        # Check if GT generation failed
        if gt_data.get("error"):
            logger.warning(f"Ground Truth Generation Failed: {gt_data['error']}")
            # Fallback: If we can't generate GT, we can't verify accuracy fully.
            # We will rely on structure checks.
            gt_data = None
            feedback.append("Warning: Could not generate ground truth for strict accuracy check.")

        # --- CRITERION 1: File Existence & Anti-Gaming (25 pts) ---
        if task_res.get("csv_exists") and task_res.get("csv_modified"):
            score += 15
            feedback.append("CSV file created/modified successfully.")
        elif task_res.get("csv_exists"):
            score += 5
            feedback.append("CSV file exists but was not modified (stale?).")
        else:
            feedback.append("CSV file not found.")
            
        if task_res.get("plot_exists") and task_res.get("plot_modified"):
            score += 10
            feedback.append("Plot created.")
        else:
            feedback.append("Plot missing or not created during task.")

        # --- CRITERION 2: CSV Content & Accuracy (50 pts) ---
        csv_valid = False
        agent_data = {}
        
        if task_res.get("csv_exists"):
            try:
                copy_from_env(task_res["csv_path"], agent_csv_file.name)
                with open(agent_csv_file.name, 'r') as f:
                    reader = csv.DictReader(f)
                    rows = list(reader)
                    
                    # Validate headers
                    required_cols = ["RiverStation", "Cumulative_Impulse_lb_sq_ft_hr"]
                    if all(col in reader.fieldnames for col in required_cols):
                        score += 10
                        feedback.append("CSV headers look correct.")
                        csv_valid = True
                    else:
                        feedback.append(f"Missing required CSV columns. Found: {reader.fieldnames}")
                    
                    # Parse data for accuracy check
                    for row in rows:
                        rs = row.get("RiverStation", "").strip()
                        try:
                            val = float(row.get("Cumulative_Impulse_lb_sq_ft_hr", 0))
                            agent_data[rs] = val
                        except ValueError:
                            pass
                            
            except Exception as e:
                feedback.append(f"Failed to read/parse CSV: {e}")

        # Accuracy Check against Ground Truth
        if csv_valid and gt_data and "station_data" in gt_data:
            gt_stations = gt_data["station_data"]
            
            # Check overlap
            common_stations = set(agent_data.keys()) & set(gt_stations.keys())
            if len(common_stations) < len(gt_stations) * 0.5:
                feedback.append("Agent analysis missed more than 50% of cross sections found in HDF.")
            else:
                # Check random sample or critical station
                crit_rs = gt_data["critical_station"]
                crit_val = gt_data["critical_impulse"]
                
                # Check Critical Station Accuracy (20 pts)
                agent_crit_val = agent_data.get(crit_rs)
                if agent_crit_val is not None:
                    # Allow 5% tolerance
                    if math.isclose(agent_crit_val, crit_val, rel_tol=0.05):
                        score += 20
                        feedback.append(f"Critical station {crit_rs} impulse ({agent_crit_val:.4f}) matches ground truth.")
                    else:
                        feedback.append(f"Critical station value mismatch. Expected ~{crit_val:.4f}, got {agent_crit_val:.4f}.")
                else:
                    feedback.append(f"Critical station {crit_rs} not found in agent output.")

                # General Correlation Check (20 pts)
                # Check average error on a few points
                match_count = 0
                check_count = 0
                for rs in list(common_stations)[:10]:
                    check_count += 1
                    if math.isclose(agent_data[rs], gt_stations[rs], rel_tol=0.1):
                        match_count += 1
                
                if check_count > 0 and match_count / check_count > 0.8:
                    score += 20
                    feedback.append("Overall impulse values match ground truth.")
                elif check_count > 0:
                    score += 5 # Partial credit
                    feedback.append("Some values match, but accuracy is low.")

        elif csv_valid and not gt_data:
            # Fallback if GT failed: give partial points for valid CSV structure with numeric data
            if len(agent_data) > 0:
                score += 30
                feedback.append("CSV contains data (Accuracy not verified due to GT failure).")

        # --- CRITERION 3: Summary File (10 pts) ---
        if task_res.get("summary_exists"):
            score += 10
            feedback.append("Summary file exists.")
            
        # --- CRITERION 4: Threshold Logic (15 pts) ---
        # Heuristic: If values are present and > 0, we assume some logic was applied.
        # Strict check was done in Accuracy section.
        # We give these points if the accuracy check passed, or if the csv seems populated reasonably.
        if score >= 60: 
             # If they got the accuracy points, they used the logic.
             score += 15
             feedback.append("Logic verification passed via accuracy check.")
        elif csv_valid and len(agent_data) > 0:
             # Basic credit
             score += 5
             
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        # Cleanup
        for f in [result_file, gt_file, agent_csv_file]:
            if os.path.exists(f.name):
                os.unlink(f.name)

    passed = score >= 70
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback)
    }