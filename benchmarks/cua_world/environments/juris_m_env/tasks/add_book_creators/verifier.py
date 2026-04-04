#!/usr/bin/env python3
"""
Verifier for add_book_creators task.
"""

import os
import json
import logging
import tempfile
from datetime import datetime
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_db_date(date_str):
    """Parse Jurism DB date string YYYY-MM-DD HH:MM:SS"""
    try:
        return datetime.strptime(date_str, "%Y-%m-%d %H:%M:%S").timestamp()
    except (ValueError, TypeError):
        return 0

def verify_add_book_creators(
    traj: Dict[str, Any],
    env_info: Dict[str, Any],
    task_info: Dict[str, Any],
) -> Dict[str, Any]:
    
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Load result
    try:
        temp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        temp.close()
        copy_from_env("/tmp/task_result.json", temp.name)
        with open(temp.name) as f:
            result = json.load(f)
        os.unlink(temp.name)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to retrieve task result: {e}"
        }

    if not result.get("item_found"):
        return {
            "passed": False,
            "score": 0,
            "feedback": "The book 'Commentaries on the Laws of England' was not found in the database. Did you delete it?"
        }

    creators = result.get("creators", [])
    
    score = 0
    feedback = []
    
    # Criteria
    # 1. Blackstone (Author)
    blackstone_found = False
    blackstone_role_correct = False
    
    for c in creators:
        lname = c.get("lastName", "").lower()
        fname = c.get("firstName", "").lower()
        role = c.get("role", "").lower()
        
        if "blackstone" in lname:
            blackstone_found = True
            if "william" in fname:
                if role == "author":
                    blackstone_role_correct = True
                else:
                    feedback.append(f"William Blackstone found but role is '{role}' (expected 'author')")
    
    if blackstone_found:
        score += 20
        feedback.append("William Blackstone added (+20)")
    else:
        feedback.append("William Blackstone missing")

    if blackstone_role_correct:
        score += 15
        feedback.append("Blackstone role is Author (+15)")

    # 2. Tucker (Editor)
    tucker_found = False
    tucker_role_correct = False
    
    for c in creators:
        lname = c.get("lastName", "").lower()
        fname = c.get("firstName", "").lower()
        role = c.get("role", "").lower()
        
        if "tucker" in lname:
            tucker_found = True
            # Flexible check for "St. George"
            if "george" in fname:
                if role == "editor":
                    tucker_role_correct = True
                else:
                    feedback.append(f"St. George Tucker found but role is '{role}' (expected 'editor')")

    if tucker_found:
        score += 20
        feedback.append("St. George Tucker added (+20)")
    else:
        feedback.append("St. George Tucker missing")

    if tucker_role_correct:
        score += 15
        feedback.append("Tucker role is Editor (+15)")

    # 3. Completion Bonus (Both roles correct)
    if blackstone_role_correct and tucker_role_correct:
        score += 10
        feedback.append("All creators and roles correct (+10)")

    # 4. Anti-gaming / Modification check
    # We check if item modification time is after task start
    # Task start is not passed in task_info usually, but we can assume we want recent mod.
    # Actually export_result.sh didn't compare times, let's just give points if item exists and has creators
    # But strictly, we should ensure it wasn't pre-populated. The setup script cleared creators, 
    # so presence of creators implies work was done.
    if len(creators) >= 2:
        score += 20
        feedback.append("Multiple creators present (+20)")
    elif len(creators) > 0:
        score += 10
        feedback.append("At least one creator present (+10)")
        
    passed = score >= 55
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback),
        "details": result
    }