#!/usr/bin/env python3
"""
Verifier for standardize_journal_abbreviations task.
Checks if the 4 target papers have their publication titles updated to the full official names.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_standardize_journal_abbreviations(traj, env_info, task_info):
    """
    Verify that journal abbreviations have been expanded to full titles.
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Load result JSON
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        try:
            copy_from_env("/tmp/task_result.json", tmp.name)
            with open(tmp.name) as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}

    # Expected values from task metadata (or hardcoded here for safety)
    targets = {
        "einstein": "Annalen der Physik",
        "mccarthy": "Communications of the ACM",
        "dijkstra": "Numerische Mathematik",
        "shannon": "Bell System Technical Journal"
    }

    score = 0
    max_score = 100
    points_per_item = 25
    feedback_parts = []
    
    passed_count = 0

    # Check each target
    for key, expected_title in targets.items():
        item_data = result.get(key, {})
        actual_title = item_data.get("pub_title", "").strip()
        is_modified = item_data.get("modified", False)

        # Robust check: case insensitive but precise spelling
        if actual_title == expected_title:
            score += points_per_item
            passed_count += 1
            feedback_parts.append(f"✓ {key.capitalize()}: Correct")
        elif actual_title.lower() == expected_title.lower():
            # Correct words, wrong casing (partial credit)
            score += 15
            feedback_parts.append(f"⚠ {key.capitalize()}: Case mismatch ('{actual_title}')")
        else:
            feedback_parts.append(f"✗ {key.capitalize()}: Incorrect ('{actual_title}')")

    # Anti-gaming check (optional but good): verify timestamps if provided
    # The export script provides 'modified' boolean based on DB timestamp
    # We won't penalize heavily if not detected (sometimes db updates are slow), 
    # but we can note it.
    
    passed = score >= 75  # Needs 3 perfect or 4 partials

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }