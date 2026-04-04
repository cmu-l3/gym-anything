#!/usr/bin/env python3
"""
Verifier for customize_library_columns task.

Verification Strategy:
1.  Read exported JSON which contains parsed column states from `xulstore.json`.
2.  Check if `zotero-items-column-dateAdded` is visible (`hidden` != "true").
3.  Check if `zotero-items-column-itemType` is visible (`hidden` != "true").
4.  Verify settings were actually modified during the task (anti-gaming).

Scoring (100 pts):
- Date Added column visible: 40 pts
- Item Type column visible: 40 pts
- Settings saved/modified during task: 20 pts
"""

import os
import json
import logging
import tempfile
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_customize_library_columns(
    traj: Dict[str, Any],
    env_info: Dict[str, Any],
    task_info: Dict[str, Any],
) -> Dict[str, Any]:
    """Verify that Date Added and Item Type columns were enabled."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve result JSON
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_file.close()
        try:
            copy_from_env("/tmp/task_result.json", temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_file.name):
                os.unlink(temp_file.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}

    # 2. Analyze result
    score = 0
    feedback_parts = []
    
    col_states = result.get("column_states", {})
    settings_modified = result.get("settings_modified", False)
    
    # Check "Date Added"
    # Logic: In XUL, if 'hidden' attribute is missing, it defaults to visible? 
    # Usually Zotero writes {"hidden": "true"} for hidden cols.
    # If explicitly enabled, it might be {"hidden": "false"} or just present without hidden=true.
    # We interpret "visible" as: key exists AND (hidden is NOT "true")
    
    date_added = col_states.get("zotero-items-column-dateAdded", {})
    if date_added and date_added.get("hidden") != "true":
        score += 40
        feedback_parts.append("'Date Added' column is visible (+40)")
    else:
        feedback_parts.append("'Date Added' column is NOT visible")

    # Check "Item Type"
    item_type = col_states.get("zotero-items-column-itemType", {})
    if item_type and item_type.get("hidden") != "true":
        score += 40
        feedback_parts.append("'Item Type' column is visible (+40)")
    else:
        feedback_parts.append("'Item Type' column is NOT visible")

    # Check modification timestamp (Anti-gaming)
    if settings_modified:
        score += 20
        feedback_parts.append("Settings updated successfully (+20)")
    else:
        # If columns are visible but file wasn't modified, maybe it was already set?
        # But setup script deletes the file, so this implies agent did nothing or didn't close app properly.
        # We allow partial credit if they are visible, but note the issue.
        if score > 0:
            feedback_parts.append("Warning: Settings file not modified during task (did you close the app?)")
        else:
            feedback_parts.append("Settings not modified")

    passed = (score >= 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "column_states": col_states,
            "modified": settings_modified
        }
    }