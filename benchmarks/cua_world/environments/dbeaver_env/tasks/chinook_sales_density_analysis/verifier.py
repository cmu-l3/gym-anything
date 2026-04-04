#!/usr/bin/env python3
"""
Verifier for chinook_sales_density_analysis task.

Scoring Breakdown (100 pts total):
1. Connection Created (10 pts)
2. dim_date Table Exists & Schema (20 pts)
3. dim_date Population (Row count + Leap Year check) (20 pts)
4. Weekend Logic Correct (10 pts)
5. View Created & Aggregation Logic (20 pts)
6. CSV Export Exists & Valid (20 pts)
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_chinook_sales_density_analysis(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/density_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    # 1. Connection (10 pts)
    if result.get("connection_exists"):
        score += 10
        feedback.append("DBeaver connection detected.")
    else:
        feedback.append("No DBeaver connection found.")

    # 2. dim_date Existence (20 pts)
    if result.get("dim_date_exists"):
        score += 20
        feedback.append("dim_date table created.")
    else:
        feedback.append("dim_date table NOT found.")

    # 3. dim_date Population (20 pts)
    # Expected 1826 rows (5 years * 365 + 1 leap day)
    row_count = result.get("dim_date_count", 0)
    leap_day = result.get("leap_day_exists", False)
    
    if 1820 <= row_count <= 1830:
        score += 10
        feedback.append(f"Row count correct ({row_count}).")
    else:
        feedback.append(f"Row count incorrect (found {row_count}, expected ~1826).")
        
    if leap_day:
        score += 10
        feedback.append("Leap day (2012-02-29) found.")
    else:
        feedback.append("Leap day (2012-02-29) MISSING.")

    # 4. Weekend Logic (10 pts)
    if result.get("weekend_check"):
        score += 10
        feedback.append("Weekend/Weekday logic is correct.")
    else:
        feedback.append("Weekend logic failed (checked Jan 3 2009 vs Jan 5 2009).")

    # 5. View Logic (20 pts)
    if result.get("view_exists"):
        score += 10
        feedback.append("View v_monthly_density created.")
        
        # Check aggregation logic based on sample
        # Sample string format: "31|20" (TotalDays|ZeroSalesDays) - example
        sample_data = result.get("sample_month_data", "")
        if sample_data:
            parts = sample_data.split('|')
            if len(parts) >= 2:
                try:
                    total_days = int(parts[0])
                    zero_sales = int(parts[1])
                    # Jan 2009: 31 days. Sparse sales means zero_sales > 0 and < 31.
                    if total_days == 31 and 0 < zero_sales < 31:
                        score += 10
                        feedback.append("View aggregation logic looks correct (Jan 2009 has sales & non-sales days).")
                    else:
                        feedback.append(f"View aggregation suspicious for Jan 2009: {sample_data}")
                except:
                    feedback.append("Could not parse view sample data.")
        else:
            feedback.append("View returned no data for Jan 2009.")
    else:
        feedback.append("View v_monthly_density NOT found.")

    # 6. CSV Export (20 pts)
    if result.get("csv_exists"):
        score += 10
        feedback.append("CSV export found.")
        
        # Check rows (60 months + 1 header = 61)
        csv_rows = result.get("csv_row_count", 0)
        if 50 <= csv_rows <= 70:
            score += 10
            feedback.append(f"CSV row count correct ({csv_rows}).")
        else:
            feedback.append(f"CSV row count incorrect ({csv_rows}, expected ~61).")
            
        if not result.get("csv_created_during_task"):
            feedback.append("WARNING: CSV timestamp indicates it was not created during this task run.")
    else:
        feedback.append("CSV export NOT found.")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback)
    }