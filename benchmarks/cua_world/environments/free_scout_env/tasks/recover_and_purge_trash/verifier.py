#!/usr/bin/env python3
"""
Verifier for recover_and_purge_trash task.

Goal:
1. Restore 'Signed Contract' conversation from Trash (must be active).
2. Permanently delete the 'Junk' conversations (must be gone from DB).
3. Trash folder should be empty.

Scoring:
- Target Preserved (Exists in DB): 40 pts
- Target Active (Not in Trash): 20 pts
- Junk Gone (Row count 0): 20 pts
- Trash Empty (Global trash count 0): 20 pts
- Bonus/Check: Target modified during task
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_recover_and_purge_trash(traj, env_info, task_info):
    """Verify the trash recovery and purge task."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result file
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
    feedback_parts = []
    
    # 1. Target Preserved (40 pts) - Critical: Don't delete the contract!
    target_exists = result.get('target_exists', False)
    if target_exists:
        score += 40
        feedback_parts.append("Contract ticket preserved in DB")
    else:
        feedback_parts.append("CRITICAL: Contract ticket was permanently deleted")
        
    # 2. Target Active (20 pts) - Must be restored from Trash
    target_is_active = result.get('target_is_active', False)
    target_modified = result.get('target_modified_during_task', False)
    
    if target_is_active:
        if target_modified:
            score += 20
            feedback_parts.append("Contract ticket successfully restored")
        else:
            # If it's active but wasn't modified, something is weird (maybe setup failed?)
            # But in the context of this task, if it's active, it's good.
            score += 20
            feedback_parts.append("Contract ticket is active")
    else:
        if target_exists:
            feedback_parts.append("Contract ticket is still in Trash (not restored)")
            
    # 3. Junk Gone (20 pts) - Specific junk items hard deleted
    junk_remaining = result.get('junk_remaining_count', 3)
    if junk_remaining == 0:
        score += 20
        feedback_parts.append("Junk tickets permanently deleted")
    else:
        # Partial credit? No, empty trash is all or nothing usually, 
        # but let's give partial if some are gone.
        # Assuming 3 junk items
        deleted_count = 3 - junk_remaining
        if deleted_count > 0:
            partial = int(20 * (deleted_count / 3))
            score += partial
            feedback_parts.append(f"Partial junk deletion ({deleted_count}/3)")
        else:
            feedback_parts.append("Junk tickets still present")
            
    # 4. Trash Empty (20 pts) - Global check
    total_trash = result.get('total_trash_count', 0)
    if total_trash == 0:
        score += 20
        feedback_parts.append("Trash folder is empty")
    else:
        feedback_parts.append(f"Trash not empty ({total_trash} items remaining)")

    # Pass threshold: 90
    # Must basically do everything perfect. 
    # If they restore the ticket (40+20=60) but don't empty trash, they fail.
    # If they empty trash but delete the ticket (0+0+20+20=40), they fail.
    
    passed = score >= 90
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }