#!/usr/bin/env python3
"""
Verifier for clean_standardize_outbreak_data task.

Verification Strategy:
1. File Existence & Timing: Output CSV must exist and be modified during task.
2. Data Integrity: Row count matches input.
3. Variable Standardization:
   - Sex must be only {'Male', 'Female'}
   - Ill must be only {'Yes', 'No'}
4. Data Cleaning: Age must not contain 999.
"""

import json
import os
import tempfile
import logging
import pandas as pd
import sys

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_clean_standardize_outbreak_data(traj, env_info, task_info):
    """
    Verifies the data cleaning task by inspecting the exported CSV file.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_rows = metadata.get('expected_rows', 75)
    
    score = 0
    feedback_parts = []
    
    # 1. Retrieve Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\Windows\\Temp\\task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Check File Existence and Timing (20 pts)
    output_exists = result.get('output_exists', False)
    created_during = result.get('file_created_during_task', False)
    
    if not output_exists:
        return {"passed": False, "score": 0, "feedback": "Output file 'oswego_clean.csv' not found."}
    
    score += 10
    if created_during:
        score += 10
        feedback_parts.append("File created during task.")
    else:
        feedback_parts.append("File timestamp indicates it wasn't modified during task.")

    # 3. Retrieve and Analyze the Output CSV
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    try:
        copy_from_env("C:\\Users\\Docker\\Documents\\oswego_clean.csv", temp_csv.name)
        
        # Read with pandas
        try:
            df = pd.read_csv(temp_csv.name)
        except Exception as e:
            return {"passed": False, "score": score, "feedback": f"Output file exists but is not a valid CSV: {str(e)}"}
            
        # Check 4: Row Count (10 pts)
        # We allow a small tolerance in case header handling is weird, but ideally strict
        if abs(len(df) - expected_rows) <= 5:
            score += 10
            feedback_parts.append(f"Row count correct ({len(df)}).")
        else:
            feedback_parts.append(f"Row count mismatch (Expected ~{expected_rows}, Found {len(df)}).")
            
        # Check 5: Sex Standardization (25 pts)
        # Normalize column names to upper for robust checking
        df.columns = [c.upper() for c in df.columns]
        
        if 'SEX' in df.columns:
            unique_sex = set(df['SEX'].dropna().unique())
            # We expect exactly {'Male', 'Female'} or a subset
            allowed_sex = {'Male', 'Female'}
            
            # Check for bad values
            bad_sex = [x for x in unique_sex if x not in allowed_sex]
            
            if not bad_sex and len(unique_sex) > 0:
                score += 25
                feedback_parts.append("Sex variable standardized correctly.")
            elif not bad_sex:
                # Column empty?
                feedback_parts.append("Sex variable is empty.")
            else:
                feedback_parts.append(f"Sex variable contains non-standard values: {bad_sex}")
        else:
            feedback_parts.append("Column 'Sex' not found in output.")

        # Check 6: Ill Standardization (25 pts)
        if 'ILL' in df.columns:
            unique_ill = set(df['ILL'].dropna().unique())
            allowed_ill = {'Yes', 'No'}
            
            bad_ill = [x for x in unique_ill if x not in allowed_ill]
            
            if not bad_ill and len(unique_ill) > 0:
                score += 25
                feedback_parts.append("Ill variable standardized correctly.")
            else:
                feedback_parts.append(f"Ill variable contains non-standard values: {bad_ill}")
        else:
            feedback_parts.append("Column 'Ill' not found in output.")

        # Check 7: Age Cleaning (20 pts)
        if 'AGE' in df.columns:
            # Check for 999
            has_999 = 999 in df['AGE'].values or '999' in df['AGE'].astype(str).values
            
            if not has_999:
                score += 20
                feedback_parts.append("Age variable cleaned (no 999 found).")
            else:
                feedback_parts.append("Age variable still contains 999.")
        else:
            feedback_parts.append("Column 'Age' not found in output.")

    except Exception as e:
        feedback_parts.append(f"Error analyzing CSV content: {str(e)}")
    finally:
        if os.path.exists(temp_csv.name):
            os.unlink(temp_csv.name)

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }