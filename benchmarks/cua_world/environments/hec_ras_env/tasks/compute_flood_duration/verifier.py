#!/usr/bin/env python3
"""
Verifier for compute_flood_duration task.
Validates:
1. Python script exists and is non-trivial.
2. CSV output exists and follows the required schema.
3. Computed values (Peak WSE, Flood Duration) match Ground Truth (pre-calculated).
"""

import json
import os
import tempfile
import logging
import pandas as pd
import numpy as np

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_compute_flood_duration(traj, env_info, task_info):
    """
    Verifies the flood duration analysis task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Define paths
    csv_path_container = "/home/ga/Documents/hec_ras_results/flood_duration.csv"
    script_path_container = "/home/ga/Documents/hec_ras_results/flood_duration_analysis.py"
    gt_path_container = "/var/lib/hec_ras/ground_truth.json"
    result_json_path = "/tmp/task_result.json"

    # Create temp directory for artifacts
    with tempfile.TemporaryDirectory() as temp_dir:
        local_csv = os.path.join(temp_dir, "flood_duration.csv")
        local_script = os.path.join(temp_dir, "analysis.py")
        local_gt = os.path.join(temp_dir, "ground_truth.json")
        local_result = os.path.join(temp_dir, "result.json")

        # Copy files
        try:
            copy_from_env(result_json_path, local_result)
            with open(local_result, 'r') as f:
                task_stats = json.load(f)
            
            # Copy Ground Truth
            copy_from_env(gt_path_container, local_gt)
            with open(local_gt, 'r') as f:
                ground_truth = json.load(f)

            # Copy Agent files if they exist
            if task_stats.get("csv_exists"):
                copy_from_env(csv_path_container, local_csv)
            
            if task_stats.get("script_exists"):
                copy_from_env(script_path_container, local_script)

        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task files: {str(e)}"}

        # === Scoring ===
        score = 0
        feedback = []

        # 1. Script Validation (15 pts)
        if task_stats.get("script_exists") and task_stats.get("script_size", 0) > 200:
            score += 15
            feedback.append("Analysis script created.")
        else:
            feedback.append("Analysis script missing or trivial.")

        # 2. CSV Existence & Creation (15 pts)
        if task_stats.get("csv_exists") and task_stats.get("csv_created_during_task"):
            score += 15
            feedback.append("Output CSV created during task.")
        else:
            feedback.append("Output CSV missing or old.")
            # Early exit if CSV missing
            return {"passed": False, "score": score, "feedback": " ".join(feedback)}

        # 3. CSV Schema Validation (20 pts)
        try:
            df = pd.read_csv(local_csv)
            
            # Normalize column names
            df.columns = [c.strip() for c in df.columns]
            
            required_cols = {
                "CrossSection", 
                "ThresholdElevation_ft", 
                "FloodDuration_hours", 
                "PeakWSE_ft", 
                "TimeAboveThreshold_pct"
            }
            
            missing_cols = required_cols - set(df.columns)
            if not missing_cols:
                score += 20
                feedback.append("CSV has correct columns.")
            else:
                score += 5
                feedback.append(f"CSV missing columns: {missing_cols}")

            # 4. Data Validation against Ground Truth (50 pts)
            if ground_truth.get("valid"):
                gt_data = ground_truth["data"]
                total_xs = ground_truth["total_xs"]
                
                # Check 4a: Row count (10 pts)
                if len(df) >= total_xs - 2 and len(df) <= total_xs + 2:
                    score += 10
                    feedback.append(f"Row count matches model ({len(df)}).")
                else:
                    feedback.append(f"Row count mismatch (Expected ~{total_xs}, Got {len(df)}).")

                # Check 4b: Value accuracy (40 pts)
                # We verify a sample of cross-sections based on index
                matches = 0
                checks = 0
                
                # Assume agent might use index or name for CrossSection.
                # If numeric index, we can map directly.
                
                for item in gt_data:
                    idx = item["xs_index"]
                    
                    # Try to find row in dataframe
                    # If df has integer index matching, use iloc or 'CrossSection' col
                    row = None
                    if "CrossSection" in df.columns:
                        # Heuristic: check if CrossSection col contains the index or 0-based index
                        # HEC-RAS often outputs 1-based, python 0-based.
                        if idx < len(df):
                            row = df.iloc[idx]
                    
                    if row is not None:
                        # Verify Peak WSE
                        agent_peak = float(row.get("PeakWSE_ft", -999))
                        gt_peak = item["peak_wse"]
                        
                        # Verify Threshold
                        agent_thresh = float(row.get("ThresholdElevation_ft", -999))
                        gt_thresh = item["threshold"]
                        
                        # Verify Duration (Steps vs Hours)
                        # We don't know agent's timestep calc exactly, but we check consistency
                        # Duration = Steps * dt. Pct = Steps / TotalSteps
                        agent_pct = float(row.get("TimeAboveThreshold_pct", -999))
                        gt_pct = (item["steps_above_threshold"] / item["total_steps"]) * 100
                        
                        # Tolerances
                        peak_ok = abs(agent_peak - gt_peak) < 0.1
                        thresh_ok = abs(agent_thresh - gt_thresh) < 0.1
                        pct_ok = abs(agent_pct - gt_pct) < 5.0 # Allow 5% variance due to time step interpretation
                        
                        checks += 1
                        if peak_ok and thresh_ok and pct_ok:
                            matches += 1
                
                if checks > 0:
                    match_rate = matches / checks
                    if match_rate > 0.8:
                        score += 40
                        feedback.append("Data values match ground truth.")
                    elif match_rate > 0.5:
                        score += 20
                        feedback.append("Some data values match ground truth.")
                    else:
                        feedback.append(f"Data values incorrect (Match rate: {match_rate:.2f}).")
            else:
                # If ground truth failed to generate, give benefit of doubt if CSV looks reasonable
                if len(df) > 10 and df["FloodDuration_hours"].mean() > 0:
                    score += 30
                    feedback.append("Ground truth generation failed, but CSV looks reasonable.")
                    logger.warning("Ground truth invalid: " + str(ground_truth.get("error")))

        except Exception as e:
            feedback.append(f"Error parsing CSV: {str(e)}")

        return {
            "passed": score >= 60,
            "score": score,
            "feedback": " ".join(feedback)
        }