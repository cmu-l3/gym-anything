#!/usr/bin/env python3
import json
import os
import sys
import tempfile
import csv

def verify_create_export_payroll_report(traj, env_info, task_info):
    """
    Verify the payroll report creation and export.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback = []
    
    # 1. Retrieve Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Retrieve CSV File (if it exists)
    csv_content = []
    if result.get("csv_found") and result.get("exported_csv_path"):
        temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
        try:
            copy_from_env(result["exported_csv_path"], temp_csv.name)
            with open(temp_csv.name, 'r', encoding='utf-8', errors='replace') as f:
                reader = csv.reader(f)
                csv_content = list(reader)
        except Exception as e:
            feedback.append(f"Failed to read exported CSV: {e}")
        finally:
            if os.path.exists(temp_csv.name):
                os.unlink(temp_csv.name)
    
    # ---------------------------------------------------------
    # SCORING
    # ---------------------------------------------------------

    # Criterion 1: Report Definition in DB (20 pts)
    if result.get("report_exists_in_db"):
        score += 20
        feedback.append("Report definition found in database (20/20)")
    else:
        feedback.append("Report definition NOT found in database")

    # Criterion 2: Configuration Checks (30 pts)
    if result.get("db_filter_set"):
        score += 15
        feedback.append("Report filter configured (15/15)")
    else:
        feedback.append("Report filter missing or incorrect")
        
    if result.get("db_salary_field_present"):
        score += 15
        feedback.append("Salary field included in report (15/15)")
    else:
        feedback.append("Salary field NOT included in report")

    # Criterion 3: Export File Exists (20 pts)
    if result.get("csv_found") and result.get("csv_created_during_task"):
        score += 20
        feedback.append("New CSV export found in Downloads (20/20)")
    elif result.get("csv_found"):
        score += 10
        feedback.append("CSV found but timestamp is old/uncertain (10/20)")
    else:
        feedback.append("No exported CSV file found")

    # Criterion 4: File Content Analysis (30 pts)
    # Check for Employee "Alice" or "Dev"
    found_employee = False
    found_salary = False
    
    # Flatten CSV content for string search
    flat_content = " ".join([str(cell) for row in csv_content for cell in row])
    
    if "Alice" in flat_content or "Dev" in flat_content:
        found_employee = True
        score += 15
        feedback.append("Export contains target employee 'Alice Dev' (15/15)")
    else:
        feedback.append("Export does NOT contain target employee")

    # Check for Salary "85000" or "85,000"
    if "85000" in flat_content or "85,000" in flat_content:
        found_salary = True
        score += 15
        feedback.append("Export contains correct salary data (15/15)")
    else:
        feedback.append("Export does NOT contain salary data")

    # Final Pass Determination
    # Pass if score >= 70 AND salary data is present (critical success factor)
    passed = (score >= 70) and found_salary
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }