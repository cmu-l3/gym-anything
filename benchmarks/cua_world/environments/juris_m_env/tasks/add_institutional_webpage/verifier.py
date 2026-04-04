#!/usr/bin/env python3
"""
Verifier for add_institutional_webpage task.

Verification Strategy:
1. Check if the item '2023 Merger Guidelines' exists.
2. Check if the item type is Webpage (itemTypeID 12 in Zotero schema).
3. Check if the author is 'Federal Trade Commission'.
4. CRITICAL: Check if the author's fieldMode is 1 (Single Field).
   - fieldMode 0 = Two fields (Last, First)
   - fieldMode 1 = Single field (Institution)
5. Check optional metadata (URL, Date).

Scoring:
- Item exists: 10
- Type correct: 10
- Author name correct: 20
- Institutional Mode Used (fieldMode=1): 40 (This is the key skill)
- Metadata correct: 20
"""

import os
import json
import logging
import tempfile
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_institutional_webpage(
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
        try:
            copy_from_env("/tmp/task_result.json", temp.name)
            with open(temp.name) as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp.name):
                os.unlink(temp.name)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Could not retrieve result file: {e}"
        }

    if "error" in result:
        return {"passed": False, "score": 0, "feedback": result["error"]}

    score = 0
    feedback = []

    # 1. Item Exists
    if result.get("item_found", False):
        score += 10
        feedback.append("Item '2023 Merger Guidelines' created (+10)")
    else:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Item '2023 Merger Guidelines' not found in library.",
            "details": result
        }

    # 2. Item Type (Webpage is usually 12, but we accept if it exists)
    # We won't strict check the ID integer as it might vary, but verify it's not empty
    item_type_id = result.get("item_type_id", "")
    if item_type_id and str(item_type_id) == "12": # Standard Zotero webpage ID
        score += 10
        feedback.append("Item type is Webpage (+10)")
    else:
        # Partial credit if found but weird ID
        feedback.append(f"Item type ID is {item_type_id} (expected 12/Webpage)")
        score += 5

    # 3. Author Name
    author_name = result.get("author_name", "")
    expected_author = "Federal Trade Commission"
    
    # Check for name correctness
    if expected_author.lower() in author_name.lower():
        score += 20
        feedback.append(f"Author name '{author_name}' matches (+20)")
    else:
        feedback.append(f"Author name mismatch: Got '{author_name}', expected '{expected_author}'")

    # 4. Field Mode (The Core Test)
    field_mode = str(result.get("author_field_mode", "0"))
    if field_mode == "1":
        score += 40
        feedback.append("Correctly used Single Field mode for institutional author (+40)")
    else:
        feedback.append("FAILED: Author entered as Person (Last, First) instead of Institution (Single Field). Use the small switch icon next to the author field.")
        
    # 5. Metadata
    metadata_score = 0
    date_val = result.get("date", "")
    url_val = result.get("url", "")
    
    if "2023" in date_val:
        metadata_score += 10
    if "ftc.gov" in url_val:
        metadata_score += 10
    
    score += metadata_score
    if metadata_score > 0:
        feedback.append(f"Metadata (Date/URL) correct (+{metadata_score})")

    # Anti-gaming
    if not result.get("created_during_task", False):
        feedback.append("Warning: Item timestamp indicates it wasn't created during this task session.")
        # We don't fail, but we note it.

    return {
        "passed": score >= 80,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": result
    }