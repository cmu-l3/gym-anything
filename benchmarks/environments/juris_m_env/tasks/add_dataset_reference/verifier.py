#!/usr/bin/env python3
"""
Verifier for add_dataset_reference task.
"""

import json
import os
import logging
import tempfile
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_dataset_reference(
    traj: Dict[str, Any],
    env_info: Dict[str, Any],
    task_info: Dict[str, Any],
) -> Dict[str, Any]:
    """Verify that the dataset reference was correctly added."""
    
    # Use copy_from_env to get the result file
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Load expected values from metadata
    metadata = task_info.get("metadata", {})
    expected_title = metadata.get("expected_title", "The Supreme Court Database")
    expected_repo = metadata.get("expected_repository", "Washington University School of Law")
    expected_url = metadata.get("expected_url", "scdb.wustl.edu")
    
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
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result: {e}"}

    if not result.get("item_found"):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No item with title 'The Supreme Court Database' was found in the library."
        }

    score = 0
    feedback_parts = []
    
    # Check Item Type (30 pts)
    if result.get("item_type_correct"):
        score += 30
        feedback_parts.append("Item type 'Dataset' is correct (+30)")
    else:
        feedback_parts.append("Item created but type is NOT 'Dataset'")

    # Check Title (15 pts) - Soft check
    title = result.get("title", "")
    if title and expected_title.lower() in title.lower():
        score += 15
        feedback_parts.append("Title matches (+15)")
    else:
        feedback_parts.append(f"Title incorrect: got '{title}'")

    # Check Author (15 pts)
    if result.get("author_found"):
        score += 15
        feedback_parts.append("Author 'Spaeth' found (+15)")
    else:
        feedback_parts.append("Author 'Spaeth' not found")

    # Check Repository (15 pts)
    repo = result.get("repository", "")
    if repo and "Washington" in repo:
        score += 15
        feedback_parts.append("Repository matches (+15)")
    else:
        feedback_parts.append(f"Repository incorrect: got '{repo}'")

    # Check URL (15 pts)
    url = result.get("url", "")
    if url and expected_url in url:
        score += 15
        feedback_parts.append("URL matches (+15)")
    else:
        feedback_parts.append(f"URL incorrect: got '{url}'")

    # Check Format (10 pts)
    fmt = result.get("format", "")
    if fmt and "Data file" in fmt:
        score += 10
        feedback_parts.append("Format matches (+10)")
    else:
        feedback_parts.append(f"Format incorrect: got '{fmt}'")

    # Anti-gaming check
    if not result.get("created_during_task"):
        feedback_parts.append("WARNING: Item appears to be old (pre-dating task start).")
        # Deduct points or fail if strictly enforcing anti-gaming
        score = 0
        feedback_parts.append("Anti-gaming check failed: Item not created during task.")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }