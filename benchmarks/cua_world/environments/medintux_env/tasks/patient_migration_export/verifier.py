#!/usr/bin/env python3
import json
import os
import tempfile
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_patient_migration_export(traj, env_info, task_info):
    """
    Verifies the patient data migration task.
    
    Criteria:
    1. Database Table 'patient_export' exists with correct columns (Structure)
    2. Database Table contains all patient records (Completeness)
    3. Database Data matches source integrity (Accuracy)
    4. CSV file exists, has header, and matches count (Export)
    5. Summary report exists and contains correct statistics (Reporting)
    """
    
    # Setup - Retrieve Result
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}
        
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    # Task Metadata & Ground Truth
    required_columns = set(task_info['metadata']['required_columns'])
    ground_truth = result.get('ground_truth', {})
    expected_total = ground_truth.get('total', 0)
    expected_male = ground_truth.get('male', 0)
    expected_female = ground_truth.get('female', 0)
    
    score = 0
    feedback = []
    
    # ---------------------------------------------------------
    # Check 1: Database Structure (25 points)
    # ---------------------------------------------------------
    if result.get('table_exists'):
        score += 10
        feedback.append("Table 'patient_export' created.")
        
        # Check columns
        actual_columns = set(result.get('table_columns', []))
        missing_cols = required_columns - actual_columns
        
        if not missing_cols:
            score += 15
            feedback.append("All required columns are present.")
        else:
            feedback.append(f"Missing columns: {', '.join(missing_cols)}.")
            # Partial credit for columns
            score += int(15 * (len(required_columns) - len(missing_cols)) / len(required_columns))
    else:
        feedback.append("Table 'patient_export' was NOT created in the database.")

    # ---------------------------------------------------------
    # Check 2: Database Content & Completeness (25 points)
    # ---------------------------------------------------------
    row_count = result.get('table_row_count', 0)
    if row_count == expected_total and expected_total > 0:
        score += 15
        feedback.append(f"Table contains correct number of rows ({row_count}).")
    elif row_count > 0:
        feedback.append(f"Table row count mismatch: found {row_count}, expected {expected_total}.")
        score += 5 # Partial credit for having data
    else:
        feedback.append("Table is empty.")
        
    # Check sample data integrity (Sample check)
    # We verify that columns like 'sex' contain normalized 'M'/'F' and not empty
    sample_data = result.get('table_sample', [])
    valid_sample = False
    if sample_data:
        valid_sample = True
        for row in sample_data:
            if row.get('sex') not in ['M', 'F']:
                valid_sample = False
            if not row.get('source_guid'):
                valid_sample = False
    
    if valid_sample and sample_data:
        score += 10
        feedback.append("Sample data integrity check passed (GUIDs and Sex values look correct).")
    elif sample_data:
        feedback.append("Sample data integrity check failed (invalid Sex or missing GUIDs).")

    # ---------------------------------------------------------
    # Check 3: CSV Export (25 points)
    # ---------------------------------------------------------
    if result.get('csv_exists'):
        if result.get('csv_created_during_task'):
            score += 10
            feedback.append("CSV file created.")
            
            # Check CSV Header
            csv_header = result.get('csv_header', [])
            # Naive check: if it has > 5 columns, likely good
            if len(csv_header) >= 10:
                score += 5
                feedback.append("CSV header looks valid.")
            else:
                feedback.append("CSV header seems incomplete.")
                
            # Check CSV Row Count
            csv_rows = result.get('csv_row_count', 0)
            if abs(csv_rows - expected_total) <= 1: # Allow off-by-one for header/newline nuances
                score += 10
                feedback.append("CSV contains correct number of records.")
            else:
                feedback.append(f"CSV row count mismatch: found {csv_rows}, expected {expected_total}.")
        else:
            feedback.append("CSV file exists but was not created during this task session.")
    else:
        feedback.append("CSV output file not found.")

    # ---------------------------------------------------------
    # Check 4: Summary Report (25 points)
    # ---------------------------------------------------------
    report_content = result.get('report_content', "").lower()
    if result.get('report_exists') and report_content.strip():
        score += 5
        feedback.append("Summary report file created.")
        
        # Parse report for numbers
        # We look for the ground truth numbers in the text
        
        # Check Total
        if str(expected_total) in report_content:
            score += 5
            feedback.append(f"Report correctly mentions total count ({expected_total}).")
            
        # Check Gender Stats
        if str(expected_male) in report_content and str(expected_female) in report_content:
            score += 10
            feedback.append(f"Report correctly mentions gender breakdown ({expected_male} M, {expected_female} F).")
        
        # Check Missing Data Stats
        expected_missing_addr = ground_truth.get('missing_address', 0)
        expected_missing_phone = ground_truth.get('missing_phone', 0)
        
        # Loose check for these numbers
        if str(expected_missing_addr) in report_content or str(expected_missing_phone) in report_content:
            score += 5
            feedback.append("Report mentions missing data statistics.")
    else:
        feedback.append("Summary report not found or empty.")

    # Final Verdict
    # Threshold: 60, but MUST have table created
    table_created = result.get('table_exists', False)
    passed = (score >= 60) and table_created
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }