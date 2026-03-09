#!/usr/bin/env python3
"""
Verifier for create_business_continuity_plan task.

Scoring Criteria:
1. Record exists with correct title (35 pts)
2. Description contains key requirements (RTO, RPO, outage context) (25 pts)
3. Record created during task (anti-gaming) (20 pts)
4. Record count increased (10 pts)
5. Record is active/not deleted (10 pts)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_business_continuity_plan(traj, env_info, task_info):
    """
    Verify the creation of a Business Continuity Plan entry in Eramba.
    """
    # 1. Setup and retrieve result data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Parse Data
    record = result.get('record_found')
    initial_count = int(result.get('initial_count', 0))
    final_count = int(result.get('final_count', 0))
    
    score = 0
    feedback_parts = []
    
    # Expected values
    expected_title_part = "Data Center Outage"
    expected_title_part2 = "Core Operations Recovery"
    
    # 3. Evaluate Criteria
    
    # Criterion 1: Record Existence & Title (35 pts)
    title_match = False
    if record:
        title = record.get('title', '')
        if expected_title_part in title and expected_title_part2 in title:
            score += 35
            title_match = True
            feedback_parts.append("Correct title found")
        elif expected_title_part in title:
            score += 20
            feedback_parts.append("Partial title match")
        else:
            feedback_parts.append(f"Record found but title mismatch ('{title}')")
    else:
        feedback_parts.append("No matching record found")

    # Criterion 2: Description Content (25 pts)
    # RTO, RPO, context
    if record:
        description = record.get('description', '')
        desc_points = 0
        required_phrases = ["data center outage", "Recovery Time Objective", "Recovery Point Objective"]
        
        found_phrases = [p for p in required_phrases if p.lower() in description.lower()]
        
        if len(found_phrases) == 3:
            desc_points = 25
            feedback_parts.append("Description contains all required details")
        elif len(found_phrases) > 0:
            desc_points = 10 * len(found_phrases)
            feedback_parts.append(f"Description contains some details ({', '.join(found_phrases)})")
        else:
            feedback_parts.append("Description missing key RTO/RPO details")
            
        score += desc_points

    # Criterion 3: Timestamp Verification (20 pts)
    # The SQL query in export_result.sh only selects records created >= task_start
    # So if we found a record, it passed this check implicitly by query design.
    if record:
        score += 20
        feedback_parts.append("Record created during task session")
    else:
        feedback_parts.append("No record created during task timeframe")

    # Criterion 4: Record Count Increase (10 pts)
    if final_count > initial_count:
        score += 10
        feedback_parts.append("Total record count increased")
    else:
        feedback_parts.append("Record count did not increase")

    # Criterion 5: Not Deleted (10 pts)
    if record:
        deleted = record.get('deleted')
        # MySQL returns 0 or 1, or string '0'/'1'
        is_deleted = str(deleted) == '1'
        if not is_deleted:
            score += 10
            feedback_parts.append("Record is active (not deleted)")
        else:
            feedback_parts.append("Record is marked as deleted")

    # 4. Final Verdict
    # Pass threshold: 60 pts AND title match required
    passed = (score >= 60) and title_match
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts),
        "details": {
            "record_found": bool(record),
            "final_count": final_count,
            "title_match": title_match
        }
    }