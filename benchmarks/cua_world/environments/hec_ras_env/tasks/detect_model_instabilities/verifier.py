#!/usr/bin/env python3
"""
Verifier for detect_model_instabilities task.

SCORING CRITERIA:
1. Analysis Script Created (10 pts)
2. CSV Report Exists & Created During Task (15 pts)
3. CSV Content Accuracy (30 pts)
   - Columns exist
   - Sorted descending
   - Top unstable cross-section matches ground truth
4. Oscillation Index Accuracy (25 pts)
   - Values match ground truth within tolerance
5. Plot Generated (20 pts)
   - Exists, is valid image, reasonable size
"""

import json
import tempfile
import os
import csv
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_detect_model_instabilities(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    score = 0
    feedback_parts = []
    
    # --- Step 1: Retrieve Task Result JSON ---
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
            
    # Extract file statuses
    script_status = result_data.get('script_file', {})
    report_status = result_data.get('report_file', {})
    plot_status = result_data.get('plot_file', {})
    ground_truth = result_data.get('ground_truth_top_5', [])
    
    # Handle ground truth error case
    if isinstance(ground_truth, dict) and "error" in ground_truth:
        return {"passed": False, "score": 0, "feedback": f"Internal Error: Could not generate ground truth: {ground_truth['error']}"}
        
    # --- Criterion 1: Script Creation (10 pts) ---
    if script_status.get('exists') and script_status.get('created_during_task'):
        score += 10
        feedback_parts.append("Analysis script created.")
    elif script_status.get('exists'):
        score += 5
        feedback_parts.append("Analysis script exists but timestamp is old.")
    else:
        feedback_parts.append("Analysis script missing.")
        
    # --- Criterion 2: CSV Report Existence (15 pts) ---
    csv_exists = report_status.get('exists') and report_status.get('size', 0) > 0
    if csv_exists:
        if report_status.get('created_during_task'):
            score += 15
            feedback_parts.append("CSV report generated.")
        else:
            score += 5
            feedback_parts.append("CSV report exists but was not created during task.")
    else:
        feedback_parts.append("CSV report missing.")
        
    # --- Criterion 3 & 4: CSV Content & Accuracy (55 pts) ---
    if csv_exists and ground_truth:
        temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
        try:
            copy_from_env("/tmp/agent_report.csv", temp_csv.name)
            
            with open(temp_csv.name, 'r') as f:
                reader = csv.DictReader(f)
                rows = list(reader)
                
            if not rows:
                feedback_parts.append("CSV is empty.")
            else:
                # Check columns
                required_cols = ['RiverStation', 'OscillationIndex']
                if all(col in rows[0] for col in required_cols):
                    # Check Sorting
                    try:
                        first_idx = float(rows[0]['OscillationIndex'])
                        last_idx = float(rows[-1]['OscillationIndex'])
                        if first_idx >= last_idx:
                            score += 10
                            feedback_parts.append("Report sorted correctly.")
                        else:
                            feedback_parts.append("Report NOT sorted descending.")
                    except ValueError:
                        feedback_parts.append("Invalid numeric data in CSV.")

                    # Check Top Instability Match (20 pts)
                    top_agent_rs = rows[0]['RiverStation']
                    top_gt_rs = ground_truth[0]['RiverStation']
                    
                    # Fuzzy match just in case of slight formatting diffs (e.g. "1200" vs "1200.0")
                    if top_agent_rs.strip() == top_gt_rs.strip() or \
                       top_agent_rs.replace('.0','') == top_gt_rs.replace('.0',''):
                        score += 20
                        feedback_parts.append(f"Correctly identified most unstable section ({top_gt_rs}).")
                    else:
                        feedback_parts.append(f"Wrong top section. Expected {top_gt_rs}, got {top_agent_rs}.")
                        
                    # Check Value Accuracy (25 pts)
                    # Compare agent's top value with GT top value
                    try:
                        agent_val = float(rows[0]['OscillationIndex'])
                        gt_val = float(ground_truth[0]['OscillationIndex'])
                        
                        # Allow small floating point tolerance (1%)
                        if math.isclose(agent_val, gt_val, rel_tol=0.01):
                            score += 25
                            feedback_parts.append("Oscillation Index calculated correctly.")
                        else:
                            feedback_parts.append(f"Incorrect Oscillation Index value. Expected ~{gt_val:.4f}, got {agent_val:.4f}.")
                    except ValueError:
                        pass
                else:
                    feedback_parts.append(f"Missing required columns in CSV. Found: {list(rows[0].keys())}")
                    
        except Exception as e:
            feedback_parts.append(f"Failed to verify CSV content: {str(e)}")
        finally:
            if os.path.exists(temp_csv.name):
                os.unlink(temp_csv.name)

    # --- Criterion 5: Plot Generation (20 pts) ---
    if plot_status.get('exists') and plot_status.get('created_during_task'):
        if plot_status.get('size', 0) > 5000: # >5KB suggests real content
            score += 20
            feedback_parts.append("Visualization plot generated.")
        else:
            score += 5
            feedback_parts.append("Plot file exists but is suspiciously small (<5KB).")
    elif plot_status.get('exists'):
        score += 5
        feedback_parts.append("Plot exists but timestamp is old.")
    else:
        feedback_parts.append("Visualization plot missing.")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }