#!/usr/bin/env python3
"""
Verifier for hospital_daily_census task.

Checks:
1. PBIX file exists and was created during task.
2. Exported CSV exists.
3. Exported CSV data matches ground truth census curve.

The Census logic (Events in Progress) produces a very specific curve that is
unlikely to be matched by simple aggregations (like Count of Admit Date).
Matching the ground truth is strong evidence of correct DAX implementation.
"""

import json
import os
import tempfile
import pandas as pd
import logging
from io import StringIO

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_hospital_daily_census(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # 1. Retrieve Result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json').name
    try:
        copy_from_env("/tmp/task_result.json", temp_result)
        with open(temp_result, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_result): os.unlink(temp_result)

    score = 0
    feedback = []
    passed = False

    # 2. Verify PBIX (10 pts)
    if result_data.get("pbix_exists", False):
        score += 10
        feedback.append("PBIX file saved.")
    else:
        feedback.append("PBIX file not found.")

    # 3. Verify CSV Existence (10 pts)
    csv_exists = result_data.get("csv_exists", False)
    if csv_exists:
        score += 10
        feedback.append("Exported CSV found.")
    else:
        feedback.append("Exported CSV not found.")

    # 4. Verify Data Accuracy (80 pts)
    # We need to compare the agent's CSV against the ground truth CSV
    if csv_exists:
        agent_csv_local = tempfile.NamedTemporaryFile(delete=False, suffix='.csv').name
        gt_csv_local = tempfile.NamedTemporaryFile(delete=False, suffix='.csv').name
        
        try:
            # Copy files
            copy_from_env(result_data["agent_csv_path"], agent_csv_local)
            copy_from_env(result_data["ground_truth_path"], gt_csv_local)
            
            # Load DataFrames
            # Agent CSV might have varying headers depending on visual config, usually "Date" and "Daily_Census"
            # We'll try to sniff headers or just look at columns
            try:
                df_agent = pd.read_csv(agent_csv_local)
                df_gt = pd.read_csv(gt_csv_local) # Columns: Date, Census
                
                # Normalize Agent Data
                # Assume column 0 is Date, column 1 is Value
                if df_agent.shape[1] < 2:
                    raise ValueError("Agent CSV has fewer than 2 columns")
                
                # Rename for consistency
                df_agent.columns = ['Date', 'Value']
                df_gt.columns = ['Date', 'Value']
                
                # Coerce Dates
                df_agent['Date'] = pd.to_datetime(df_agent['Date'], errors='coerce')
                df_gt['Date'] = pd.to_datetime(df_gt['Date'], errors='coerce')
                
                # Drop NaTs
                df_agent = df_agent.dropna(subset=['Date'])
                
                # Merge to compare
                merged = pd.merge(df_gt, df_agent, on='Date', how='inner', suffixes=('_gt', '_agent'))
                
                if len(merged) < 100:
                    feedback.append(f"Agent data too sparse. Matched only {len(merged)} days.")
                else:
                    # Calculate error
                    # Mean Absolute Error or Correlation
                    merged['Diff'] = abs(merged['Value_gt'] - merged['Value_agent'])
                    mae = merged['Diff'].mean()
                    mean_census = merged['Value_gt'].mean()
                    
                    # Error Tolerance: 5% of mean census
                    tolerance = mean_census * 0.05
                    
                    if mae <= tolerance:
                        score += 80
                        feedback.append(f"Data matches ground truth! MAE: {mae:.2f} (Tol: {tolerance:.2f})")
                        passed = True
                    else:
                        # Partial credit for being close (maybe slight filter diff)
                        if mae <= tolerance * 3:
                            score += 40
                            feedback.append(f"Data is close but not exact. MAE: {mae:.2f}. Check 'Inpatient' filter or dates.")
                        else:
                            feedback.append(f"Data does not match 'Events in Progress' logic. MAE: {mae:.2f}. Likely used simple Admit count.")
                            
            except Exception as e:
                feedback.append(f"Error parsing CSV data: {str(e)}")
                
        except Exception as e:
            feedback.append(f"Error copying/reading verification files: {str(e)}")
        finally:
            if os.path.exists(agent_csv_local): os.unlink(agent_csv_local)
            if os.path.exists(gt_csv_local): os.unlink(gt_csv_local)

    # Final Score calc
    final_score = min(100, score)
    # Passed if score >= 70 (Requires good data match)
    is_passing = final_score >= 70

    return {
        "passed": is_passing,
        "score": final_score,
        "feedback": " ".join(feedback)
    }