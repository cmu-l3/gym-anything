#!/usr/bin/env python3
"""
Verifier for aggregate_data_csv_import task.

Scoring (100 points total):
1. Data Import Success (60 points)
   - At least 5 values imported/exist in DB (35 pts)
   - Most/All values imported (25 pts)
   - Timestamps verify creation during task (Anti-gaming)
2. Reporting (40 points)
   - Result text file created (20 pts)
   - File created during task window (10 pts)
   - File has content (10 pts)

Pass threshold: 60 points
Mandatory: At least 5 data values imported.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_aggregate_data_csv_import(traj, env_info, task_info):
    """Verify that aggregate data CSV was imported successfully."""
    
    # 1. Setup access to result file
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Infrastructure error: copy_from_env not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Metrics
    initial_count = int(result.get('initial_db_count', 0))
    current_count = int(result.get('current_db_count', 0))
    newly_modified = int(result.get('newly_modified_count', 0))
    
    report_exists = result.get('report_file_exists', False)
    report_fresh = result.get('report_file_created_during_task', False)
    report_len = int(result.get('report_content_length', 0))
    
    score = 0
    feedback = []
    
    # 3. Evaluate Data Import (60 pts)
    # The script generates ~15 rows (5 facilities * 3 DEs). 
    # Let's say we expect at least 5.
    
    # Check 1: Do the records exist?
    count_diff = current_count - initial_count
    
    if newly_modified >= 5:
        score += 35
        feedback.append(f"Successfully imported {newly_modified} data values.")
        
        # Bonus for completeness (>10 records)
        if newly_modified >= 10:
            score += 25
            feedback.append("Import volume indicates complete dataset processing.")
        elif newly_modified >= 5:
            score += 10
            feedback.append("Partial import completed.")
    else:
        # Fail immediately if no data imported
        if current_count > initial_count:
            feedback.append(f"Found {count_diff} new records, but timestamps don't match task window. Possible anti-gaming violation.")
        else:
            feedback.append("No new data values found in the database.")
            
    # 4. Evaluate Reporting (40 pts)
    if report_exists:
        if report_fresh:
            score += 20
            feedback.append("Import summary file created successfully.")
            
            if report_len > 20:
                score += 20  # Combined 10 for freshness check in logic + 10 for content
                feedback.append("Summary file contains detailed content.")
            else:
                score += 10
                feedback.append("Summary file is empty or too short.")
        else:
            feedback.append("Summary file exists but was not created during this task session.")
    else:
        feedback.append("Import summary file not found.")

    # 5. Final Result
    passed = (score >= 60) and (newly_modified >= 5)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }