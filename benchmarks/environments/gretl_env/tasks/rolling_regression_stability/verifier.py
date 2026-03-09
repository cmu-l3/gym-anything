#!/usr/bin/env python3
"""
Verifier for rolling_regression_stability task.
Verifies that the agent performed a rolling OLS regression correctly by:
1. Checking existence of output CSV, Plot, and Script.
2. Comparing the agent's CSV numerical results against a ground truth CSV generated within the environment.
3. Checking that a loop was used in the script.
"""

import json
import os
import sys
import tempfile
import csv
import math
import logging
import base64

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_rolling_regression_stability(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # Temp files
    tmp_json = tempfile.mktemp(suffix=".json")
    tmp_agent_csv = tempfile.mktemp(suffix=".csv")
    tmp_gt_csv = tempfile.mktemp(suffix=".csv")

    score = 0
    max_score = 100
    feedback = []

    try:
        # 1. Fetch JSON result
        try:
            copy_from_env("/tmp/task_result.json", tmp_json)
            with open(tmp_json, 'r') as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}

        # 2. Check basic artifacts (30 points)
        if result.get("csv_exists"):
            score += 10
            feedback.append("Results CSV found.")
        else:
            feedback.append("Results CSV missing.")

        if result.get("plot_exists"):
            score += 10
            feedback.append("Plot found.")
        else:
            feedback.append("Plot missing.")

        if result.get("script_exists"):
            score += 10
            feedback.append("Script file found.")
        else:
            feedback.append("Script file missing.")

        # 3. Anti-gaming check (Files must be new)
        if not result.get("files_created_during_task", False):
            return {"passed": False, "score": 0, "feedback": "Files were not created during the task session (timestamps too old)."}

        # 4. Script Analysis (10 points)
        # Check if they actually wrote a loop
        if result.get("script_exists"):
            try:
                script_content = base64.b64decode(result.get("script_content_base64", "")).decode('utf-8', errors='ignore')
                if "loop" in script_content.lower() and "ols" in script_content.lower():
                    score += 10
                    feedback.append("Script logic looks correct (contains loop and ols).")
                else:
                    feedback.append("Script does not appear to contain required 'loop' or 'ols' commands.")
            except:
                feedback.append("Could not analyze script content.")

        # 5. Numerical Verification (60 points)
        # Compare agent CSV to Ground Truth CSV
        if result.get("csv_exists") and result.get("ground_truth_generated"):
            try:
                copy_from_env("/tmp/agent_results.csv", tmp_agent_csv)
                copy_from_env("/tmp/ground_truth.csv", tmp_gt_csv)
                
                agent_data = []
                with open(tmp_agent_csv, 'r') as f:
                    reader = csv.reader(f)
                    # Skip header if present, or detect it
                    rows = list(reader)
                    # Simple heuristic: if first row has letters, skip it
                    if rows and any(c.isalpha() for c in rows[0][0]):
                        rows = rows[1:]
                    
                    for row in rows:
                        # Extract numerical values. We expect 2 columns usually (coeff, se) or index+coeff+se
                        # We'll look for the first two valid floats in the row
                        nums = []
                        for cell in row:
                            try:
                                nums.append(float(cell))
                            except ValueError:
                                pass
                        if len(nums) >= 2:
                            agent_data.append(nums[:2]) # Keep first two (coeff, se)

                gt_data = []
                with open(tmp_gt_csv, 'r') as f:
                    reader = csv.reader(f)
                    rows = list(reader)
                    if rows and any(c.isalpha() for c in rows[0][0]):
                        rows = rows[1:]
                    for row in rows:
                        nums = []
                        for cell in row:
                            try:
                                nums.append(float(cell))
                            except ValueError:
                                pass
                        if len(nums) >= 2:
                            gt_data.append(nums[:2])

                # Comparison Logic
                # We check for overlap. The agent might have saved fewer rows or different range.
                # We check if a significant sequence of agent data matches a sequence in ground truth.
                
                matches = 0
                total_comparisons = 0
                
                if not agent_data:
                    feedback.append("Agent CSV contained no valid numerical data.")
                else:
                    # Try to align
                    # We iterate through GT and see if agent data starts matching
                    best_match_count = 0
                    
                    # Brute force alignment (datasets are small, ~100 rows)
                    for start_idx in range(len(gt_data)):
                        current_matches = 0
                        comparisons = 0
                        for i in range(min(len(agent_data), len(gt_data) - start_idx)):
                            a_coeff = agent_data[i][0]
                            g_coeff = gt_data[start_idx + i][0]
                            
                            # Tolerance 0.001
                            if abs(a_coeff - g_coeff) < 0.001:
                                current_matches += 1
                            comparisons += 1
                        
                        if current_matches > best_match_count:
                            best_match_count = current_matches
                            total_comparisons = comparisons

                    if total_comparisons > 0:
                        match_rate = best_match_count / len(agent_data)
                        if match_rate > 0.9: # 90% of agent rows match some sequence in GT
                            score += 60
                            feedback.append("Numerical results match ground truth data.")
                        elif match_rate > 0.5:
                            score += 30
                            feedback.append("Partial match of numerical results.")
                        else:
                            feedback.append(f"Numerical mismatch. Match rate: {match_rate:.2f}")
                            # log sample for debugging
                            if len(agent_data) > 0 and len(gt_data) > 0:
                                feedback.append(f"Sample Agent: {agent_data[0]}, Sample GT: {gt_data[0]}")
                    else:
                        feedback.append("Could not align data for comparison.")

            except Exception as e:
                feedback.append(f"Error during CSV comparison: {str(e)}")
        elif not result.get("ground_truth_generated"):
            feedback.append("Verification failed: Ground truth could not be generated.")

    finally:
        # Cleanup
        for fpath in [tmp_json, tmp_agent_csv, tmp_gt_csv]:
            if os.path.exists(fpath):
                os.remove(fpath)

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback)
    }