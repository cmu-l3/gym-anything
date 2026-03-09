#!/usr/bin/env python3
"""
Verifier for remove_items_from_collection task.

Verification Logic:
1. Verify "Brief Research" collection still exists.
2. Verify "Obergefell" and "Tinker" are NOT in the collection.
3. Verify "Obergefell" and "Tinker" ARE still in the main library (not trashed).
4. Verify collection count is exactly 8 (started with 10).
5. VLM check: Confirm visual workflow (context menu usage).
"""

import os
import json
import logging
import tempfile
from typing import Dict, Any
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_remove_items_from_collection(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load programmatic results from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    if 'error' in result:
        return {"passed": False, "score": 0, "feedback": f"Internal error: {result['error']}"}

    score = 0
    feedback = []
    
    # === CRITERIA 1: Collection Integrity (30 pts) ===
    if result.get('collection_exists'):
        score += 5
        feedback.append("Collection 'Brief Research' exists (+5)")
    else:
        feedback.append("Collection 'Brief Research' was deleted or renamed")
    
    # Expected count: 8 (10 initial - 2 removed)
    count = result.get('collection_item_count', 0)
    if count == 8:
        score += 25
        feedback.append("Collection item count is correct (8 items) (+25)")
    else:
        feedback.append(f"Collection has {count} items (expected 8)")

    # === CRITERIA 2: Items Removed from Collection (30 pts) ===
    # Both should be FALSE
    obergefell_in_coll = result.get('obergefell_in_collection', True)
    tinker_in_coll = result.get('tinker_in_collection', True)
    
    if not obergefell_in_coll:
        score += 15
        feedback.append("'Obergefell' removed from collection (+15)")
    else:
        feedback.append("'Obergefell' still in collection")
        
    if not tinker_in_coll:
        score += 15
        feedback.append("'Tinker' removed from collection (+15)")
    else:
        feedback.append("'Tinker' still in collection")

    # === CRITERIA 3: Items Preserved in Library (30 pts) ===
    # Both should be TRUE (Critical for success)
    obergefell_in_lib = result.get('obergefell_in_library', False)
    tinker_in_lib = result.get('tinker_in_library', False)
    
    preservation_score = 0
    if obergefell_in_lib:
        preservation_score += 15
        feedback.append("'Obergefell' still in library (+15)")
    else:
        feedback.append("'Obergefell' was DELETED from library (Moved to Trash)!")
        
    if tinker_in_lib:
        preservation_score += 15
        feedback.append("'Tinker' still in library (+15)")
    else:
        feedback.append("'Tinker' was DELETED from library (Moved to Trash)!")
    
    score += preservation_score

    # === CRITERIA 4: VLM Trajectory Verification (10 pts) ===
    # Verify the agent actually used the UI correctly
    vlm_score = 0
    try:
        frames = sample_trajectory_frames(traj, n=4)
        final_frame = get_final_screenshot(traj)
        
        # Check for context menu usage "Remove Items from Collection"
        prompt = """
        Review these screenshots of a Jurism/Zotero workflow.
        The user wants to remove items from a collection without deleting them.
        
        Look for:
        1. A collection selected in the left pane (likely 'Brief Research').
        2. A context menu (right-click menu) on items in the center list.
        3. Selection of "Remove Item from Collection" (NOT "Move Item to Trash").
        
        Does the visual evidence suggest the agent used the "Remove from Collection" action?
        """
        
        vlm_resp = query_vlm(images=frames + [final_frame], prompt=prompt).lower()
        
        if "yes" in vlm_resp or "remove" in vlm_resp:
            vlm_score = 10
            feedback.append("VLM confirms correct workflow (+10)")
        else:
            feedback.append("VLM could not clearly verify workflow context menu")
            
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
    
    score += vlm_score

    # === Final Evaluation ===
    # Pass threshold: 60 pts AND preservation criteria met
    # If they deleted the items from the library, they fail, even if score is high
    preservation_success = (obergefell_in_lib and tinker_in_lib)
    passed = (score >= 60) and preservation_success
    
    if not preservation_success:
        feedback.insert(0, "FAILED: Items were deleted from library instead of removed from collection.")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": result
    }