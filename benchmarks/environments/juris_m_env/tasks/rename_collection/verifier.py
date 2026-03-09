#!/usr/bin/env python3
"""
Verifier for rename_collection task.

Verification strategy:
1. Database State Check (Primary):
   - Old name ("Research") should be gone.
   - New name ("First Amendment Jurisprudence") should exist.
   - Collection ID should remain the same (proves rename, not delete+create).
   - Item count should be preserved.

2. VLM Check (Secondary):
   - Verify final screenshot shows the new name in the UI.

Scoring:
- New Name Exists: 30 pts
- Old Name Removed: 20 pts
- Same Collection ID (Preserved): 20 pts
- Items Preserved: 20 pts
- VLM Confirmation: 10 pts

Pass Threshold: 70 pts
"""

import os
import json
import logging
import tempfile
from typing import Dict, Any

# Gym Anything VLM utilities (assumed available in environment)
try:
    from gym_anything.vlm import get_final_screenshot, query_vlm
except ImportError:
    # Mock for local testing if gym_anything not installed
    def get_final_screenshot(traj): return None
    def query_vlm(images, prompt): return {"success": False}

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_rename_collection(
    traj: Dict[str, Any],
    env_info: Dict[str, Any],
    task_info: Dict[str, Any],
) -> Dict[str, Any]:
    """Verify the rename_collection task."""
    
    # 1. Setup and Retrieve Data
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Infrastructure error: copy_from_env not available"}

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
            "feedback": f"Could not retrieve task result: {e}. Did the task scripts run?",
        }

    if "error" in result:
        return {"passed": False, "score": 0, "feedback": f"Task error: {result['error']}"}

    # 2. Extract Data
    initial_id = str(result.get("initial_collection_id", ""))
    initial_count = int(result.get("initial_item_count", 0))
    
    old_name_exists = result.get("old_name_exists", True)
    new_name_exists = result.get("new_name_exists", False)
    new_id = str(result.get("new_collection_id", ""))
    new_count = int(result.get("new_collection_item_count", 0))
    modified_during_task = result.get("modified_during_task", False)

    score = 0
    feedback = []

    # 3. Database Verification Logic
    
    # Check 1: New Name Exists (30 pts)
    if new_name_exists:
        score += 30
        feedback.append("Success: Collection 'First Amendment Jurisprudence' found.")
    else:
        feedback.append("Fail: Collection 'First Amendment Jurisprudence' NOT found.")

    # Check 2: Old Name Removed (20 pts)
    if not old_name_exists:
        score += 20
        feedback.append("Success: Old collection 'Research' is gone.")
    else:
        feedback.append("Fail: Old collection 'Research' still exists.")

    # Check 3: ID Preservation (Rename vs Recreate) (20 pts)
    # This is critical for "Rename" semantics. If they deleted and recreated, ID changes.
    id_match = False
    if initial_id and new_id and (initial_id == new_id):
        id_match = True
        score += 20
        feedback.append("Success: Collection ID preserved (verified rename operation).")
    elif new_name_exists:
        feedback.append(f"Warning: Collection ID changed ({initial_id} -> {new_id}). Did you delete and recreate it?")
    
    # Check 4: Item Preservation (20 pts)
    if new_count == initial_count and new_count > 0:
        score += 20
        feedback.append(f"Success: All {initial_count} items preserved.")
    else:
        if new_count == 0:
             feedback.append("Fail: The new collection is empty.")
        else:
             feedback.append(f"Fail: Item count changed ({initial_count} -> {new_count}).")

    # 4. VLM Verification (10 pts)
    # Visual check to ensure the UI reflects the change
    vlm_score = 0
    final_screenshot = get_final_screenshot(traj)
    
    if final_screenshot and score >= 50: # Only check VLM if DB checks show some promise
        try:
            vlm_response = query_vlm(
                images=[final_screenshot],
                prompt="Look at the sidebar or collection list in this software. Does a collection named 'First Amendment Jurisprudence' appear? Does 'Research' appear? Answer JSON: {'new_name_visible': bool, 'old_name_visible': bool}"
            )
            # Simple fallback parsing if VLM returns dict directly or string
            if isinstance(vlm_response, dict):
                if vlm_response.get("new_name_visible", False):
                    vlm_score = 10
                    feedback.append("Visual Check: New name confirmed in UI.")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            # If VLM fails but DB is perfect, we can grant these points or ignore
            pass
    
    # If DB checks are perfect (90 pts), grant VLM points automatically if VLM failed or wasn't run
    # This prevents VLM flakes from failing a perfect programmatic execution
    if score == 90:
        score += 10
        feedback.append("Perfect database state implies visual success.")
    else:
        score += vlm_score

    # 5. Final Result
    passed = score >= 70 and new_name_exists
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": result
    }