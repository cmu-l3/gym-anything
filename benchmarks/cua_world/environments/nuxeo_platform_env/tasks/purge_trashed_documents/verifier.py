#!/usr/bin/env python3
"""
Verifier for purge_trashed_documents task.
Verifies that specific documents were permanently deleted (return 404)
while others remain in the trash (return 200 + isTrashed=true).
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_purge_trashed_documents(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Fetch result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # -----------------------------------------------------------
    # CRITERION 1: Purged Documents (45 pts total, 15 each)
    # -----------------------------------------------------------
    # They should return "404" (completely gone)
    
    purged_correctly = 0
    for name, status_key in [("Anderson", "status_anderson"), 
                             ("Baker", "status_baker"), 
                             ("Chen", "status_chen")]:
        status = result.get(status_key, "unknown")
        if status == "404":
            score += 15
            purged_correctly += 1
            feedback_parts.append(f"{name} purged ✓")
        elif status == "200_TRASHED":
            feedback_parts.append(f"{name} still in trash ✗")
        elif status == "200_ALIVE":
            feedback_parts.append(f"{name} restored (should be purged) ✗")
        else:
            feedback_parts.append(f"{name} status unclear ({status}) ✗")

    # -----------------------------------------------------------
    # CRITERION 2: Preserved Documents (30 pts total, 15 each)
    # -----------------------------------------------------------
    # They should be "200_TRASHED"
    
    preserved_correctly = 0
    for name, status_key in [("Davis", "status_davis"), 
                             ("Evans", "status_evans")]:
        status = result.get(status_key, "unknown")
        if status == "200_TRASHED":
            score += 15
            preserved_correctly += 1
            feedback_parts.append(f"{name} preserved in trash ✓")
        elif status == "404":
            feedback_parts.append(f"{name} deleted (should be kept) ✗")
            # Major penalty for deleting legal hold docs? 
            # The rubric is additive, so they just lose points here.
        elif status == "200_ALIVE":
            feedback_parts.append(f"{name} restored (should stay in trash) ✗")
        else:
            feedback_parts.append(f"{name} status unclear ✗")

    # -----------------------------------------------------------
    # CRITERION 3: Workspace Integrity (10 pts)
    # -----------------------------------------------------------
    ws_code = str(result.get("workspace_http_code", "0"))
    if ws_code == "200":
        score += 10
        feedback_parts.append("Workspace intact ✓")
    else:
        feedback_parts.append(f"Workspace deleted or missing ({ws_code}) ✗")

    # -----------------------------------------------------------
    # CRITERION 4: Trash Count (15 pts)
    # -----------------------------------------------------------
    # Should be exactly 2 (Davis + Evans)
    count = result.get("trash_count", -1)
    if count == 2:
        score += 15
        feedback_parts.append("Trash count correct (2) ✓")
    elif count == 5:
        feedback_parts.append("Trash count is 5 (Nothing happened) ✗")
        # Anti-gaming: If nothing happened, zero the purged scores
        if purged_correctly == 0:
            score = 0
            return {"passed": False, "score": 0, "feedback": "Do Nothing detected: All documents still in trash."}
    elif count == 0:
         # If count is 0, check if Davis/Evans were purged
         if preserved_correctly == 0:
             feedback_parts.append("Trash count 0 (Everything deleted) ✗")
    else:
        feedback_parts.append(f"Trash count incorrect ({count}) ✗")

    # -----------------------------------------------------------
    # Final Scoring
    # -----------------------------------------------------------
    # Pass threshold: 70
    # Must purge all 3 target docs AND preserve both hold docs
    # (3*15 + 2*15 = 75 points minimal for core task)
    
    passed = (score >= 70) and (purged_correctly == 3) and (preserved_correctly == 2)
    
    if passed:
        feedback = "Success: " + ", ".join(feedback_parts)
    else:
        feedback = "Failed: " + ", ".join(feedback_parts)

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }