#!/usr/bin/env python3
"""
Verifier for add_legal_blog_post task.

Verification Strategy:
- Check existence of 'Web Research' collection
- Check if item exists in that collection
- Verify metadata fields (Title, Author, Blog Title, Date, URL)
- Verify tag

Scoring (100 pts):
- Collection Created: 10
- Item Created in Collection: 10
- Item Type (Blog Post): 10
- Title Match: 15
- Author Match: 15
- Blog Title Match: 10
- Date & URL Match: 15
- Tag Added: 15
"""

import os
import json
import logging
import tempfile
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_legal_blog_post(
    traj: Dict[str, Any],
    env_info: Dict[str, Any],
    task_info: Dict[str, Any],
) -> Dict[str, Any]:
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        temp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        temp.close()
        try:
            copy_from_env("/tmp/add_legal_blog_post_result.json", temp.name)
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
            "feedback": f"Could not retrieve export result: {e}. Was the task completed?",
        }

    if "error" in result:
        return {"passed": False, "score": 0, "feedback": result["error"]}

    score = 0
    feedback = []
    
    # 1. Collection Created (10)
    if result.get("collection_exists"):
        score += 10
        feedback.append("Collection 'Web Research' created (+10)")
    else:
        feedback.append("Collection 'Web Research' not found")

    # 2. Item in Collection (10)
    if result.get("item_exists_in_collection"):
        score += 10
        feedback.append("Item found in collection (+10)")
    else:
        feedback.append("Target item not found in the 'Web Research' collection")
        # If item not found, metadata checks usually fail, but we'll check what we can
    
    # 3. Item Type (10)
    item_type = result.get("item_type", "").lower()
    if "blog" in item_type or "web" in item_type: # Accept blogPost or webpage if close enough
        score += 10
        feedback.append(f"Item type '{item_type}' accepted (+10)")
    else:
        feedback.append(f"Item type '{item_type}' incorrect (expected Blog Post)")

    # 4. Title Match (15)
    if result.get("title_match"):
        score += 15
        feedback.append("Title matches exactly (+15)")
    else:
        feedback.append(f"Title incorrect. Got: {result.get('actual_title', 'None')}")

    # 5. Author Match (15)
    if result.get("author_match"):
        score += 15
        feedback.append("Author (Howe) found (+15)")
    else:
        feedback.append("Author 'Howe' not found")

    # 6. Blog Title Match (10)
    if result.get("blog_title_match"):
        score += 10
        feedback.append("Blog Title (SCOTUSblog) found (+10)")
    else:
        feedback.append("Blog Title 'SCOTUSblog' not found")

    # 7. Date & URL Match (15)
    match_count = 0
    if result.get("date_match"): match_count += 1
    if result.get("url_match"): match_count += 1
    
    if match_count == 2:
        score += 15
        feedback.append("Date and URL match (+15)")
    elif match_count == 1:
        score += 7
        feedback.append("Partial Date/URL match (+7)")
    else:
        feedback.append("Date and URL incorrect or missing")

    # 8. Tag Added (15)
    if result.get("tag_match"):
        score += 15
        feedback.append("Tag 'standing' found (+15)")
    else:
        feedback.append("Tag 'standing' not found")

    passed = score >= 80
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": result
    }