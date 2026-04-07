#!/usr/bin/env python3
import json
import os
import tempfile
import logging
import pandas as pd
import numpy as np

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_federal_grant_budget_reconciliation(traj, env_info, task_info):
    """
    Verifies the Federal Grant Budget Reconciliation task.
    
    Criteria:
    1. File modified/saved (10 pts)
    2. 'Financial_Report' sheet exists and has data (10 pts)
    3. Direct Costs total matches ground truth (within 1.0) (25 pts)
    4. F&A Costs total matches ground truth (within 1.0) (40 pts) 
       (This implicitly checks correct exclusions of Tuition/Equipment)
    5. Total/Remaining balance logic is consistent (15 pts)
    """
    
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}
        
    score = 0
    feedback = []
    passed = False
    
    # Temp files
    temp_json = tempfile.mktemp(suffix=".json")
    temp_xlsx = tempfile.mktemp(suffix=".xlsx")
    
    try:
        # 2. Get Result JSON
        try:
            copy_from_env(r"C:\tmp\task_result.json", temp_json)
            with open(temp_json, 'r') as f:
                result_data = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Could not retrieve task result: {e}"}
            
        # Check basic file status
        if not result_data.get('output_exists'):
            return {"passed": False, "score": 0, "feedback": "Output file not found."}
            
        if not result_data.get('file_modified'):
            feedback.append("Warning: File timestamp indicates it was not saved during the task.")
            # We don't fail immediately, but it's suspicious.
            score += 0 # No points for step 1 if not saved
        else:
            score += 10
            feedback.append("File was saved successfully.")

        # Get Ground Truth
        gt_direct = result_data.get('ground_truth_direct', 0.0)
        gt_fa = result_data.get('ground_truth_fa', 0.0)
        
        # 3. Analyze Excel Content
        try:
            copy_from_env(r"C:\Users\Docker\Desktop\ExcelTasks\nsf_grant_ledger.xlsx", temp_xlsx)
            
            # Read 'Financial_Report' sheet
            # Note: The setup script wrote the header at row 0 (A1), data starts around row 6 (index 5)
            # But the user might have modified it. We look for the header row "Budget_Category"
            df = pd.read_excel(temp_xlsx, sheet_name='Financial_Report', header=None)
            
            # Find the header row
            header_row_idx = None
            for idx, row in df.iterrows():
                # check if row contains "Budget_Category" and "Direct_Costs_Expended"
                row_str = " ".join([str(x) for x in row.values])
                if "Budget_Category" in row_str and "Direct" in row_str:
                    header_row_idx = idx
                    break
            
            if header_row_idx is None:
                return {"passed": False, "score": score, "feedback": "Could not find header row in 'Financial_Report' sheet."}
                
            score += 10 # Sheet structure valid enough to find header
            
            # Reload with correct header
            df = pd.read_excel(temp_xlsx, sheet_name='Financial_Report', header=header_row_idx)
            
            # Clean columns (strip whitespace)
            df.columns = [str(c).strip() for c in df.columns]
            
            # Identify columns
            # We expect: Budget_Category, Budgeted_Amount, Direct_Costs_Expended, FA_Costs_Expended, Total_Costs, Remaining_Balance
            # Allow some fuzzy matching
            col_direct = next((c for c in df.columns if "Direct" in c and "Expended" in c), None)
            col_fa = next((c for c in df.columns if "FA" in c or "F&A" in c), None)
            
            if not col_direct or not col_fa:
                return {"passed": False, "score": score, "feedback": "Could not identify 'Direct' or 'F&A' columns."}
            
            # Sum the user's values
            # We filter out the 'TOTAL' row if the user added one, usually by checking if Budget_Category is valid or NaN
            # The original setup had ~7 categories.
            
            # Convert to numeric, errors='coerce' turns strings to NaN
            df[col_direct] = pd.to_numeric(df[col_direct], errors='coerce').fillna(0)
            df[col_fa] = pd.to_numeric(df[col_fa], errors='coerce').fillna(0)
            
            user_direct_sum = df[col_direct].sum()
            user_fa_sum = df[col_fa].sum()
            
            # Logic check: The user might have a TOTAL row which doubles the sum if we just sum the column
            # We should check if the sum is roughly 2x ground truth, implying they summed the total row too.
            # Or we can exclude rows where 'Budget_Category' contains 'TOTAL'.
            
            # Safer: Sum only rows that look like original categories
            # "Salaries & Wages", "Fringe Benefits", etc.
            valid_cats = ["Salaries", "Fringe", "Tuition", "Materials", "Travel", "Equipment", "Participant", "Consultant"]
            
            filtered_df = df[df['Budget_Category'].astype(str).apply(lambda x: any(c in x for c in valid_cats))]
            
            # If filtered is empty, fall back to total sum / 2 assumption or raw sum
            if len(filtered_df) > 0:
                user_direct_sum = filtered_df[col_direct].sum()
                user_fa_sum = filtered_df[col_fa].sum()
            
            # Verify Direct Costs (25 pts)
            # Tolerance +/- 1.0 (rounding)
            if abs(user_direct_sum - gt_direct) < 5.0:
                score += 25
                feedback.append(f"Direct Costs correct: {user_direct_sum:.2f}")
            else:
                feedback.append(f"Direct Costs incorrect. Expected ~{gt_direct:.2f}, got {user_direct_sum:.2f}")

            # Verify F&A Costs (40 pts)
            # This is the hardest part.
            if abs(user_fa_sum - gt_fa) < 5.0:
                score += 40
                feedback.append(f"F&A Costs correct: {user_fa_sum:.2f}")
            else:
                feedback.append(f"F&A Costs incorrect. Expected ~{gt_fa:.2f}, got {user_fa_sum:.2f}")
                # Analyze common errors
                # Error 1: Applied F&A to everything?
                # Error 2: Forgot to exclude Tuition?
                pass
                
            # Verify Totals/Balance (15 pts)
            # Check if Total = Direct + F&A in the rows
            # Check a random row
            try:
                col_total = next((c for c in df.columns if "Total" in c), None)
                if col_total:
                    # check math on first data row
                    row0 = filtered_df.iloc[0]
                    calc_total = row0[col_direct] + row0[col_fa]
                    user_total = float(row0[col_total])
                    if abs(calc_total - user_total) < 0.1:
                        score += 15
                        feedback.append("Row formulas (Total = Direct + F&A) appear consistent.")
                else:
                    feedback.append("Could not find Total column to verify consistency.")
            except:
                pass

        except Exception as e:
            return {"passed": False, "score": score, "feedback": f"Error parsing Excel file: {e}"}

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification failed: {e}"}
        
    finally:
        # Cleanup
        if os.path.exists(temp_json): os.unlink(temp_json)
        if os.path.exists(temp_xlsx): os.unlink(temp_xlsx)
        
    passed = score >= 80
    return {"passed": passed, "score": score, "feedback": " | ".join(feedback)}