#!/usr/bin/env python3
"""
Verifier for export_employee_directory task.
Checks if the agent successfully exported the Odoo employee list to an Excel file
with the correct columns and data.
"""

import json
import os
import sys
import tempfile
import pandas as pd
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_export_employee_directory(traj, env_info, task_info):
    """
    Verify the employee export task.
    
    Criteria:
    1. File exists and is a valid XLSX.
    2. File was created during the task.
    3. Required columns are present.
    4. Row count matches expected range (approx 20 demo employees).
    5. Specific employee names are present (sanity check).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_columns = [c.lower() for c in metadata.get('expected_columns', ["name", "department", "job position", "work phone"])]
    min_rows = metadata.get('min_rows', 15)
    
    # Load result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # Check basic file existence
    if not result.get('output_exists', False):
        return {"passed": False, "score": 0, "feedback": "No Excel (.xlsx) file found in Downloads folder."}

    if not result.get('file_created_during_task', False):
        return {"passed": False, "score": 0, "feedback": "An Excel file was found, but it was not created during the task session (anti-gaming check failed)."}

    remote_path = result.get('output_path')
    if not remote_path:
        return {"passed": False, "score": 0, "feedback": "Result JSON missing output path."}

    # Retrieve the Excel file
    temp_xlsx = tempfile.NamedTemporaryFile(delete=False, suffix='.xlsx')
    try:
        copy_from_env(remote_path, temp_xlsx.name)
        
        # Parse Excel file
        try:
            df = pd.read_excel(temp_xlsx.name)
        except Exception as e:
            return {"passed": False, "score": 10, "feedback": f"File exists but is not a valid Excel file: {str(e)}"}
            
        score = 20 # Points for valid file created
        feedback_parts = ["Valid Excel file created."]
        
        # Check Columns
        # Normalize columns to lowercase for comparison
        df.columns = df.columns.astype(str).str.strip()
        actual_columns_lower = [str(c).lower() for c in df.columns]
        
        missing_cols = []
        for col in expected_columns:
            # Flexible matching: check if expected col is contained in any actual col
            # e.g. "Work Phone" matches "Work Phone" or "Work Mobile" if user selected that
            match = False
            for act in actual_columns_lower:
                if col in act or act in col:
                    match = True
                    break
            if not match:
                missing_cols.append(col)
        
        if not missing_cols:
            score += 30
            feedback_parts.append("All required columns present.")
        else:
            feedback_parts.append(f"Missing columns: {', '.join(missing_cols)}.")

        # Check Row Count
        # Odoo header is usually row 0, verify data length
        row_count = len(df)
        if row_count >= min_rows:
            score += 25
            feedback_parts.append(f"Row count sufficient ({row_count} rows).")
        else:
            feedback_parts.append(f"Row count too low ({row_count} < {min_rows}). Did you select all employees?")
            
        # Check Content (Spot Check)
        # Check for 'Mitchell Admin' or 'Marc Demo' usually present in demo data
        # We look in the first column or any column that looks like 'name'
        name_col = None
        for c in df.columns:
            if "name" in str(c).lower():
                name_col = c
                break
        
        content_verified = False
        if name_col:
            names_in_file = df[name_col].astype(str).str.lower().tolist()
            # Demo names are typically: Mitchell Admin, Marc Demo
            hits = 0
            targets = ["mitchell", "demo", "admin", "sarah"] # lower case parts
            for val in names_in_file:
                if any(t in val for t in targets):
                    hits += 1
            
            if hits >= 2:
                content_verified = True
        
        if content_verified:
            score += 25
            feedback_parts.append("Content verification passed (found expected employee names).")
        else:
            feedback_parts.append("Content verification failed (could not find expected demo employee names).")

        passed = score >= 75
        return {
            "passed": passed,
            "score": score,
            "feedback": " ".join(feedback_parts)
        }

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error verifying file content: {str(e)}"}
    finally:
        if os.path.exists(temp_xlsx.name):
            os.unlink(temp_xlsx.name)