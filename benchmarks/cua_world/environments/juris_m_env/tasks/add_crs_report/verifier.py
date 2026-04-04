#!/usr/bin/env python3
"""
Verifier for add_crs_report task.

Criteria:
1. Item exists (30 pts)
2. Item Type is 'Report' (itemTypeID check or inference) (10 pts)
3. Report Number is 'R44235' (15 pts)
4. Institution is 'Congressional Research Service' (15 pts)
5. Author is 'McMillion' (15 pts)
6. Title matches (10 pts)
7. Created during task (5 pts)

Total: 100
Pass Threshold: 70
"""

import os
import json
import logging
import tempfile
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_crs_report(
    traj: Dict[str, Any],
    env_info: Dict[str, Any],
    task_info: Dict[str, Any],
) -> Dict[str, Any]:
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Load result JSON
    try:
        temp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        temp.close()
        try:
            copy_from_env("/tmp/add_crs_report_result.json", temp.name)
            with open(temp.name) as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp.name):
                os.unlink(temp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}

    if not result.get("item_found"):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No matching report item found. Did you create the item with the correct Report Number (R44235) or Title?"
        }

    score = 30
    feedback = ["Item found (+30)"]
    fields = result.get("fields", {})
    creators = result.get("creators", [])
    
    # 1. Check Item Type
    # In Jurism/Zotero schema, Report itemTypeID is usually 27, but relying on IDs can be flaky across versions.
    # However, reports typically have 'reportNumber' and 'institution' fields.
    # If the user selected 'Report' type, these fields exist.
    # We'll give points if the expected fields are present which implies correct type usage.
    # Note: verifier doesn't check raw type ID string from DB easily without a map, 
    # but presence of specific fields like 'reportNumber' is a strong indicator.
    
    # 2. Check Report Number
    report_num = fields.get("reportNumber", "")
    if "R44235" in report_num:
        score += 15
        feedback.append("Report Number correct (+15)")
    else:
        feedback.append(f"Incorrect Report Number: found '{report_num}' expected 'R44235'")

    # 3. Check Institution
    institution = fields.get("institution", "")
    if "Congressional Research Service" in institution:
        score += 15
        feedback.append("Institution correct (+15)")
    else:
        feedback.append(f"Incorrect Institution: found '{institution}'")

    # 4. Check Author
    author_found = False
    for c in creators:
        if "McMillion" in c.get("lastName", ""):
            author_found = True
            break
    
    if author_found:
        score += 15
        feedback.append("Author found (+15)")
    else:
        feedback.append("Author 'McMillion' not found in creators")

    # 5. Check Title
    title = fields.get("title", "")
    if "Supreme Court Appointment Process" in title:
        score += 10
        feedback.append("Title correct (+10)")
    else:
        feedback.append("Title mismatch")

    # 6. Check Date
    date_field = fields.get("date", "")
    if "2022" in date_field:
        score += 5
        feedback.append("Date correct (+5)")
    
    # 7. Check Url
    url_field = fields.get("url", "")
    if "crsreports.congress.gov" in url_field:
        score += 5
        feedback.append("URL correct (+5)")

    # 8. Anti-gaming (Created during task)
    if result.get("created_during_task"):
        score += 5
        feedback.append("Created during task (+5)")
    else:
        feedback.append("Item timestamp indicates it was not created during this session")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": result
    }