#!/usr/bin/env python3
"""
Verifier for add_conference_paper_reference task.

Verification Criteria:
1. Item exists (created during task)
2. Item Type is "Conference Paper" (ID 10)
3. Title matches
4. Proceedings Title (field 12) matches
5. Conference Name (field 21) matches
6. Publisher, Date, Pages match
7. Authors match (Branting and Balderas)

Scoring:
- Item Exists: 10
- Correct Item Type: 20
- Title: 15
- Authors: 15
- Proceedings/Conf Fields: 20
- Publisher/Date/Pages: 20
"""

import os
import json
import logging
import tempfile
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_conference_paper(
    traj: Dict[str, Any],
    env_info: Dict[str, Any],
    task_info: Dict[str, Any],
) -> Dict[str, Any]:
    """Verify the added conference paper reference."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Get metadata
    metadata = task_info.get("metadata", {})
    expected_title = metadata.get("expected_title", "Explainable Legal Prediction")
    expected_type_id = metadata.get("expected_item_type_id", 10) # 10 is Conference Paper

    # Load result
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
            "feedback": f"Could not retrieve export result: {e}",
        }

    if "error" in result:
        return {"passed": False, "score": 0, "feedback": f"Error during verification export: {result['error']}"}

    score = 0
    feedback = []
    item = result.get("item", {})
    found = result.get("found", False)

    # 1. Check existence (10 pts)
    if not found:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No item with title 'Explainable Legal Prediction' found in library."
        }
    score += 10
    feedback.append("Item found (+10)")

    # 2. Check Item Type (20 pts)
    # Conference Paper ID is 10. Journal Article is 1 (usually).
    actual_type_id = item.get("item_type_id")
    if actual_type_id == expected_type_id:
        score += 20
        feedback.append("Correct Item Type: Conference Paper (+20)")
    else:
        feedback.append(f"Incorrect Item Type ID: {actual_type_id} (Expected {expected_type_id} for Conference Paper)")

    # 3. Check Title (15 pts) - already partially checked by find logic, but verify exactness
    actual_title = item.get("title", "")
    if expected_title.lower() in actual_title.lower():
        score += 15
        feedback.append("Title correct (+15)")
    else:
        feedback.append(f"Title mismatch. Expected: {expected_title}")

    # 4. Check Authors (15 pts)
    creators = item.get("creators", [])
    authors_found = 0
    # Expect Branting and Balderas
    has_branting = any("branting" in c.get("last", "").lower() for c in creators)
    has_balderas = any("balderas" in c.get("last", "").lower() for c in creators)

    if has_branting:
        authors_found += 1
    if has_balderas:
        authors_found += 1
    
    if authors_found == 2:
        score += 15
        feedback.append("Both authors found (+15)")
    elif authors_found == 1:
        score += 7
        feedback.append("One author found (+7)")
    else:
        feedback.append("Authors missing or incorrect")

    # 5. Check Proceedings/Conference Fields (20 pts)
    # Vital distinction: Proceedings Title vs Conference Name
    proc_title = item.get("proceedings_title", "")
    conf_name = item.get("conference_name", "")
    
    proc_ok = "legal knowledge" in proc_title.lower()
    conf_ok = "jurix" in conf_name.lower()

    if proc_ok and conf_ok:
        score += 20
        feedback.append("Proceedings Title and Conference Name correct (+20)")
    elif proc_ok:
        score += 10
        feedback.append("Proceedings Title correct, but Conference Name missing/wrong (+10)")
    elif conf_ok:
        score += 10
        feedback.append("Conference Name correct, but Proceedings Title missing/wrong (+10)")
    else:
        feedback.append("Proceedings Title and Conference Name fields incorrect or swapped")

    # 6. Check Publisher/Date/Pages (20 pts)
    pub = item.get("publisher", "")
    date = item.get("date", "")
    pages = item.get("pages", "")

    meta_score = 0
    if "ios" in pub.lower(): meta_score += 7
    if "2019" in date: meta_score += 7
    if "3-12" in pages: meta_score += 6
    
    score += meta_score
    if meta_score == 20:
        feedback.append("Publisher, Date, Pages correct (+20)")
    else:
        feedback.append(f"Metadata partial match ({meta_score}/20)")

    # Pass threshold: 75 pts (Must have correct type + title + mostly correct fields)
    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": result
    }