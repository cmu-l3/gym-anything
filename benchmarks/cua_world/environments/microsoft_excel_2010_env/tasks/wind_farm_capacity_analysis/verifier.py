#!/usr/bin/env python3
"""
Verifier for wind_farm_capacity_analysis task.

Verifies:
1. Turbine_Annual_Summary calculations (SUMIF logic, CF formulas, Revenue, Availability).
2. Monthly_Farm_Summary calculations (Wake loss, Front/Back comparison).
3. Correct use of formulas (not hardcoded values) - inferred by recalculating and matching.
4. Correct categorization of Underperforming turbines.

Uses pandas and openpyxl to process the Excel file.
"""

import json
import os
import tempfile
import logging
import pandas as pd
import numpy as np
from openpyxl import load_workbook

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_wind_farm_capacity_analysis(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # Copy result JSON and Excel file
    temp_dir = tempfile.mkdtemp()
    result_json_path = os.path.join(temp_dir, "task_result.json")
    excel_path = os.path.join(temp_dir, "wind_farm_production.xlsx")
    
    try:
        copy_from_env("C:\\Users\\Docker\\task_result.json", result_json_path)
        with open(result_json_path, 'r') as f:
            res_data = json.load(f)
            
        if not res_data.get('file_exists'):
            return {"passed": False, "score": 0, "feedback": "Excel file not found"}
            
        if not res_data.get('is_modified'):
            return {"passed": False, "score": 0, "feedback": "File was not modified after task start"}
            
        copy_from_env("C:\\Users\\Docker\\Documents\\wind_farm_production.xlsx", excel_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve files: {e}"}

    # Load Data using Pandas (read_excel uses openpyxl)
    try:
        # Read Input Data
        df_prod = pd.read_excel(excel_path, sheet_name="Turbine_Production")
        
        # Read Agent Output Sheets
        df_annual = pd.read_excel(excel_path, sheet_name="Turbine_Annual_Summary", header=0)
        df_monthly = pd.read_excel(excel_path, sheet_name="Monthly_Farm_Summary", header=0)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read Excel sheets: {e}"}

    score = 0
    feedback = []

    # --- RECALCULATE GROUND TRUTH ---
    
    # 1. Annual Summary Truth
    # Group by Turbine_ID
    annual_truth = df_prod.groupby('Turbine_ID').agg({
        'Actual_Production_MWh': 'sum',
        'Hours_In_Month': 'sum',
        'Downtime_Hours': 'sum',
        'Nameplate_MW': 'first', # Should be 2.5
        'Turbine_Row': 'first'
    }).reset_index()
    
    annual_truth['Available_Hours'] = annual_truth['Hours_In_Month'] - annual_truth['Downtime_Hours']
    annual_truth['Availability_Pct'] = (annual_truth['Available_Hours'] / annual_truth['Hours_In_Month']) * 100
    annual_truth['Gross_CF'] = (annual_truth['Actual_Production_MWh'] / (annual_truth['Nameplate_MW'] * annual_truth['Hours_In_Month'])) * 100
    annual_truth['Net_CF'] = (annual_truth['Actual_Production_MWh'] / (annual_truth['Nameplate_MW'] * annual_truth['Available_Hours'])) * 100
    annual_truth['Revenue'] = annual_truth['Actual_Production_MWh'] * 45
    
    def get_flag(cf):
        if cf < 28: return "UNDERPERFORMING"
        if cf < 32: return "REVIEW"
        return np.nan # Pandas uses nan for empty

    annual_truth['Flag'] = annual_truth['Gross_CF'].apply(get_flag)

    # --- VERIFY SHEET 1: Turbine_Annual_Summary ---
    
    # Clean agent data (remove total row if present)
    df_annual_clean = df_annual[df_annual['Turbine_ID'].astype(str).str.startswith('WT')].copy().reset_index(drop=True)
    
    if len(df_annual_clean) != 20:
        feedback.append(f"Expected 20 turbine rows, found {len(df_annual_clean)}")
    else:
        # Check Total Production (10 pts)
        try:
            diff = np.abs(df_annual_clean['Total_Production_MWh'] - annual_truth['Actual_Production_MWh'])
            if diff.max() < 1.0:
                score += 10
                feedback.append("Annual Production totals correct.")
            else:
                feedback.append(f"Production totals mismatch. Max diff: {diff.max()}")
        except KeyError: feedback.append("Column 'Total_Production_MWh' missing")

        # Check Availability (10 pts)
        try:
            diff = np.abs(df_annual_clean['Availability_Pct'] - annual_truth['Availability_Pct'])
            if diff.max() < 0.1:
                score += 10
                feedback.append("Availability calculation correct.")
            else:
                feedback.append("Availability calculation mismatch")
        except KeyError: feedback.append("Column 'Availability_Pct' missing")

        # Check Gross CF (10 pts)
        try:
            diff = np.abs(df_annual_clean['Gross_Capacity_Factor_Pct'] - annual_truth['Gross_CF'])
            if diff.max() < 0.1:
                score += 10
                feedback.append("Gross CF calculation correct.")
            else:
                feedback.append("Gross CF mismatch")
        except KeyError: feedback.append("Column 'Gross_Capacity_Factor_Pct' missing")

        # Check Revenue (5 pts)
        try:
            diff = np.abs(df_annual_clean['Annual_Revenue_USD'] - annual_truth['Revenue'])
            if diff.max() < 5.0:
                score += 5
                feedback.append("Revenue calculation correct.")
        except KeyError: feedback.append("Column 'Annual_Revenue_USD' missing")

        # Check Performance Flag (10 pts)
        try:
            # Normalize NaNs/None/Empty strings
            agent_flags = df_annual_clean['Performance_Flag'].fillna('').astype(str).str.strip().str.upper()
            truth_flags = annual_truth['Flag'].fillna('').astype(str).str.strip().str.upper()
            
            # Count matches
            matches = (agent_flags == truth_flags).sum()
            if matches == 20:
                score += 10
                feedback.append("Performance flags fully correct.")
            elif matches >= 15:
                score += 5
                feedback.append(f"Performance flags mostly correct ({matches}/20).")
            else:
                feedback.append(f"Performance flags mismatch ({matches}/20).")
        except KeyError: feedback.append("Column 'Performance_Flag' missing")

    # --- VERIFY SHEET 2: Monthly_Farm_Summary ---
    
    # Clean agent data (remove Annual row)
    df_monthly_clean = df_monthly[pd.to_numeric(df_monthly['Month'], errors='coerce').notna()].copy().reset_index(drop=True)
    df_monthly_clean = df_monthly_clean[df_monthly_clean['Month'].astype(int) <= 12]

    if len(df_monthly_clean) != 12:
        feedback.append(f"Expected 12 month rows, found {len(df_monthly_clean)}")
    else:
        # Calculate Monthly Truth
        monthly_truth = df_prod.groupby('Month').agg({
            'Actual_Production_MWh': 'sum',
            'Hours_In_Month': 'first', # All turbines same hours
            'Downtime_Hours': 'sum',
            'Wind_Speed_Avg_ms': 'mean' # Average of averages is fine here as count is constant
        }).reset_index()
        
        # Calculate Front/Back CFs
        front_prod = df_prod[df_prod['Turbine_Row'] == 'Front'].groupby('Month')['Actual_Production_MWh'].sum().reset_index()
        back_prod = df_prod[df_prod['Turbine_Row'] == 'Back'].groupby('Month')['Actual_Production_MWh'].sum().reset_index()
        
        # 10 Front, 10 Back turbines. Capacity = 10 * 2.5 = 25 MW each row
        monthly_truth['Front_CF'] = (front_prod['Actual_Production_MWh'] / (25 * monthly_truth['Hours_In_Month'])) * 100
        monthly_truth['Back_CF'] = (back_prod['Actual_Production_MWh'] / (25 * monthly_truth['Hours_In_Month'])) * 100
        monthly_truth['Wake_Loss'] = (monthly_truth['Front_CF'] - monthly_truth['Back_CF']) / monthly_truth['Front_CF'] * 100

        # Check Farm Production (10 pts)
        try:
            diff = np.abs(df_monthly_clean['Farm_Production_MWh'] - monthly_truth['Actual_Production_MWh'])
            if diff.max() < 1.0:
                score += 10
                feedback.append("Monthly Farm Production correct.")
        except KeyError: pass
        
        # Check Wake Loss (15 pts) - Complex formula
        try:
            diff = np.abs(df_monthly_clean['Wake_Loss_Pct'] - monthly_truth['Wake_Loss'])
            if diff.max() < 0.5:
                score += 15
                feedback.append("Wake Loss calculation correct.")
            elif diff.max() < 2.0:
                score += 7
                feedback.append("Wake Loss calculation close (minor deviation).")
            else:
                feedback.append(f"Wake Loss mismatch. Max diff: {diff.max()}")
        except KeyError: feedback.append("Column 'Wake_Loss_Pct' missing")

        # Check Front/Back CF (10 pts)
        try:
            diff_f = np.abs(df_monthly_clean['Front_Row_Avg_CF_Pct'] - monthly_truth['Front_CF'])
            diff_b = np.abs(df_monthly_clean['Back_Row_Avg_CF_Pct'] - monthly_truth['Back_CF'])
            if diff_f.max() < 0.2 and diff_b.max() < 0.2:
                score += 10
                feedback.append("Front/Back Row CF correct.")
        except KeyError: pass

    # --- CHECK FOR FORMULAS ---
    # We open with openpyxl data_only=False to check for '='
    try:
        wb = load_workbook(excel_path, data_only=False)
        ws_annual = wb["Turbine_Annual_Summary"]
        ws_monthly = wb["Monthly_Farm_Summary"]
        
        formula_count = 0
        total_checks = 0
        
        # Check a sample of cells that should have formulas
        # Annual: B2, G2, K2
        if "=" in str(ws_annual["B2"].value): formula_count += 1
        if "=" in str(ws_annual["G2"].value): formula_count += 1
        if "=" in str(ws_annual["K2"].value): formula_count += 1
        
        # Monthly: B2, J2
        if "=" in str(ws_monthly["B2"].value): formula_count += 1
        if "=" in str(ws_monthly["J2"].value): formula_count += 1
        
        if formula_count >= 3:
            score += 20
            feedback.append("Formulas detected in cells.")
        else:
            feedback.append("Few or no formulas detected (hardcoded values?).")
            
    except Exception as e:
        feedback.append(f"Formula check failed: {e}")

    # Pass Threshold
    passed = score >= 65
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }