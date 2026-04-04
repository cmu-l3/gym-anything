#!/usr/bin/env python3
"""
Verifier for data_frequency_conversion task.

Checks:
1. File existence and creation time.
2. Data structure (Rows=25 for 1984-2008, Columns).
3. Aggregation logic (Quarterly -> Annual Average).
4. Calculation logic (Log difference growth rate).
"""

import json
import os
import tempfile
import logging
import pandas as pd
import numpy as np

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_data_frequency_conversion(traj, env_info, task_info):
    """
    Verify the Annualization and Growth Rate calculation task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Metadata & Result JSON
    metadata = task_info.get('metadata', {})
    expected_rows = metadata.get('expected_rows', 25)
    
    temp_result_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result_json.name)
        with open(temp_result_json.name, 'r') as f:
            result_info = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_result_json.name):
            os.unlink(temp_result_json.name)

    # Basic Checks
    if not result_info.get('output_exists'):
        return {"passed": False, "score": 0, "feedback": "Output CSV file was not created."}
    
    if not result_info.get('file_created_during_task'):
        return {"passed": False, "score": 0, "feedback": "Output file exists but was not created/modified during this task session."}

    # 2. Retrieve Agent's CSV
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    try:
        copy_from_env("/tmp/agent_output.csv", temp_csv.name)
        df_agent = pd.read_csv(temp_csv.name)
    except Exception as e:
        return {"passed": False, "score": 10, "feedback": f"Output file exists but could not be parsed as CSV: {e}"}
    finally:
        if os.path.exists(temp_csv.name):
            os.unlink(temp_csv.name)

    # Clean up column names (strip whitespace, lowercase)
    df_agent.columns = [c.strip().lower() for c in df_agent.columns]

    score = 15  # Base score for creating valid CSV
    feedback = ["CSV created and readable."]

    # 3. Verify Columns
    required_cols = ['gdp', 'inf', 'gdp_growth']
    missing_cols = [c for c in required_cols if c not in df_agent.columns]
    
    if not missing_cols:
        score += 15
        feedback.append("All required columns present.")
    else:
        feedback.append(f"Missing columns: {missing_cols}")
        # If crucial columns missing, we might stop or penalize heavily
        if 'gdp' not in df_agent.columns or 'gdp_growth' not in df_agent.columns:
            return {"passed": False, "score": score, "feedback": " ".join(feedback)}

    # 4. Verify Row Count (Duration 1984-2008 = 25 years)
    # Allow small tolerance if headers cause off-by-one, but exact is expected
    rows = len(df_agent)
    if rows == expected_rows:
        score += 20
        feedback.append(f"Correct row count ({rows}).")
    elif rows == expected_rows + 1: # Maybe 2009 included
        score += 10
        feedback.append(f"Row count slightly off ({rows}), possibly included partial 2009 data.")
    else:
        feedback.append(f"Incorrect row count: {rows} (Expected {expected_rows}).")

    # 5. Verify Aggregation Logic (Quarterly -> Annual Average)
    # We reconstruct the ground truth for the first few years to verify.
    # Data source: USA.gdt (subset)
    # 1984 Q1-Q4 GDP values from the real dataset (approximate/known values for verification)
    # 1984: 6735.6, 6890.3, 7016.2, 7120.3 -> Avg: 6940.6
    # 1985: 7215.1, 7292.0, 7425.2, 7486.2 -> Avg: 7354.625
    # We verify the first few rows to ensure method "Average" was used, not "Sum".
    
    # Ground truth samples (Year: Expected_GDP)
    # These are derived from the usa.gdt dataset usually found in Gretl
    gt_gdp = {
        0: 6940.6, # 1984
        1: 7354.6, # 1985
        24: 13312.8 # 2008 (Last year check)
    }
    
    aggregation_passed = True
    
    if 'gdp' in df_agent.columns:
        agent_gdp = df_agent['gdp'].tolist()
        for idx, expected in gt_gdp.items():
            if idx < len(agent_gdp):
                val = agent_gdp[idx]
                # Check for Average (correct) vs Sum (incorrect)
                if abs(val - expected) < 1.0:
                    pass # Correct
                elif abs(val - (expected * 4)) < 4.0:
                    aggregation_passed = False
                    feedback.append("GDP values look like SUM instead of AVERAGE.")
                    break
                else:
                    aggregation_passed = False
                    feedback.append(f"GDP value mismatch at index {idx}: Got {val}, Expected ~{expected}.")
                    break
            else:
                aggregation_passed = False
                feedback.append("Data too short to verify specific years.")
                break
    
    if aggregation_passed:
        score += 25
        feedback.append("Annual aggregation (Average) appears correct.")
    
    # 6. Verify Growth Rate Calculation
    # Formula: 100 * (ln(gdp_t) - ln(gdp_{t-1}))
    # We check internal consistency of the Agent's file.
    # Even if their aggregation was wrong, if the math is consistent, they get partial points.
    
    calculation_passed = True
    if 'gdp_growth' in df_agent.columns and 'gdp' in df_agent.columns:
        agent_gdp = df_agent['gdp'].astype(float).tolist()
        agent_growth = df_agent['gdp_growth'].astype(float).tolist()
        
        # Check a few random points (starting from index 1, as index 0 has no previous)
        valid_checks = 0
        for i in range(1, len(agent_gdp)):
            if pd.isna(agent_growth[i]) or pd.isna(agent_gdp[i]) or pd.isna(agent_gdp[i-1]):
                continue
            
            # Calculate expected growth based on THEIR gdp values
            # Prevent log(0)
            if agent_gdp[i] <= 0 or agent_gdp[i-1] <= 0:
                continue

            expected_growth = 100 * (np.log(agent_gdp[i]) - np.log(agent_gdp[i-1]))
            
            if abs(agent_growth[i] - expected_growth) > 0.05:
                # Also check standard percentage change: 100 * (current - prev) / prev
                alt_growth = 100 * ((agent_gdp[i] - agent_gdp[i-1]) / agent_gdp[i-1])
                if abs(agent_growth[i] - alt_growth) < 0.05:
                     feedback.append(f"Used standard % change formula instead of log difference at row {i}.")
                     # We might penalize slightly or accept if ambiguous, but task said log diff.
                     # Task explicitly said: "Use the formula: 100 * (ln(gdp) - ln(gdp(-1)))"
                     calculation_passed = False
                     break
                else:
                    calculation_passed = False
                    feedback.append(f"Growth calculation incorrect at row {i}. Got {agent_growth[i]}, Expected log-diff {expected_growth:.4f}.")
                    break
            valid_checks += 1
            
        if valid_checks > 0 and calculation_passed:
            score += 25
            feedback.append("Growth rate formula (Log Difference) applied correctly.")
        elif valid_checks == 0:
             feedback.append("Could not verify growth rate (insufficient data/NaNs).")
    else:
        calculation_passed = False
        feedback.append("Cannot verify growth calculation (missing columns).")

    # Final result
    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }