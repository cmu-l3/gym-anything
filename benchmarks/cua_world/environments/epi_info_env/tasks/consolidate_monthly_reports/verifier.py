#!/usr/bin/env python3
"""
Verifier for consolidate_monthly_reports task.
"""

import json
import tempfile
import os
import csv
import logging
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_consolidate_monthly_reports(traj, env_info, task_info):
    """
    Verifies that the agent correctly consolidated and filtered the surveillance data.
    
    Criteria:
    1. Output CSV exists (20 pts)
    2. CSV contains data from all three months (Jan, Feb, Mar) (40 pts)
    3. Filtering is correct (Only 'Confirmed' cases) (25 pts)
    4. HTML Summary report exists (15 pts)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 1. Retrieve JSON result from the container
    # The PowerShell script saves analysis to C:\tmp\task_result.json
    # We map this to a temp file on host
    
    task_result = {}
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Note: Adjust path separators for copy_from_env if needed. 
        # Usually copy_from_env takes the path as seen inside the guest.
        copy_from_env("C:\\tmp\\task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        logger.warning(f"Could not retrieve task result JSON: {e}")
        # Proceed with defaults
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)
            
    # 2. Retrieve actual CSV for strict checking (double check logic)
    csv_content = []
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    csv_retrieved = False
    try:
        copy_from_env("C:\\Users\\Docker\\Documents\\Q1_Confirmed.csv", temp_csv.name)
        csv_retrieved = True
        with open(temp_csv.name, 'r', newline='') as f:
            reader = csv.DictReader(f)
            csv_content = list(reader)
    except Exception as e:
        logger.warning(f"Could not retrieve CSV file: {e}")
    finally:
        if os.path.exists(temp_csv.name):
            os.unlink(temp_csv.name)

    # Scoring Logic
    
    # Criterion 1: Output File Exists
    if task_result.get("output_exists") or csv_retrieved:
        score += 20
        feedback_parts.append("Master CSV file created.")
    else:
        return {"passed": False, "score": 0, "feedback": "Master CSV file 'Q1_Confirmed.csv' not found."}

    # Criterion 2: Data Consolidation (Check for mix of months)
    # Using the PS analysis or our own CSV read
    jan_present = task_result.get("jan_ids_present", False)
    feb_present = task_result.get("feb_ids_present", False)
    mar_present = task_result.get("mar_ids_present", False)
    
    # If we pulled the CSV, double check
    if csv_retrieved and csv_content:
        ids = [row.get('CaseID', '') for row in csv_content]
        if any(i.startswith('1') for i in ids): jan_present = True
        if any(i.startswith('2') for i in ids): feb_present = True
        if any(i.startswith('3') for i in ids): mar_present = True

    months_count = sum([jan_present, feb_present, mar_present])
    if months_count == 3:
        score += 40
        feedback_parts.append("Data from all 3 months consolidated.")
    elif months_count == 2:
        score += 25
        feedback_parts.append("Data from 2 months consolidated (missing one).")
    elif months_count == 1:
        score += 10
        feedback_parts.append("Only one month of data found in output.")
    else:
        feedback_parts.append("Output file appears empty or missing CaseIDs.")

    # Criterion 3: Filtering (Only 'Confirmed')
    # Expected: 0 non-confirmed rows
    non_confirmed_count = task_result.get("non_confirmed_rows", 999)
    if csv_retrieved:
        non_confirmed_count = sum(1 for row in csv_content if row.get('Classification', '').strip().lower() != 'confirmed')
    
    if non_confirmed_count == 0 and len(csv_content) > 0:
        score += 25
        feedback_parts.append("Filtering correct: Only confirmed cases present.")
    elif non_confirmed_count > 0:
        feedback_parts.append(f"Filtering failed: Found {non_confirmed_count} non-confirmed records.")
    else:
        feedback_parts.append("No data to check filtering.")

    # Criterion 4: Report Generation
    if task_result.get("report_exists"):
        score += 15
        feedback_parts.append("Summary HTML report created.")
    else:
        feedback_parts.append("Summary HTML report missing.")

    # Anti-gaming: Check if meaningful work was done (file created during task)
    if not task_result.get("timestamp_valid", False):
        score = 0
        feedback_parts = ["File timestamp check failed (pre-existing file?)."]

    # Pass Threshold
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }