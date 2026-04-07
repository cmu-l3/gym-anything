#!/usr/bin/env python3
"""
Verifier for fleet_vehicle_replacement_analysis task.

Verifies:
1. Data Aggregation: Correct total maintenance calculated from logs.
2. Logic: Correct Status determination (REPLACE vs KEEP).
3. Budgeting: Correct Total Budget calculation.
4. File Stats: File was modified.
"""

import json
import os
import tempfile
import logging
import pandas as pd
import numpy as np

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_fleet_analysis(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # Setup paths
    task_result_path = "C:\\workspace\\tasks\\fleet_vehicle_replacement_analysis\\task_result.json"
    excel_path = "C:\\Users\\Docker\\Documents\\fleet_analysis.xlsx"
    
    score = 0
    feedback = []
    
    # 1. Get execution metadata
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(task_result_path, temp_json.name)
        with open(temp_json.name, 'r') as f:
            exec_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)
            
    if not exec_result.get('output_exists'):
        return {"passed": False, "score": 0, "feedback": "Excel file not found"}
        
    if not exec_result.get('file_modified_during_task'):
        feedback.append("Warning: File not modified during task (timestamps unchanged)")
    
    # 2. Analyze Excel Content
    temp_xlsx = tempfile.NamedTemporaryFile(delete=False, suffix='.xlsx')
    try:
        copy_from_env(excel_path, temp_xlsx.name)
        
        # Load Data
        try:
            df_inv = pd.read_excel(temp_xlsx.name, sheet_name='Inventory')
            df_log = pd.read_excel(temp_xlsx.name, sheet_name='Maint_Log')
            df_pol = pd.read_excel(temp_xlsx.name, sheet_name='Policy', header=None)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Could not read Excel sheets: {e}"}
            
        # --- GROUND TRUTH CALCULATION ---
        
        # 1. Aggregate Costs
        # Group log by VIN and sum Cost
        # Clean VINs (strip whitespace)
        df_log['VIN'] = df_log['VIN'].astype(str).str.strip()
        df_inv['VIN'] = df_inv['VIN'].astype(str).str.strip()
        
        gt_costs = df_log.groupby('VIN')['Cost'].sum()
        
        # 2. Calculate Metrics
        current_year = 2025
        df_inv['GT_Maint'] = df_inv['VIN'].map(gt_costs).fillna(0)
        df_inv['GT_Age'] = current_year - df_inv['Year']
        # Handle zero division for new cars
        df_inv['GT_CPM'] = df_inv.apply(lambda row: row['GT_Maint'] / row['Odometer'] if row['Odometer'] > 0 else 0, axis=1)
        
        # 3. Apply Logic
        # REPLACE if: Age >= 8 OR Odo >= 200k OR CPM >= 0.12
        def get_status(row):
            cond_eol = (row['GT_Age'] >= 8) or (row['Odometer'] >= 200000)
            cond_cost = (row['GT_CPM'] >= 0.12)
            return "REPLACE" if (cond_eol or cond_cost) else "KEEP"
            
        df_inv['GT_Status'] = df_inv.apply(get_status, axis=1)
        
        gt_replace_count = (df_inv['GT_Status'] == "REPLACE").sum()
        gt_budget = gt_replace_count * 58000
        
        # --- SCORING ---
        
        # Criterion 1: Maintenance Aggregation (30 pts)
        # Check if 'Total Maint Cost' column exists and matches
        maint_col_candidates = [c for c in df_inv.columns if 'maint' in c.lower() and 'cost' in c.lower()]
        if maint_col_candidates:
            user_maint = df_inv[maint_col_candidates[0]]
            # Compare with tolerance
            # Replace non-numeric with 0
            user_maint = pd.to_numeric(user_maint, errors='coerce').fillna(0)
            
            # Check correlation or absolute difference
            # Allow small diffs
            matches = np.isclose(user_maint, df_inv['GT_Maint'], atol=1.0)
            match_pct = matches.mean()
            
            if match_pct > 0.9:
                score += 30
                feedback.append("Maintenance costs aggregated correctly")
            elif match_pct > 0.5:
                score += 15
                feedback.append(f"Maintenance costs partially correct ({match_pct:.1%} match)")
            else:
                feedback.append("Maintenance costs incorrect")
        else:
            feedback.append("Could not find 'Total Maint Cost' column")
            
        # Criterion 2: Metric Calculation (Age, CPM) (20 pts)
        # Check Age
        age_score = 0
        age_cols = [c for c in df_inv.columns if 'age' in c.lower()]
        if age_cols:
            user_age = pd.to_numeric(df_inv[age_cols[0]], errors='coerce').fillna(0)
            if np.isclose(user_age, df_inv['GT_Age'], atol=0.1).mean() > 0.9:
                age_score = 10
        
        # Check CPM
        cpm_score = 0
        cpm_cols = [c for c in df_inv.columns if 'cpm' in c.lower() or 'mile' in c.lower()]
        if cpm_cols:
            user_cpm = pd.to_numeric(df_inv[cpm_cols[0]], errors='coerce').fillna(0)
            if np.isclose(user_cpm, df_inv['GT_CPM'], atol=0.01).mean() > 0.9:
                cpm_score = 10
                
        score += (age_score + cpm_score)
        if age_score + cpm_score == 20:
            feedback.append("Derived metrics (Age, CPM) correct")
        
        # Criterion 3: Logic Implementation (30 pts)
        # Check Status column
        status_cols = [c for c in df_inv.columns if 'status' in c.lower()]
        if status_cols:
            user_status = df_inv[status_cols[0]].astype(str).str.upper().str.strip()
            # Compare
            status_match = (user_status == df_inv['GT_Status']).mean()
            
            if status_match > 0.9:
                score += 30
                feedback.append("Replacement logic applied correctly")
            elif status_match > 0.7:
                score += 15
                feedback.append(f"Replacement logic partially correct ({status_match:.1%})")
            else:
                feedback.append("Replacement logic failed")
        else:
            feedback.append("Status column not found")
            
        # Criterion 4: Budget Accuracy (20 pts)
        # Look for the budget in Policy sheet
        # Usually cell H2, but let's search the whole sheet for the number
        found_budget = False
        
        # Convert sheet to string values and search for numeric budget
        # Budget is likely > 100,000
        policy_values = df_pol.values.flatten()
        
        for val in policy_values:
            try:
                # remove currency symbols
                clean_val = str(val).replace('$','').replace(',','')
                num_val = float(clean_val)
                if np.isclose(num_val, gt_budget, atol=58000): # Allow off by 1 car
                    found_budget = True
                    break
            except:
                continue
                
        if found_budget:
            score += 20
            feedback.append(f"Total budget correct (Found approx {gt_budget})")
        else:
            feedback.append(f"Total budget incorrect (Expected {gt_budget})")

    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Verification error: {e}"}
    finally:
        if os.path.exists(temp_xlsx.name):
            os.unlink(temp_xlsx.name)
            
    return {
        "passed": score >= 80,
        "score": score,
        "feedback": " | ".join(feedback)
    }