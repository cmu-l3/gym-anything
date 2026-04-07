#!/usr/bin/env python3
"""
Verifier for Import Server Logs task.

Criteria:
1. Significant increase in visit count (>= 100).
2. Visits must be correctly associated with Site ID 1.
3. Visits must have correct timestamps (last ~7 days).
4. Visits must have parsed metadata (browser/OS) proving use of import tool.
5. User must have created a result text file with the count.
"""

import json
import logging
import os
import tempfile
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_import_server_logs(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get metadata
    metadata = task_info.get('metadata', {})
    expected_min_visits = metadata.get('expected_min_visits', 100)
    
    # Retrieve result JSON
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        os.unlink(temp_result.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result: {e}"}

    # Extract metrics
    initial_visits = int(result.get('initial_visits', 0))
    current_visits = int(result.get('current_visits', 0))
    current_actions = int(result.get('current_actions', 0))
    recent_visits = int(result.get('recent_visits', 0))
    parsed_ua_visits = int(result.get('parsed_user_agents', 0))
    result_file_exists = result.get('result_file_exists', False)
    result_file_content = result.get('result_file_content', "")

    new_visits = current_visits - initial_visits
    
    score = 0
    feedback = []

    # Criterion 1: Visit Count Increase (30 pts)
    # The log file has ~250 visits. We expect at least 100 to be imported successfully.
    if new_visits >= 100:
        score += 30
        feedback.append(f"Successfully imported {new_visits} visits (Target: >=100).")
    elif new_visits >= 50:
        score += 15
        feedback.append(f"Partially imported {new_visits} visits (Target: >=100).")
    else:
        feedback.append(f"Failed to import enough visits. Only {new_visits} new records found.")

    # Criterion 2: High Volume Bonus (10 pts)
    # If they got most of the logs (>=200), give bonus
    if new_visits >= 200:
        score += 10
        feedback.append("Bonus: High import success rate (>200 visits).")

    # Criterion 3: Actions Created (15 pts)
    # Visits should have associated actions (pageviews)
    if current_actions > 0 and current_actions >= new_visits:
        score += 15
        feedback.append("Visit actions (pageviews) correctly recorded.")
    else:
        feedback.append("Warning: Low action count relative to visits.")

    # Criterion 4: Timestamp Validity (15 pts)
    # Log files were generated for the last 7 days. Imports should reflect this.
    # If recent_visits (last 8 days) is close to current_visits, the timestamps are correct.
    if recent_visits >= (new_visits * 0.9) and new_visits > 0:
        score += 15
        feedback.append("Timestamps are correctly within the last week.")
    else:
        feedback.append("Timestamps do not match expected range (check timezone or log date parsing).")

    # Criterion 5: Metadata Parsed (10 pts)
    # The Python script parses User Agents. Manual SQL INSERTs usually skip this or do it poorly.
    if parsed_ua_visits >= (new_visits * 0.9) and new_visits > 0:
        score += 10
        feedback.append("Browser/OS metadata correctly parsed.")
    else:
        feedback.append("Browser/OS metadata missing (did you use the import script?).")

    # Criterion 6: Result File (20 pts total)
    if result_file_exists:
        score += 10
        feedback.append("Result file found.")
        
        # Check content accuracy
        try:
            reported_count = int(result_file_content)
            # Allow 30% tolerance between reported and actual database change
            # (Sometimes duplicates or existing data affect the exact delta)
            if abs(reported_count - new_visits) <= (new_visits * 0.3):
                score += 10
                feedback.append(f"Reported count ({reported_count}) matches database delta ({new_visits}).")
            else:
                feedback.append(f"Reported count ({reported_count}) disagrees with database delta ({new_visits}).")
        except ValueError:
            feedback.append(f"Result file content '{result_file_content}' is not a valid number.")
    else:
        feedback.append("Result file not created.")

    # DO NOTHING GATE
    # If no visits were imported, fail regardless of other artifacts
    if new_visits < 10:
        score = 0
        feedback = ["Critical Failure: No significant data imported."]
    
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }