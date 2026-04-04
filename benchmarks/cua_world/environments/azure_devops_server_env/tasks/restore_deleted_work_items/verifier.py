#!/usr/bin/env python3
import json
import logging
import os
import tempfile
import sys

logger = logging.getLogger(__name__)

def verify_restore_deleted_work_items(traj, env_info, task_info):
    """
    Verify that the user restored specific work items, assigned them to Sprint 2,
    and added a recovery comment.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Define score components
    SCORE_PER_ITEM_RESTORED = 15    # 3 items * 15 = 45
    SCORE_PER_ITEM_ITERATION = 10   # 3 items * 10 = 30
    SCORE_PER_ITEM_COMMENT = 8.33   # 3 items * ~8.33 = 25
    # Total = 100
    
    REQUIRED_COMMENT_PART = "Recovered from Recycle Bin"
    REQUIRED_ITERATION_SUFFIX = "Sprint 2"

    # Fetch result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\Users\\Docker\\task_results\\restore_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve or parse task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    item_states = result.get("ItemStates", [])
    if not item_states:
        return {"passed": False, "score": 0, "feedback": "No item states found in result."}

    total_score = 0
    feedback = []
    
    restored_count = 0
    iteration_count = 0
    comment_count = 0

    for item in item_states:
        item_id = item.get("Id")
        exists = item.get("Exists", False)
        is_deleted = item.get("IsDeleted", False) # Note: API usually sets this field only if true
        iteration = item.get("IterationPath", "")
        comments = item.get("Comments", [])
        
        # 1. Check Restoration
        # If 'Exists' is true and 'IsDeleted' is false/missing, it's restored.
        if exists and not is_deleted:
            total_score += SCORE_PER_ITEM_RESTORED
            restored_count += 1
            
            # 2. Check Iteration (Only check if restored)
            if iteration and iteration.endswith(REQUIRED_ITERATION_SUFFIX):
                total_score += SCORE_PER_ITEM_ITERATION
                iteration_count += 1
            else:
                feedback.append(f"Item {item_id}: Wrong iteration '{iteration}'")

            # 3. Check Comments (Only check if restored)
            has_valid_comment = False
            if comments:
                for c in comments:
                    if REQUIRED_COMMENT_PART.lower() in str(c).lower():
                        has_valid_comment = True
                        break
            
            if has_valid_comment:
                total_score += SCORE_PER_ITEM_COMMENT
                comment_count += 1
            else:
                feedback.append(f"Item {item_id}: Missing or incorrect recovery comment")
        else:
            feedback.append(f"Item {item_id}: Not restored")

    # Final scoring logic
    score = min(100, round(total_score))
    passed = (restored_count == 3 and iteration_count == 3 and comment_count >= 3)
    
    summary = (
        f"Restored: {restored_count}/3. "
        f"Correct Sprint: {iteration_count}/3. "
        f"Commented: {comment_count}/3."
    )
    
    if feedback:
        summary += " Issues: " + "; ".join(feedback)

    return {
        "passed": passed,
        "score": score,
        "feedback": summary
    }