#!/usr/bin/env python3
"""
Verifier for update_labor_estimates task.

Scoring Logic:
- High Priority Open Issues: Must be 40.0 hours (30 pts)
- Normal Priority Open Issues: Must be 16.0 hours (30 pts)
- Low Priority Open Issues: Must be 8.0 hours (20 pts)
- Closed Issues: Must remain 0.0 hours (20 pts)
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_update_labor_estimates(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    issues = result.get('db_issues', [])
    task_start = result.get('task_start', 0)
    
    if not issues:
        return {"passed": False, "score": 0, "feedback": "No issues found in project database."}

    # Rubric
    rubric = {
        "High": 40.0,
        "Normal": 16.0,
        "Low": 8.0
    }

    # Counters
    total_open_high = 0
    total_open_normal = 0
    total_open_low = 0
    total_closed = 0
    
    correct_high = 0
    correct_normal = 0
    correct_low = 0
    correct_closed = 0
    
    feedback_details = []

    for issue in issues:
        priority = issue.get('priority')
        is_closed = issue.get('is_closed')
        actual_hours = issue.get('estimated_hours', 0.0)
        subject = issue.get('subject', 'Unknown')

        if is_closed:
            total_closed += 1
            # Closed issues should ideally be 0.0 (as seeded)
            if actual_hours == 0.0:
                correct_closed += 1
            else:
                feedback_details.append(f"❌ Closed issue '{subject}' modified to {actual_hours}h (should be 0)")
        else:
            expected = rubric.get(priority, 0.0)
            
            if priority == "High":
                total_open_high += 1
                if actual_hours == expected:
                    correct_high += 1
                else:
                    feedback_details.append(f"❌ High priority '{subject}' is {actual_hours}h (expected {expected}h)")
            elif priority == "Normal":
                total_open_normal += 1
                if actual_hours == expected:
                    correct_normal += 1
                else:
                    feedback_details.append(f"❌ Normal priority '{subject}' is {actual_hours}h (expected {expected}h)")
            elif priority == "Low":
                total_open_low += 1
                if actual_hours == expected:
                    correct_low += 1
                else:
                    feedback_details.append(f"❌ Low priority '{subject}' is {actual_hours}h (expected {expected}h)")

    # Calculate Score
    score = 0
    
    # 30 pts for High
    if total_open_high > 0:
        score += (correct_high / total_open_high) * 30
    
    # 30 pts for Normal
    if total_open_normal > 0:
        score += (correct_normal / total_open_normal) * 30
        
    # 20 pts for Low
    if total_open_low > 0:
        score += (correct_low / total_open_low) * 20
        
    # 20 pts for Closed (Integrity check)
    if total_closed > 0:
        score += (correct_closed / total_closed) * 20

    # Anti-gaming: Ensure at least some updates happened after start time
    # We check if any issue was updated recently (timestamp check)
    updated_count = sum(1 for i in issues if i.get('updated_on', 0) > task_start)
    if updated_count == 0 and score > 20:
        score = 0
        feedback_details.append("❌ No database updates detected after task start time.")

    passed = score >= 80

    feedback_str = "Verification Complete. "
    if not feedback_details:
        feedback_str += "All estimates correct."
    else:
        feedback_str += "Errors found: " + "; ".join(feedback_details[:3])
        if len(feedback_details) > 3:
            feedback_str += f" (+{len(feedback_details)-3} more)"

    return {
        "passed": passed,
        "score": int(score),
        "feedback": feedback_str,
        "details": {
            "correct_high": f"{correct_high}/{total_open_high}",
            "correct_normal": f"{correct_normal}/{total_open_normal}",
            "correct_low": f"{correct_low}/{total_open_low}",
            "correct_closed": f"{correct_closed}/{total_closed}"
        }
    }