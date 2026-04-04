#!/usr/bin/env python3
"""
Verifier for normalize_journal_names task.

Verifies that 5 specific journal abbreviations have been expanded to their full names.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_normalize_journal_names(traj, env_info, task_info):
    """
    Verify the journal name corrections.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Expected corrections mapping (Title Keyword -> Expected Full Journal Name)
    expected_map = task_info.get('metadata', {}).get('corrections', {
        "Minimum-Redundancy Codes": "Proceedings of the IRE",
        "Recursive Functions": "Communications of the ACM",
        "Connexion with Graphs": "Numerische Mathematik",
        "Mathematical Theory of Communication": "Bell System Technical Journal",
        "Elementary Number Theory": "American Journal of Mathematics"
    })

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    max_score = 100
    points_per_item = 20
    feedback_parts = []
    
    items = result.get("items", {})
    
    if not items:
        return {"passed": False, "score": 0, "feedback": "No target items found in database query"}

    # Check each item
    for title_key, expected_val in expected_map.items():
        actual_val = items.get(title_key)
        
        if actual_val is None:
            feedback_parts.append(f"Paper '{title_key[:15]}...' not found")
            continue

        # Check for exact match
        if actual_val.strip() == expected_val.strip():
            score += points_per_item
            feedback_parts.append(f"✓ '{title_key[:15]}...' correct")
        else:
            # Check for common partial errors
            if expected_val.lower() in actual_val.lower():
                feedback_parts.append(f"✗ '{title_key[:15]}...' incorrect format ('{actual_val}')")
            elif "proc" in actual_val.lower() or "commun" in actual_val.lower():
                 feedback_parts.append(f"✗ '{title_key[:15]}...' still abbreviated")
            else:
                 feedback_parts.append(f"✗ '{title_key[:15]}...' incorrect ('{actual_val}')")

    # Anti-gaming check: App should be running (minor check, not heavily penalized if crashed at end)
    if not result.get("app_running", False):
        feedback_parts.append("(Warning: Zotero was not running at verification time)")

    passed = (score >= 60)  # Need at least 3 correct

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }