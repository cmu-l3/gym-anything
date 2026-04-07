#!/usr/bin/env python3
"""
Verifier for building_tou_energy_analysis task.
Uses pandas to read the exported excel file with evaluated formulas.
Dynamically calculates the ground truth from the raw data to ensure robust grading.
"""

import os
import sys
import json
import logging
import tempfile
import pandas as pd

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Constants
PEAK_RATE = 0.28
OFFPEAK_RATE = 0.11

def verify_tou_analysis(traj, env_info, task_info):
    """Verify that the TOU analysis and monthly summary are correct."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    # Read export metadata
    temp_meta = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_meta.name)
        with open(temp_meta.name, 'r') as f:
            export_meta = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result metadata: {e}"}
    finally:
        if os.path.exists(temp_meta.name):
            os.unlink(temp_meta.name)
            
    # Anti-gaming check
    if not export_meta.get("file_modified_during_task", False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "File was not saved/modified during the task. Did you forget to save?"
        }

    # Fetch the processed spreadsheet
    temp_excel = tempfile.NamedTemporaryFile(delete=False, suffix='.xlsx')
    try:
        copy_from_env("/home/ga/Documents/hourly_load_data.xlsx", temp_excel.name)
        
        # Load MeterData
        try:
            df_meter = pd.read_excel(temp_excel.name, sheet_name='MeterData', engine='openpyxl')
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to read 'MeterData' sheet: {e}"}
            
        # Load Monthly_Summary
        try:
            df_summary = pd.read_excel(temp_excel.name, sheet_name='Monthly_Summary', engine='openpyxl')
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to read 'Monthly_Summary' sheet. Does it exist? Error: {e}"}

    finally:
        if os.path.exists(temp_excel.name):
            os.unlink(temp_excel.name)

    score = 0
    feedback_parts = []
    
    # ---------------------------------------------------------
    # 1. Verify MeterData Enrichment (Granular Checks)
    # ---------------------------------------------------------
    
    # Normalize headers to lowercase for flexible matching
    meter_cols = {str(c).lower().strip(): c for c in df_meter.columns}
    
    has_month = 'month' in meter_cols
    has_hour = 'hour' in meter_cols
    has_weekday = 'weekday' in meter_cols
    has_period = 'period' in meter_cols
    has_cost = 'cost' in meter_cols
    
    if has_month and has_hour and has_weekday:
        score += 15
        feedback_parts.append("Date/Time columns extracted (+15)")
    else:
        feedback_parts.append("Missing Month/Hour/Weekday columns")
        
    # Recalculate Ground Truth dynamically from their Timestamp and Usage
    try:
        df_meter['Timestamp'] = pd.to_datetime(df_meter['Timestamp'])
        
        # Ground Truth arrays
        gt_month = df_meter['Timestamp'].dt.month
        gt_hour = df_meter['Timestamp'].dt.hour
        gt_is_weekday = df_meter['Timestamp'].dt.dayofweek < 5
        
        gt_is_peak = gt_is_weekday & (gt_hour >= 14) & (gt_hour <= 19)
        
        gt_cost = df_meter['Usage_kWh'] * np.where(gt_is_peak, PEAK_RATE, OFFPEAK_RATE)
        
        # Check Period logic if the column exists
        if has_period:
            user_period = df_meter[meter_cols['period']].astype(str).str.lower().str.strip()
            # Check a peak sample and off-peak sample
            correct_peaks = (user_period[gt_is_peak] == 'peak').mean()
            correct_offpeaks = (user_period[~gt_is_peak] == 'off-peak').mean()
            
            if correct_peaks > 0.95 and correct_offpeaks > 0.95:
                score += 25
                feedback_parts.append("TOU Period logic correct (+25)")
            else:
                feedback_parts.append(f"TOU logic flawed (Peak acc: {correct_peaks:.2f}, Off-Peak acc: {correct_offpeaks:.2f})")
        else:
            feedback_parts.append("Missing 'Period' column")
            
        # Check Cost math
        if has_cost:
            user_cost = pd.to_numeric(df_meter[meter_cols['cost']], errors='coerce').fillna(0)
            cost_mse = ((user_cost - gt_cost)**2).mean()
            if cost_mse < 0.1:  # allow tiny rounding differences
                score += 15
                feedback_parts.append("Hourly Cost calculations correct (+15)")
            else:
                feedback_parts.append("Hourly Cost calculations incorrect")
        else:
            feedback_parts.append("Missing 'Cost' column")
            
    except Exception as e:
        logger.error(f"Error validating MeterData: {e}")
        feedback_parts.append("Failed to evaluate MeterData logic due to data format issues.")

    # ---------------------------------------------------------
    # 2. Verify Monthly_Summary Sheet
    # ---------------------------------------------------------
    summary_cols = {str(c).lower().strip(): c for c in df_summary.columns}
    
    req_cols = ['month', 'total_usage_kwh', 'peak_demand_kw', 'total_cost']
    has_summary_cols = all(c in summary_cols for c in req_cols)
    
    if has_summary_cols and len(df_summary) >= 12:
        score += 10
        feedback_parts.append("Monthly_Summary structure correct (+10)")
        
        # Generate Ground Truth Summary
        gt_summary = df_meter.groupby(gt_month).agg(
            total_usage=('Usage_kWh', 'sum'),
            peak_demand=('Usage_kWh', 'max'),
            total_cost=('Usage_kWh', lambda x: (x * np.where(gt_is_peak[x.index], PEAK_RATE, OFFPEAK_RATE)).sum())
        )
        
        try:
            # Sort user summary by month to ensure alignment
            df_summary_sorted = df_summary.sort_values(by=summary_cols['month']).head(12)
            
            user_usage = pd.to_numeric(df_summary_sorted[summary_cols['total_usage_kwh']], errors='coerce').values
            user_demand = pd.to_numeric(df_summary_sorted[summary_cols['peak_demand_kw']], errors='coerce').values
            user_total_cost = pd.to_numeric(df_summary_sorted[summary_cols['total_cost']], errors='coerce').values
            
            # Verify Usage & Demand Aggregation
            usage_err = np.mean(np.abs(user_usage - gt_summary['total_usage'].values) / gt_summary['total_usage'].values)
            demand_err = np.mean(np.abs(user_demand - gt_summary['peak_demand'].values) / gt_summary['peak_demand'].values)
            
            if usage_err < 0.02 and demand_err < 0.02:
                score += 15
                feedback_parts.append("Usage and Demand aggregations correct (+15)")
            else:
                feedback_parts.append("Usage or Demand aggregations incorrect")
                
            # Verify Cost Aggregation
            cost_err = np.mean(np.abs(user_total_cost - gt_summary['total_cost'].values) / gt_summary['total_cost'].values)
            
            if cost_err < 0.02:
                score += 15
                feedback_parts.append("Cost aggregation correct (+15)")
            else:
                feedback_parts.append("Cost aggregation incorrect")
                
        except Exception as e:
            logger.error(f"Error evaluating aggregations: {e}")
            feedback_parts.append("Failed to validate summary numbers.")
    else:
        feedback_parts.append("Monthly_Summary missing required columns or has < 12 rows")

    # ---------------------------------------------------------
    # 3. VLM Verification (Trajectory checking)
    # ---------------------------------------------------------
    # Optional points for visual evidence of work (e.g. formula entry, pivot table)
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
    
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        
        vlm_prompt = """
        Review these screenshots of a user working in WPS Spreadsheet. 
        Determine if the user actively authored formulas (e.g., IF, MONTH, HOUR) and created a summary table (e.g., PivotTable or SUMIFS).
        Respond in JSON:
        {
            "authored_formulas": true/false,
            "created_summary": true/false
        }
        """
        
        try:
            vlm_res = query_vlm(images=frames + [final] if final else frames, prompt=vlm_prompt)
            parsed = vlm_res.get("parsed", {})
            if parsed.get("authored_formulas") and parsed.get("created_summary"):
                score += 5
                feedback_parts.append("VLM visual verification passed (+5)")
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")

    # Determine final pass/fail
    passed = score >= 75
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }

import numpy as np