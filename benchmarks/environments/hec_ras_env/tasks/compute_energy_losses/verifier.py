#!/usr/bin/env python3
"""
Verifier for compute_energy_losses task.
Compares agent's CSV output against Ground Truth generated from the HDF file.
"""

import json
import os
import tempfile
import csv
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_compute_energy_losses(traj, env_info, task_info):
    """
    Verify the energy loss analysis task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    max_score = 100
    feedback_parts = []
    
    # Files to retrieve
    files_to_check = {
        "result_json": "/tmp/task_result.json",
        "ground_truth": "/tmp/ground_truth.json",
        "agent_csv": "/home/ga/Documents/hec_ras_results/energy_loss_analysis.csv",
        "agent_summary": "/home/ga/Documents/hec_ras_results/energy_loss_summary.txt",
        "agent_script": "/home/ga/Documents/hec_ras_results/energy_loss_analysis.py"
    }
    
    local_files = {}
    
    # Retrieve files
    with tempfile.TemporaryDirectory() as tmpdir:
        for name, remote_path in files_to_check.items():
            local_path = os.path.join(tmpdir, os.path.basename(remote_path))
            try:
                copy_from_env(remote_path, local_path)
                if os.path.exists(local_path) and os.path.getsize(local_path) > 0:
                    local_files[name] = local_path
            except Exception as e:
                logger.warning(f"Could not copy {name}: {e}")

        # 1. Check Task Result JSON
        if "result_json" not in local_files:
            return {"passed": False, "score": 0, "feedback": "Failed to retrieve task result metadata"}
            
        with open(local_files["result_json"], 'r') as f:
            result_meta = json.load(f)
            
        # 2. Check Ground Truth
        ground_truth = {}
        if "ground_truth" in local_files:
            with open(local_files["ground_truth"], 'r') as f:
                ground_truth = json.load(f)
        
        if "error" in ground_truth:
            return {"passed": False, "score": 0, "feedback": f"Ground Truth generation failed: {ground_truth['error']}"}

        # --- SCORING CRITERIA ---

        # Criterion 1: Script exists (Evidence of work) - 10 pts
        if result_meta.get("script_exists", False):
            score += 10
            feedback_parts.append("Python analysis script created.")
        else:
            feedback_parts.append("Missing Python analysis script.")

        # Criterion 2: CSV structure and existence - 15 pts
        csv_data = []
        if "agent_csv" in local_files and result_meta.get("csv_modified", False):
            try:
                with open(local_files["agent_csv"], 'r') as f:
                    reader = csv.DictReader(f)
                    if reader.fieldnames:
                        required_cols = {'upstream_xs', 'downstream_xs', 'reach_length_ft', 
                                         'upstream_egl_ft', 'downstream_egl_ft', 'energy_loss_ft', 'energy_slope_ft_per_ft'}
                        if required_cols.issubset(set(reader.fieldnames)):
                            score += 15
                            feedback_parts.append("CSV file has correct columns.")
                            csv_data = list(reader)
                        else:
                            score += 5
                            feedback_parts.append(f"CSV missing columns. Found: {reader.fieldnames}")
                    else:
                        feedback_parts.append("CSV file empty or unreadable.")
            except Exception as e:
                feedback_parts.append(f"Error parsing CSV: {e}")
        else:
            feedback_parts.append("CSV file not found or not modified.")

        # Criterion 3: Correct number of rows - 10 pts
        gt_rows = ground_truth.get("rows", [])
        if len(csv_data) > 0:
            # Allow +/- 1 row difference (header handling issues etc)
            if abs(len(csv_data) - len(gt_rows)) <= 1:
                score += 10
                feedback_parts.append(f"Row count correct ({len(csv_data)}).")
            else:
                feedback_parts.append(f"Row count mismatch (Expected ~{len(gt_rows)}, Got {len(csv_data)}).")

        # Criterion 4: Values Accuracy (Max Loss Pair & Individual Values) - 35 pts
        # Check Max Loss Pair
        matched_rows = 0
        total_rows = len(gt_rows)
        
        if len(csv_data) > 0 and len(gt_rows) > 0:
            # Verify Max Loss Pair
            agent_max_loss = -999.0
            agent_max_pair = ""
            
            try:
                # Find max loss in agent data
                for row in csv_data:
                    loss = float(row.get('energy_loss_ft', -999))
                    if loss > agent_max_loss:
                        agent_max_loss = loss
                        agent_max_pair = f"{row.get('upstream_xs')}-{row.get('downstream_xs')}"
                
                gt_max_pair = ground_truth.get("max_loss_pair", "")
                
                # Loose matching on pair name (trim spaces)
                if gt_max_pair.replace(" ", "") in agent_max_pair.replace(" ", ""):
                    score += 20
                    feedback_parts.append("Correctly identified max energy loss pair.")
                else:
                    feedback_parts.append(f"Wrong max loss pair. Expected {gt_max_pair}, Got {agent_max_pair}.")
            except ValueError:
                 feedback_parts.append("Could not parse numeric values in CSV.")

            # Verify Individual Values (Sample check)
            # We check the first few rows
            correct_values = 0
            checks = 0
            for i in range(min(len(csv_data), len(gt_rows), 5)):
                try:
                    agent_val = float(csv_data[i]['energy_loss_ft'])
                    gt_val = gt_rows[i]['loss']
                    # 20% tolerance or 0.1 ft absolute (for small values)
                    if math.isclose(agent_val, gt_val, rel_tol=0.2, abs_tol=0.1):
                        correct_values += 1
                    checks += 1
                except:
                    pass
            
            if checks > 0 and (correct_values / checks) >= 0.75:
                score += 15
                feedback_parts.append("Energy loss calculations match ground truth.")
            elif checks > 0:
                 feedback_parts.append("Energy loss calculations diverge from ground truth.")

        # Criterion 5: Summary File - 20 pts
        if "agent_summary" in local_files and result_meta.get("summary_modified", False):
            with open(local_files["agent_summary"], 'r') as f:
                content = f.read().lower()
                
            gt_total = ground_truth.get("total_loss", 0)
            gt_slope = ground_truth.get("avg_slope", 0)
            
            # Simple check: does the file contain numbers reasonably close to GT?
            # We look for the numbers in the text
            found_total = False
            found_slope = False
            
            import re
            numbers = [float(x) for x in re.findall(r"-?\d+\.?\d*", content)]
            
            for num in numbers:
                if math.isclose(num, gt_total, rel_tol=0.2, abs_tol=0.5):
                    found_total = True
                if math.isclose(num, gt_slope, rel_tol=0.2, abs_tol=0.001):
                    found_slope = True
            
            if found_total:
                score += 10
                feedback_parts.append("Summary: Total Loss correct.")
            else:
                feedback_parts.append(f"Summary: Total Loss incorrect or missing (Expected ~{gt_total:.2f}).")
                
            if found_slope:
                score += 10
                feedback_parts.append("Summary: Average Slope correct.")
            else:
                feedback_parts.append(f"Summary: Average Slope incorrect or missing (Expected ~{gt_slope:.5f}).")
        else:
             feedback_parts.append("Summary text file missing.")

        # Criterion 6: Files created during task (Anti-gaming) - 10 pts
        if result_meta.get("csv_modified", False) and result_meta.get("summary_modified", False):
            score += 10
        else:
            feedback_parts.append("Files were not modified during task session.")

        return {
            "passed": score >= 55,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }