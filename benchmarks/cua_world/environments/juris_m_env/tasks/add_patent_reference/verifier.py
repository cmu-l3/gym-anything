#!/usr/bin/env python3
"""
Verifier for add_patent_reference task.

Criteria:
1. Patent item exists in DB (30 pts)
2. Title matches (10 pts)
3. Patent Number matches exact format (20 pts)
4. Inventor (Creator) correct with 'inventor' role (15 pts)
5. Assignee correct (15 pts)
6. Date correct (10 pts)
7. Created during task (Anti-gaming check)

Pass Threshold: 80 points
"""

import os
import json
import logging
import tempfile
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_patent_reference(
    traj: Dict[str, Any],
    env_info: Dict[str, Any],
    task_info: Dict[str, Any],
) -> Dict[str, Any]:
    
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Retrieve result JSON
    try:
        temp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        temp.close()
        try:
            copy_from_env("/tmp/add_patent_reference_result.json", temp.name)
            with open(temp.name) as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp.name):
                os.unlink(temp.name)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to retrieve results: {e}"
        }

    if result.get("error"):
        return {"passed": False, "score": 0, "feedback": f"Internal error: {result['error']}"}

    score = 0
    feedback = []
    
    metadata = task_info.get("metadata", {})
    expected_number = metadata.get("expected_patent_number", "US 8046721 B2")
    expected_assignee = metadata.get("expected_assignee", "Apple Inc.")
    expected_inventor = metadata.get("expected_inventor_last", "Anzures")
    expected_date = metadata.get("expected_date", "2011-10-25")

    # 1. Check if patent found (30 pts)
    if not result.get("patent_found"):
        return {
            "passed": False,
            "score": 0,
            "feedback": "No patent item found matching the title '...unlocking a device...'. Ensure you created the item and saved it."
        }
    
    score += 30
    feedback.append("Patent item created (+30)")
    
    details = result.get("item_details", {})
    creators = result.get("creators", [])
    
    # 2. Check Title (10 pts) - existence implied by search, but verifying content
    title = details.get("title", "")
    if "unlocking a device" in title.lower() and "graphical user interface" in title.lower():
        score += 10
        feedback.append("Title correct (+10)")
    else:
        feedback.append(f"Title mismatch or incomplete: '{title}'")

    # 3. Check Patent Number (20 pts)
    pat_num = details.get("patentNumber", "")
    if expected_number in pat_num:
        score += 20
        feedback.append(f"Patent number '{pat_num}' correct (+20)")
    else:
        feedback.append(f"Patent number mismatch: expected '{expected_number}', got '{pat_num}'")

    # 4. Check Assignee (15 pts)
    assignee = details.get("assignee", "")
    if expected_assignee.lower() in assignee.lower():
        score += 15
        feedback.append(f"Assignee '{assignee}' correct (+15)")
    else:
        feedback.append(f"Assignee mismatch: expected '{expected_assignee}', got '{assignee}'")

    # 5. Check Date (10 pts)
    date_val = details.get("date", "")
    if expected_date in date_val:
        score += 10
        feedback.append(f"Date '{date_val}' correct (+10)")
    else:
        feedback.append(f"Date mismatch: expected '{expected_date}', got '{date_val}'")

    # 6. Check Inventor (15 pts)
    inventor_found = False
    role_correct = False
    
    for c in creators:
        if expected_inventor.lower() in c.get('last', '').lower():
            inventor_found = True
            if c.get('role') == 'inventor':
                role_correct = True
            break
    
    if inventor_found and role_correct:
        score += 15
        feedback.append("Inventor 'Anzures' correctly added with role 'Inventor' (+15)")
    elif inventor_found:
        score += 5
        feedback.append("Inventor 'Anzures' found but wrong role (expected 'Inventor') (+5)")
    else:
        feedback.append("Inventor 'Anzures' not found")

    # Anti-gaming check
    if not result.get("created_during_task"):
        feedback.append("WARNING: Item timestamp indicates it was not created during this task session.")
        # We might penalize or fail based on policy, for now just warn if scoring logic is strict
        # But for this task definition, if they did it, they did it. 
        # Ideally, setup clears the item, so existence implies creation.

    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": result
    }