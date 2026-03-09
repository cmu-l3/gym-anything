#!/usr/bin/env python3
"""
Verifier for create_law_collection task.

Verification strategy:
1. Read exported JSON from VM via copy_from_env
2. Check that at least 1 collection was created
3. Check that the collection contains >=3 items

Scoring (100 points):
- At least 1 collection exists: 40 pts
- Collection has >=3 items: 40 pts
- Collection has >=4 items: +10 pts bonus
- Collection name suggests legal content: 10 pts

Pass threshold: 40 points (collection exists with items)
"""

import os
import json
import logging
import tempfile
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_create_law_collection(
    traj: Dict[str, Any],
    env_info: Dict[str, Any],
    task_info: Dict[str, Any],
) -> Dict[str, Any]:
    """Verify that a law collection was created with at least 3 items."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        temp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        temp.close()
        try:
            copy_from_env("/tmp/create_law_collection_result.json", temp.name)
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

    collection_count = result.get("collection_count", 0)
    max_items = result.get("max_items_in_collection", 0)
    coll_name = result.get("most_recent_collection", "")

    logger.info(f"collection_count={collection_count}, max_items={max_items}, name={coll_name!r}")

    # Collection exists
    if collection_count > 0:
        score += 40
        feedback.append(f"{collection_count} collection(s) created (+40)")
    else:
        feedback.append(
            "No collections found. Right-click 'My Library' in the left panel "
            "and select 'New Collection...'"
        )
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback), "details": result}

    # Items in collection
    if max_items >= 3:
        score += 40
        feedback.append(f"Collection has {max_items} items (+40)")
        if max_items >= 4:
            score += 10
            feedback.append("Collection has >=4 items (+10 bonus)")
    else:
        feedback.append(
            f"Collection has only {max_items} item(s) — need >=3. "
            "Select items and right-click > Add to Collection"
        )

    # Collection name hints at legal content
    legal_keywords = ["law", "legal", "court", "case", "constitution", "statute", "justice"]
    if any(k in coll_name.lower() for k in legal_keywords):
        score += 10
        feedback.append(f'Collection name "{coll_name}" suggests legal content (+10)')
    else:
        feedback.append(f'Collection named "{coll_name}"')

    passed = score >= 40 and max_items >= 3
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback),
        "details": result,
    }
