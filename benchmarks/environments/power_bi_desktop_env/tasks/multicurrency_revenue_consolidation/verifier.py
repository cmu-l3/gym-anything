#!/usr/bin/env python3
"""
Verifier for multicurrency_revenue_consolidation task.

Verifies:
1. Consolidated_Revenue.pbix exists and was saved during task.
2. revenue_by_currency.csv exists.
3. The calculated USD totals in the CSV match the Ground Truth (recalculated from source data).

Method:
- Copies source CSVs (rates, transactions) from the env to recalculate ground truth.
- Copies output CSV from env.
- Compares values with tolerance.
"""

import json
import os
import tempfile
import logging
import pandas as pd
import numpy as np

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_multicurrency_revenue(traj, env_info, task_info):
    """
    Verify the Power BI multi-currency consolidation task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Define paths
    result_json_remote = "C:/workspace/task_result.json"
    
    # Create temp dir for files
    with tempfile.TemporaryDirectory() as temp_dir:
        # 1. Get Result JSON
        local_result_json = os.path.join(temp_dir, "task_result.json")
        try:
            copy_from_env(result_json_remote, local_result_json)
            with open(local_result_json, 'r') as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}

        # Check critical artifacts first
        pbix_exists = result.get("pbix_exists", False)
        csv_exists = result.get("csv_exists", False)
        
        score = 0
        feedback = []

        # PBIX Check (10 pts)
        if pbix_exists:
            score += 10
            feedback.append("PBIX file saved.")
        else:
            feedback.append("PBIX file not found.")

        # CSV Check (15 pts)
        if csv_exists:
            score += 15
            feedback.append("Output CSV found.")
        else:
            feedback.append("Output CSV not found.")
            return {"passed": False, "score": score, "feedback": " ".join(feedback)}

        # 2. Retrieve Data Files for Ground Truth Calculation
        try:
            # Copy source files
            local_rates = os.path.join(temp_dir, "daily_rates.csv")
            local_trans = os.path.join(temp_dir, "sales_transactions.csv")
            local_output = os.path.join(temp_dir, "revenue_by_currency.csv")
            
            # Paths from metadata or result
            remote_rates = result.get("data_path_rates", "C:/Users/Docker/Desktop/PowerBITasks/daily_rates.csv")
            remote_trans = result.get("data_path_trans", "C:/Users/Docker/Desktop/PowerBITasks/sales_transactions.csv")
            remote_output = "C:/Users/Docker/Desktop/revenue_by_currency.csv"

            copy_from_env(remote_rates, local_rates)
            copy_from_env(remote_trans, local_trans)
            copy_from_env(remote_output, local_output)
            
            # Load Data
            df_rates = pd.read_csv(local_rates)
            df_trans = pd.read_csv(local_trans)
            df_agent = pd.read_csv(local_output)

        except Exception as e:
            return {"passed": False, "score": score, "feedback": f"Failed to retrieve data files for verification: {e}"}

        # 3. Calculate Ground Truth
        try:
            # Normalize column names/types
            df_rates['Date'] = pd.to_datetime(df_rates['Date'])
            df_trans['Date'] = pd.to_datetime(df_trans['Date'])
            
            # Merge to find correct rate for each transaction
            # Note: This is a Left Join on [Date, Currency]
            df_merged = pd.merge(df_trans, df_rates, on=['Date', 'Currency'], how='left')
            
            # Calculate USD Amount
            df_merged['USD_Calculated'] = df_merged['Amount'] * df_merged['RateToUSD']
            
            # Group by Currency
            ground_truth = df_merged.groupby('Currency')['USD_Calculated'].sum().to_dict()
            total_ground_truth = df_merged['USD_Calculated'].sum()
            
        except Exception as e:
            return {"passed": False, "score": score, "feedback": f"Error calculating ground truth: {e}"}

        # 4. Compare Agent Output to Ground Truth
        try:
            # Normalize agent output
            # Agent CSV might use different headers depending on visual config, likely "Currency" and "Total_Revenue_USD"
            # We look for the numeric column and the text column
            agent_cols = df_agent.columns
            num_col = next((c for c in agent_cols if pd.api.types.is_numeric_dtype(df_agent[c]) or "Revenue" in c or "USD" in c), None)
            curr_col = next((c for c in agent_cols if "Currency" in c or "curr" in c.lower()), None)
            
            if not num_col or not curr_col:
                 # Fallback: try parsing index if currency is index
                 feedback.append("Could not identify columns in output CSV.")
                 valid_structure = False
            else:
                valid_structure = True
            
            if valid_structure:
                # Clean currency column and numbers
                df_agent[num_col] = pd.to_numeric(df_agent[num_col], errors='coerce').fillna(0)
                agent_results = dict(zip(df_agent[curr_col], df_agent[num_col]))
                
                # Check Total Accuracy (35 pts)
                agent_total = sum(agent_results.values())
                diff_pct = abs(agent_total - total_ground_truth) / total_ground_truth if total_ground_truth else 0
                
                if diff_pct < 0.015: # 1.5% tolerance
                    score += 35
                    feedback.append(f"Total Revenue accurate (Agent: {agent_total:,.2f}, GT: {total_ground_truth:,.2f}).")
                else:
                    feedback.append(f"Total Revenue mismatch (Agent: {agent_total:,.2f}, GT: {total_ground_truth:,.2f}).")

                # Check Breakdown Accuracy (20 pts)
                # Check at least EUR and GBP specifically
                breakdown_ok = True
                for curr in ['EUR', 'GBP']:
                    if curr in ground_truth:
                        gt_val = ground_truth[curr]
                        ag_val = agent_results.get(curr, 0)
                        
                        if gt_val > 0:
                            curr_diff = abs(ag_val - gt_val) / gt_val
                            if curr_diff > 0.02: # 2% tolerance per currency
                                breakdown_ok = False
                                feedback.append(f"{curr} conversion mismatch.")
                
                if breakdown_ok:
                    score += 20
                    feedback.append("Currency breakdown accurate.")
                    
                # Measure defined check (20 pts)
                # We can't easily check inside the binary on Linux without heavy tools, 
                # but if the values are correct, they likely defined the measure.
                # We award these points if the calculation is correct.
                if diff_pct < 0.015 and breakdown_ok:
                    score += 20
                    feedback.append("Implied: DAX measure defined correctly.")
                else:
                    feedback.append("Calculations incorrect, DAX measure likely wrong.")

        except Exception as e:
            feedback.append(f"Error comparing results: {e}")

    # Final verdict
    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }