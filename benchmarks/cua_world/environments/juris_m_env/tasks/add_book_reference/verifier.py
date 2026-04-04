#!/usr/bin/env python3
"""
Verifier for add_book_reference task.

Checks if a book item with specific metadata was added to the Juris-M library.
Uses robust JSON export from the container to verify SQL states.

Scoring Breakdown (100 pts):
- Book item exists: 15 pts
- Title correct: 15 pts
- Authors (Hart & Sacks) present: 25 pts
- Publisher correct: 10 pts
- Place correct: 5 pts
- Date correct: 10 pts
- Pages correct: 5 pts
- ISBN correct: 10 pts
- Created during task (anti-gaming): 5 pts
"""

import os
import json
import logging
import tempfile
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_book_reference(
    traj: Dict[str, Any],
    env_info: Dict[str, Any],
    task_info: Dict[str, Any],
) -> Dict[str, Any]:
    """Verify that the book reference was added correctly."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Get expected values from metadata
    metadata = task_info.get("metadata", {})
    expected_title = metadata.get("expected_title", "The Legal Process")
    
    # Retrieve result JSON
    try:
        temp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        temp.close()
        try:
            copy_from_env("/tmp/task_result.json", temp.name)
            with open(temp.name) as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp.name):
                os.unlink(temp.name)
    except Exception as e:
        logger.error(f"Failed to retrieve result: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not retrieve export result: {e}. Did the task complete successfully?",
        }

    if result.get("error"):
        return {"passed": False, "score": 0, "feedback": f"Error in export: {result['error']}"}

    score = 0
    feedback = []
    
    item_found = result.get("item_found", False)
    item_data = result.get("item", {})
    
    # 1. Item Existence (15 pts)
    if item_found:
        score += 15
        feedback.append("Book item found (+15)")
    else:
        feedback.append("No matching book item found in library")
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback),
            "details": result
        }

    # 2. Title Check (15 pts)
    title = item_data.get("title", "")
    if "legal process" in title.lower():
        score += 15
        feedback.append("Title correct (+15)")
    else:
        feedback.append(f"Title incorrect or missing. Found: '{title}'")

    # 3. Authors Check (25 pts)
    # Expect: Hart and Sacks
    creators = item_data.get("creators", [])
    hart_found = False
    sacks_found = False
    
    for c in creators:
        last = c.get("last", "").lower()
        if "hart" in last:
            hart_found = True
        if "sacks" in last:
            sacks_found = True
            
    if hart_found:
        score += 12
        feedback.append("Author 'Hart' found (+12)")
    else:
        feedback.append("Author 'Hart' missing")
        
    if sacks_found:
        score += 13
        feedback.append("Author 'Sacks' found (+13)")
    else:
        feedback.append("Author 'Sacks' missing")

    # 4. Publisher Check (10 pts)
    pub = item_data.get("publisher", "").lower()
    if "foundation" in pub:
        score += 10
        feedback.append("Publisher correct (+10)")
    else:
        feedback.append(f"Publisher incorrect/missing ('{pub}')")

    # 5. Place Check (5 pts)
    place = item_data.get("place", "").lower()
    if "westbury" in place or "ny" in place:
        score += 5
        feedback.append("Place correct (+5)")
    else:
        feedback.append(f"Place incorrect/missing ('{place}')")

    # 6. Date Check (10 pts)
    date_val = item_data.get("date", "")
    if "1994" in date_val:
        score += 10
        feedback.append("Date correct (+10)")
    else:
        feedback.append(f"Date incorrect/missing ('{date_val}')")

    # 7. Pages Check (5 pts)
    pages = item_data.get("num_pages", "")
    if "1378" in pages:
        score += 5
        feedback.append("Page count correct (+5)")
    else:
        feedback.append(f"Page count incorrect/missing ('{pages}')")

    # 8. ISBN Check (10 pts)
    isbn = item_data.get("isbn", "").replace("-", "")
    # Check for significant part of ISBN
    if "1566621" in isbn:
        score += 10
        feedback.append("ISBN correct (+10)")
    else:
        feedback.append(f"ISBN incorrect/missing ('{isbn}')")

    # 9. Anti-Gaming Timestamp Check (5 pts)
    if result.get("created_during_task", False):
        score += 5
        feedback.append("Item created during task (+5)")
    else:
        feedback.append("Item appears to be pre-existing (no points for creation time)")

    passed = score >= 60 and item_found
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": result
    }