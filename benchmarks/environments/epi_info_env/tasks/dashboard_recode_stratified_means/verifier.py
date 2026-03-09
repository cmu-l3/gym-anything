#!/usr/bin/env python3
"""
Verifier for dashboard_recode_stratified_means task.

Requirements:
1. Excel output file exists and was created during task.
2. Excel contains specific columns: 'AgeGroup', 'Mean'.
3. 'AgeGroup' contains recoded strings: 'Young Adult', 'Middle Aged', 'Older Adult'.
4. Data is stratified by Gender (1/2 or Male/Female).
5. Means follow biological plausibility (Older > Young).
"""

import json
import tempfile
import os
import logging
import pandas as pd
import numpy as np

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_dashboard_recode(traj, env_info, task_info):
    """
    Verify the Epi Info 7 Dashboard Recode task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_groups = set(metadata.get('expected_groups', ["Young Adult", "Middle Aged", "Older Adult"]))
    
    score = 0
    feedback_parts = []
    
    # 1. Retrieve Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\tmp\\task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Check File Existence and Timing (25 pts)
    if not result_data.get('output_exists'):
        return {"passed": False, "score": 0, "feedback": "Output Excel file not found."}
    
    score += 10
    feedback_parts.append("Output file exists")
    
    if result_data.get('file_created_during_task'):
        score += 15
        feedback_parts.append("File created during task")
    else:
        feedback_parts.append("File timestamp verification failed")

    # 3. Analyze Excel Content (75 pts)
    temp_excel = tempfile.NamedTemporaryFile(delete=False, suffix='.xlsx')
    try:
        # Copy Excel file
        copy_from_env("C:\\Users\\Docker\\Documents\\BP_Analysis_Results.xlsx", temp_excel.name)
        
        # Read Excel
        # Note: Epi Info exports often have headers. Pandas default read usually works.
        try:
            df = pd.read_excel(temp_excel.name)
        except Exception as e:
            return {"passed": False, "score": score, "feedback": f"File exists but is not a valid Excel file: {e}"}

        # Normalize column names (Epi Info might export uppercase or with specific formatting)
        df.columns = [str(c).strip() for c in df.columns]
        
        # Check for Recoded Variable (30 pts)
        # Look for a column that contains the expected recode strings
        age_col = None
        for col in df.columns:
            unique_vals = set(df[col].dropna().astype(str).unique())
            # Check if intersection with expected groups is significant
            if len(unique_vals.intersection(expected_groups)) >= 2:
                age_col = col
                break
        
        if age_col:
            score += 30
            feedback_parts.append(f"Recoded variable found in column '{age_col}'")
            
            # Check for all specific groups
            unique_vals = set(df[age_col].dropna().astype(str).unique())
            missing_groups = expected_groups - unique_vals
            if not missing_groups:
                score += 5  # Bonus for perfection
            else:
                feedback_parts.append(f"Missing groups: {missing_groups}")
        else:
            feedback_parts.append("Could not find column with 'Young Adult'/'Middle Aged' labels")

        # Check for Means Statistic (15 pts)
        # Look for a column likely to be the Mean BP (values approx 100-150)
        mean_col = None
        for col in df.columns:
            if "Mean" in col or "Avg" in col or "BPXSY1" in col:
                # Check if values are numeric and in range
                try:
                    vals = pd.to_numeric(df[col], errors='coerce').dropna()
                    if len(vals) > 0 and vals.mean() > 80 and vals.mean() < 200:
                        mean_col = col
                        break
                except:
                    continue
        
        if mean_col:
            score += 15
            feedback_parts.append(f"Mean statistic found in column '{mean_col}'")
        else:
            feedback_parts.append("Could not identify Mean BP column")

        # Check for Stratification (Gender) (15 pts)
        gender_col = None
        for col in df.columns:
            if "RIAGENDR" in col or "Gender" in col:
                gender_col = col
                break
        
        if gender_col:
            score += 15
            feedback_parts.append("Stratification by Gender found")
        else:
            feedback_parts.append("Stratification by Gender NOT found")

        # Data Plausibility Check (Bonus/Validation)
        if age_col and mean_col:
            try:
                # Older adults should generally have higher BP than Young Adults
                means_by_age = df.groupby(age_col)[mean_col].mean()
                if "Older Adult" in means_by_age and "Young Adult" in means_by_age:
                    if means_by_age["Older Adult"] > means_by_age["Young Adult"]:
                        feedback_parts.append("Data trend matches biological plausibility (Older > Young)")
                    else:
                        feedback_parts.append("WARNING: Data trend unusual (Older <= Young)")
            except:
                pass

    except Exception as e:
        feedback_parts.append(f"Error analyzing Excel content: {e}")
    finally:
        if os.path.exists(temp_excel.name):
            os.unlink(temp_excel.name)

    # 4. Canvas File Check (10 pts)
    if result_data.get('canvas_exists'):
        score += 10
        feedback_parts.append("Dashboard canvas saved")

    passed = score >= 70 and result_data.get('output_exists')

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }