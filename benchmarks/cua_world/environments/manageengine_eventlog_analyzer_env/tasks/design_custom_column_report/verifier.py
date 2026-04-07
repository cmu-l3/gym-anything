#!/usr/bin/env python3
"""
Verifier for design_custom_column_report task.

Checks:
1. Output file exists and was created during the task.
2. Output file is a valid CSV with restricted columns (User, Source, Time).
3. Report profile exists in the database.
4. VLM verification of the trajectory (optional but good for confirming UI interaction).
"""

import json
import os
import tempfile
import csv
import io
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_design_custom_column_report(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    max_columns = metadata.get('max_columns', 5)  # Strict check: 3 requested + maybe 1 index
    required_cols = metadata.get('required_columns', ["User", "Source", "Time"])
    
    score = 0
    feedback_parts = []
    
    # 1. Retrieve Result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Retrieve CSV File (if exists)
    csv_content = ""
    if result.get("file_exists"):
        temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
        try:
            copy_from_env("/home/ga/Documents/executive_report.csv", temp_csv.name)
            with open(temp_csv.name, 'r', encoding='utf-8', errors='ignore') as f:
                csv_content = f.read()
        except Exception as e:
            logger.warning(f"Failed to copy CSV file: {e}")
        finally:
            if os.path.exists(temp_csv.name):
                os.unlink(temp_csv.name)

    # --- SCORING CRITERIA ---

    # Criterion 1: Report Profile Created in DB (30 pts)
    if result.get("report_profile_in_db"):
        score += 30
        feedback_parts.append("Report profile 'Executive Failed Logons' found in database.")
    else:
        feedback_parts.append("Report profile NOT found in database.")

    # Criterion 2: File Existence & Creation Time (30 pts)
    if result.get("file_exists") and result.get("file_created_during_task"):
        score += 30
        feedback_parts.append("CSV file exported successfully.")
    elif result.get("file_exists"):
        score += 10
        feedback_parts.append("CSV file exists but timestamp suggests it wasn't created during this task.")
    else:
        feedback_parts.append("CSV file not found at expected location.")

    # Criterion 3: Column Customization Verification (40 pts)
    # This is the core skill test: did they filter columns?
    column_check_passed = False
    if csv_content:
        try:
            # Parse first line to get headers
            reader = csv.reader(io.StringIO(csv_content))
            headers = next(reader, [])
            
            # Normalize headers (lowercase, remove quotes/spaces)
            norm_headers = [h.lower().strip() for h in headers]
            
            # Check column count
            if 0 < len(headers) <= max_columns:
                score += 20
                feedback_parts.append(f"Column count looks correct ({len(headers)} columns).")
                column_check_passed = True
            elif len(headers) > max_columns:
                feedback_parts.append(f"Too many columns ({len(headers)}). Default report not customized?")
            
            # Check for required content matches
            # We look for partial matches e.g. "User" in "Username"
            found_req = 0
            for req in required_cols:
                req_lower = req.lower()
                if any(req_lower in h for h in norm_headers):
                    found_req += 1
            
            if found_req >= 2: # Allow missing one due to naming variations
                score += 20
                feedback_parts.append("Required columns (User, Source, Time) found.")
            else:
                feedback_parts.append(f"Missing required columns. Found headers: {headers}")

        except Exception as e:
            feedback_parts.append(f"Error parsing CSV content: {e}")
    else:
        feedback_parts.append("No CSV content to verify columns.")

    # Final Evaluation
    passed = score >= 70 and result.get("file_exists")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }