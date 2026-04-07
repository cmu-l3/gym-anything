#!/usr/bin/env python3
"""
Verifier for Vendor Fraud Detection (Benford's Law) task.

Verification Strategy:
1. Load the original input data (vendor_payments.xlsx) and calculate Ground Truth Benford stats.
   - Filter Amount >= 10, remove negative/zero.
   - Extract leading digits.
   - Identify expected 'highest deviation' digit and top vendors.
2. Load the agent's output file (fraud_analysis_complete.xlsx).
3. Verify 'Benford_Analysis' sheet:
   - Check if table matches ground truth calculation (tolerance +/- 0.5%).
   - Check if Chart object exists.
4. Verify 'Suspicious_Activity' sheet:
   - Check if the identified anomalous digit matches ground truth.
   - Check if the listed vendors match the top spenders for that digit.
"""

import json
import os
import tempfile
import logging
import math
import pandas as pd
import numpy as np
from collections import Counter

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_vendor_fraud_detection(traj, env_info, task_info):
    """
    Verify the Benford's Law analysis task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Define paths
    input_path = "C:\\workspace\\data\\vendor_payments.xlsx"
    output_path = "C:\\workspace\\data\\fraud_analysis_complete.xlsx"
    result_json_path = "C:\\tmp\\task_result.json"

    # Setup temp directory for analysis
    temp_dir = tempfile.mkdtemp()
    local_input = os.path.join(temp_dir, "input.xlsx")
    local_output = os.path.join(temp_dir, "output.xlsx")
    local_json = os.path.join(temp_dir, "result.json")

    score = 0
    feedback = []

    try:
        # 1. Retrieve Files
        try:
            copy_from_env(result_json_path, local_json)
            with open(local_json, 'r') as f:
                task_result = json.load(f)
        except Exception:
            return {"passed": False, "score": 0, "feedback": "Failed to retrieve task result JSON."}

        if not task_result.get('output_exists'):
            return {"passed": False, "score": 0, "feedback": "Output file not found."}

        if not task_result.get('file_created_during_task'):
            # Anti-gaming: File must be new/modified
            return {"passed": False, "score": 0, "feedback": "Output file was not modified during the task."}
        
        score += 10 # Basic file existence points

        try:
            copy_from_env(input_path, local_input)
            copy_from_env(output_path, local_output)
        except Exception as e:
            return {"passed": False, "score": score, "feedback": f"Failed to retrieve Excel files: {str(e)}"}

        # 2. Calculate Ground Truth (from input file)
        try:
            df_in = pd.read_excel(local_input)
            
            # Data Cleaning Logic
            # Assuming 'AMOUNT' column exists, if not find best match
            amt_col = next((c for c in df_in.columns if 'amount' in str(c).lower()), None)
            vendor_col = next((c for c in df_in.columns if 'vendor' in str(c).lower()), None)
            
            if not amt_col:
                return {"passed": False, "score": score, "feedback": "Could not verify: Input file structure unknown (no Amount column)."}

            # Filter: >= 10, valid numbers
            df_clean = df_in[pd.to_numeric(df_in[amt_col], errors='coerce') >= 10].copy()
            df_clean['LeadingDigit'] = df_clean[amt_col].astype(str).str.replace(r'[^0-9.]', '', regex=True).str.lstrip('0').str[0]
            
            # Filter valid digits 1-9
            df_clean = df_clean[df_clean['LeadingDigit'].isin([str(d) for d in range(1, 10)])]
            
            total_count = len(df_clean)
            if total_count == 0:
                 return {"passed": False, "score": score, "feedback": "Input data invalid (no valid rows)."}

            # Calculate Actual Distribution
            counts = df_clean['LeadingDigit'].value_counts()
            actual_dist = {int(d): counts.get(str(d), 0) / total_count for d in range(1, 10)}
            
            # Calculate Benford Expected
            benford_dist = {d: math.log10(1 + 1/d) for d in range(1, 10)}
            
            # Find Max Deviation
            deviations = {d: actual_dist[d] - benford_dist[d] for d in range(1, 10)}
            max_dev_digit = max(deviations, key=deviations.get) # Digit with highest (positive) deviation
            
            # Get Top Vendors for that digit
            suspect_df = df_clean[df_clean['LeadingDigit'] == str(max_dev_digit)]
            top_vendors_gt = suspect_df.groupby(vendor_col)[amt_col].sum().sort_values(ascending=False).head(5).index.tolist()
            
        except Exception as e:
            return {"passed": False, "score": score, "feedback": f"Error calculating ground truth: {str(e)}"}

        # 3. Verify Agent's Analysis
        try:
            # Check Sheet 1: Benford_Analysis
            xls = pd.ExcelFile(local_output)
            sheet_names = [s.lower() for s in xls.sheet_names]
            
            if 'benford_analysis' not in sheet_names:
                feedback.append("Missing 'Benford_Analysis' sheet.")
            else:
                score += 10
                df_out_analysis = pd.read_excel(local_output, sheet_name=next(s for s in xls.sheet_names if s.lower() == 'benford_analysis'))
                
                # Check for digit column (1-9)
                # We expect a table with Digits, Actual %, Expected %
                # We'll heuristic match
                # Check if the agent calculated values close to our ground truth
                
                # Convert dataframe to string to search for values
                content_str = df_out_analysis.to_string()
                
                # Check if correct expected percentages appear (30.1%, 17.6%...)
                # Allow some formatting variance
                matches_benford = 0
                for d in [1, 9]: # Check endpoints
                    val = benford_dist[d] * 100
                    # Look for value in dataframe (roughly)
                    found = False
                    for col in df_out_analysis.columns:
                        for item in df_out_analysis[col]:
                            try:
                                if isinstance(item, (int, float)) and abs(item - val) < 1.0: found = True # 30.1 vs 30
                                if isinstance(item, (int, float)) and abs(item - (val/100)) < 0.01: found = True # 0.301 vs 0.30
                            except: pass
                    if found: matches_benford += 1
                
                if matches_benford >= 1:
                    score += 20
                    feedback.append("Benford calculations verified.")
                else:
                    feedback.append("Benford expected values not found in analysis.")

                # Check for Actuals
                # Check the actual % for digit 1
                gt_d1 = actual_dist[1] * 100
                found_actual = False
                for col in df_out_analysis.columns:
                    for item in df_out_analysis[col]:
                        try:
                            if isinstance(item, (int, float)) and abs(item - gt_d1) < 1.0: found_actual = True
                            if isinstance(item, (int, float)) and abs(item - (gt_d1/100)) < 0.01: found_actual = True
                        except: pass
                
                if found_actual:
                    score += 20
                    feedback.append("Actual frequency calculations verified.")
                else:
                    feedback.append("Actual frequency values mismatch ground truth.")

            # Check Sheet 2: Suspicious_Activity
            if 'suspicious_activity' not in sheet_names:
                feedback.append("Missing 'Suspicious_Activity' sheet.")
            else:
                score += 10
                df_suspicious = pd.read_excel(local_output, sheet_name=next(s for s in xls.sheet_names if s.lower() == 'suspicious_activity'))
                
                # Convert to string to find the anomalous digit
                suspicious_str = df_suspicious.to_string().lower()
                
                # Check if the Max Deviation Digit is present
                if str(max_dev_digit) in suspicious_str:
                    score += 15
                    feedback.append(f"Correctly identified anomalous digit: {max_dev_digit}.")
                else:
                    feedback.append(f"Failed to identify correct anomalous digit ({max_dev_digit}).")

                # Check for top vendors
                # We allow partial matching of vendor names
                vendors_found = 0
                for vendor in top_vendors_gt:
                    if str(vendor).lower() in suspicious_str:
                        vendors_found += 1
                
                if vendors_found >= 1:
                    score += 15
                    feedback.append(f"Identified top vendors correctly ({vendors_found}/5).")
                else:
                    feedback.append("Top vendors for the anomalous digit not found.")

        except Exception as e:
            feedback.append(f"Error analyzing output file: {str(e)}")

    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"System error: {str(e)}"}
    finally:
        # Cleanup
        try:
            import shutil
            shutil.rmtree(temp_dir)
        except: pass

    passed = score >= 85
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }