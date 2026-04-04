#!/usr/bin/env python3
"""
Verifier for create_data_asset task.

Evaluates if the agent successfully created a Data Asset record in Eramba 
with the correct title and description.
"""

import json
import os
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_data_asset(traj, env_info, task_info):
    """
    Verifies the creation of a specific Data Asset.
    
    Scoring Criteria:
    1. Record exists in database with correct title (40 pts)
    2. Description contains required details (30 pts)
    3. Record was created during the task window (anti-gaming) (20 pts)
    4. Database record count increased (10 pts)
    """
    
    # 1. Setup and load result data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment interaction failed (copy_from_env missing)"}

    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Extract Data
    record_found = result.get("record_found", False)
    record = result.get("record", {})
    task_start_ts = result.get("task_start_time", 0)
    count_increased = result.get("count_increased", False)
    
    score = 0
    feedback_lines = []
    
    # 3. Verify Record Existence & Title (40 pts)
    expected_title = task_info.get("metadata", {}).get("expected_title", "Customer Loyalty Program Database")
    
    if record_found and record:
        actual_title = record.get("title", "")
        if expected_title.lower() in actual_title.lower():
            score += 40
            feedback_lines.append(f"Success: Data Asset '{actual_title}' found.")
        else:
            # Partial credit if found but title mismatch (unlikely given query)
            score += 20
            feedback_lines.append(f"Warning: Record found but title '{actual_title}' might be incorrect.")
    else:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Failed: No Data Asset with the expected title was found in the database."
        }

    # 4. Verify Description Content (30 pts)
    required_terms = task_info.get("metadata", {}).get("required_terms", ["personal data", "loyalty"])
    actual_desc = record.get("description", "").lower()
    
    found_terms = [term for term in required_terms if term.lower() in actual_desc]
    
    if len(found_terms) == len(required_terms):
        score += 30
        feedback_lines.append("Success: Description contains all required details.")
    elif len(found_terms) > 0:
        partial_score = int(30 * (len(found_terms) / len(required_terms)))
        score += partial_score
        feedback_lines.append(f"Partial Success: Description missing some details. Found: {found_terms}")
    else:
        feedback_lines.append("Failed: Description appears empty or missing required context.")

    # 5. Verify Timestamp / Anti-Gaming (20 pts)
    # Eramba dates are usually 'YYYY-MM-DD HH:MM:SS'
    created_str = record.get("created", "")
    valid_timestamp = False
    if created_str:
        try:
            # Parse MySQL datetime string
            created_dt = datetime.strptime(created_str, "%Y-%m-%d %H:%M:%S")
            created_ts = created_dt.timestamp()
            
            # Allow small clock skew (e.g. 60s) but generally creation should be after start
            if created_ts >= (task_start_ts - 60):
                score += 20
                valid_timestamp = True
                feedback_lines.append("Success: Record created during task session.")
            else:
                feedback_lines.append(f"Failed: Record creation time ({created_str}) predates task start.")
        except ValueError:
            feedback_lines.append("Warning: Could not parse creation timestamp.")
    
    # 6. Verify Count Increase (10 pts)
    if count_increased:
        score += 10
    else:
        feedback_lines.append("Warning: Total record count did not increase (record might have been overwritten?).")

    # 7. Final Determination
    passed = (record_found and valid_timestamp and score >= 70)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_lines)
    }