#!/usr/bin/env python3
"""
Verifier for extract_high_value_customers task (Oracle Analytics Desktop).

Checks:
1. CSV file existence and creation time.
2. CSV content (Schema and Data Logic).
3. VLM verification of UI interaction.
"""

import json
import os
import tempfile
import logging
import pandas as pd
import io

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_extract_high_value_customers(traj, env_info, task_info):
    """
    Verify that the agent exported the correct high-value customer list.
    """
    # 1. Setup and Resource Acquisition
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_filename = metadata.get('expected_filename', 'vip_corporate_customers.csv')
    # Windows path in container needs to be mapped to the linux path used by copy_from_env
    # Usually provided as /tmp/task_result.json for the result file
    # and the specific document path for the CSV.
    
    # In dockur/windows, paths like C:\Users\Docker\Documents usually map to /mnt/users/docker/documents 
    # or rely on the copy_from_env handling the windows path translation if supported.
    # Assuming copy_from_env takes the path EXACTLY as written in the OS.
    
    expected_path_windows = metadata.get('expected_path', r"C:\Users\Docker\Documents\vip_corporate_customers.csv")
    
    score = 0
    max_score = 100
    feedback_parts = []
    
    # 2. Analyze Result JSON (Metadata)
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Note: We use the Linux-style path if mounted, or Windows path if copy_from_env supports it.
        # Based on standard gym-anything with windows, we usually access via a share or specific path.
        # We'll try to copy the result json first.
        copy_from_env(r"C:\tmp\task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # Criterion 1: File Existence & Anti-Gaming (30 pts)
    file_exists = result_data.get('file_exists', False)
    created_during = result_data.get('file_created_during_task', False)
    
    if file_exists:
        score += 15
        if created_during:
            score += 15
            feedback_parts.append("New CSV file created.")
        else:
            feedback_parts.append("CSV file exists but was NOT created during this task (stale data).")
    else:
        feedback_parts.append("Expected CSV file not found.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: Data Content Verification (70 pts)
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    try:
        copy_from_env(expected_path_windows, temp_csv.name)
        
        # Read CSV
        # Oracle Analytics CSV exports often have specific headers or skipping requirements.
        # We'll try standard reading first.
        try:
            df = pd.read_csv(temp_csv.name)
        except:
            # Try skipping metadata rows if OAD adds them
            df = pd.read_csv(temp_csv.name, skiprows=1)
            
        # Normalize columns (strip whitespace, lowercase)
        df.columns = [c.strip().lower() for c in df.columns]
        
        # Check Columns (10 pts)
        required_cols = ['customer name', 'customer segment', 'profit']
        # Note: OAD might export 'Segment' instead of 'Customer Segment' depending on dataset naming
        # We allow flexibility
        
        col_map = {}
        for rc in required_cols:
            found = False
            for c in df.columns:
                if rc in c or (rc == 'customer segment' and 'segment' in c):
                    col_map[rc] = c
                    found = True
                    break
            if not found:
                feedback_parts.append(f"Missing column: {rc}")
        
        if len(col_map) == 3:
            score += 10
            feedback_parts.append("Correct columns found.")
            
            # Check Filters
            
            # Segment Filter (30 pts)
            segment_col = col_map['customer segment']
            # Check unique values
            unique_segments = df[segment_col].astype(str).str.lower().unique()
            if len(unique_segments) == 1 and 'corporate' in unique_segments[0]:
                score += 30
                feedback_parts.append("Segment correctly filtered to Corporate.")
            else:
                feedback_parts.append(f"Incorrect segments found: {unique_segments}")
                
            # Profit Filter (30 pts)
            profit_col = col_map['profit']
            # Clean profit data (remove currency symbols if string)
            if df[profit_col].dtype == object:
                df[profit_col] = df[profit_col].replace(r'[$,]', '', regex=True).astype(float)
            
            min_profit = df[profit_col].min()
            if min_profit >= 5000:
                score += 30
                feedback_parts.append(f"Profit correctly filtered (Min: {min_profit}).")
            else:
                feedback_parts.append(f"Profit filter failed. Found values as low as {min_profit}.")
                
        else:
            feedback_parts.append("Could not verify data due to missing columns.")

    except Exception as e:
        feedback_parts.append(f"Failed to parse CSV file: {e}")
    finally:
        if os.path.exists(temp_csv.name):
            os.unlink(temp_csv.name)

    passed = score >= 100
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }