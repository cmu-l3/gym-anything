#!/usr/bin/env python3
"""
Verifier for deduplicate_project_files task.

Verifies:
1. The older document (specific UID) is in the trash.
2. The newer document (specific UID) is NOT in the trash.
3. The Finance workspace has exactly 1 active document remaining.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_deduplicate_project_files(traj, env_info, task_info):
    """
    Verify that the older duplicate was trashed and the newer one kept.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Extract data
    older_doc = result.get("older_doc", {})
    newer_doc = result.get("newer_doc", {})
    active_count = result.get("active_children_count", -1)

    score = 0
    feedback = []

    # Criterion 1: Older document should be trashed (50 pts)
    # Note: If it doesn't exist (permanently deleted), that's technically removing it from workspace,
    # but the task asked to "move to trash". However, effectively getting rid of it is the main goal.
    # Nuxeo API usually returns isTrashed=true for soft deletes.
    if older_doc.get("exists") and older_doc.get("is_trashed"):
        score += 50
        feedback.append("Older duplicate correctly moved to Trash.")
    elif not older_doc.get("exists"):
        # If permanently deleted, we might award partial points or full, but instructions said "move to trash"
        score += 40
        feedback.append("Older duplicate was permanently deleted (expected Trash).")
    else:
        feedback.append("Older duplicate is still active in the workspace.")

    # Criterion 2: Newer document should be active (40 pts)
    if newer_doc.get("exists") and not newer_doc.get("is_trashed"):
        score += 40
        feedback.append("Newer duplicate remains active.")
    elif newer_doc.get("exists") and newer_doc.get("is_trashed"):
        feedback.append("Newer duplicate was incorrectly Trashed.")
    else:
        feedback.append("Newer duplicate is missing.")

    # Criterion 3: Clean workspace state (10 pts)
    # Should have exactly 1 active document (the newer one)
    if active_count == 1:
        score += 10
        feedback.append("Workspace correctly contains exactly one active document.")
    elif active_count > 1:
        feedback.append(f"Workspace still has {active_count} active documents (cleanup incomplete).")
    elif active_count == 0:
        feedback.append("Workspace is empty (both documents removed?).")

    # Final Pass/Fail
    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }