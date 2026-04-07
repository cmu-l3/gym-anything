#!/usr/bin/env python3
"""
Verifier for instantiate_project_from_template task.

Verifies:
1. 'Project Phoenix' workspace exists in 'Projects'.
2. Title is exactly 'Project Phoenix'.
3. Name/ID is 'Project-Phoenix' (implied by path).
4. Structure (subfolders) matches the template.
5. Original template still exists (was copied, not moved).
6. Anti-gaming: Workspace created AFTER task start.
"""

import json
import os
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_instantiate_project_from_template(traj, env_info, task_info):
    """
    Verify the agent correctly copied the template and renamed it.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result file
    import tempfile
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # ----------------------------------------------------------------
    # 1. Check Source Preservation (10 pts)
    # ----------------------------------------------------------------
    if result.get('source_exists'):
        score += 10
        feedback_parts.append("Source template preserved")
    else:
        feedback_parts.append("CRITICAL: Source template was deleted or moved!")
        
    # ----------------------------------------------------------------
    # 2. Check Target Existence & Path (30 pts)
    # ----------------------------------------------------------------
    target_exists = result.get('target_exists')
    target_path = result.get('target_path', '')
    
    # Check if the path ends correctly (verifies the Rename/Name ID part)
    if target_exists and target_path.endswith("/Projects/Project-Phoenix"):
        score += 30
        feedback_parts.append("Target workspace created with correct ID")
    elif target_exists:
        # Exists but wrong path ID (e.g. they renamed title but not local name)
        score += 15
        feedback_parts.append(f"Target workspace exists but ID is incorrect (path: {target_path})")
    else:
        # Check if they just copied it but forgot to rename anything
        project_contents = result.get('project_contents', [])
        found_copy = any("Standard Project Template" in t for t in project_contents)
        if found_copy:
             feedback_parts.append("Found a copy of the template, but it wasn't renamed to 'Project Phoenix'")
             # Small partial credit for successful copy
             score += 5
        else:
             feedback_parts.append("Target workspace not found")
        
        return {
            "passed": False,
            "score": score,
            "feedback": "; ".join(feedback_parts)
        }

    # ----------------------------------------------------------------
    # 3. Check Target Title (20 pts)
    # ----------------------------------------------------------------
    target_title = result.get('target_title', '')
    if target_title == "Project Phoenix":
        score += 20
        feedback_parts.append("Target title matches")
    elif "Phoenix" in target_title:
        score += 10
        feedback_parts.append(f"Target title partially correct ('{target_title}')")
    else:
        feedback_parts.append(f"Target title incorrect ('{target_title}')")

    # ----------------------------------------------------------------
    # 4. Check Internal Structure (30 pts)
    # ----------------------------------------------------------------
    children_names = result.get('children_names', [])
    required_children = ["01-Planning", "02-Financials", "03-Legal"]
    
    missing = [c for c in required_children if c not in children_names]
    
    if not missing:
        score += 30
        feedback_parts.append("Full folder structure verified")
    else:
        # Partial credit per folder
        found_count = len(required_children) - len(missing)
        points = found_count * 10
        score += points
        feedback_parts.append(f"Structure incomplete. Missing: {', '.join(missing)}")

    # ----------------------------------------------------------------
    # 5. Anti-Gaming / Timestamp (10 pts)
    # ----------------------------------------------------------------
    # Nuxeo stores times like "2023-10-25T10:00:00.00Z"
    # Task result has task_start in epoch seconds
    created_str = result.get('target_created')
    task_start = result.get('task_start', 0)
    
    is_new = False
    if created_str and task_start:
        try:
            # Simple check: created time > task start
            # Parse Nuxeo time to epoch
            dt = datetime.strptime(created_str.split('.')[0], "%Y-%m-%dT%H:%M:%S")
            created_epoch = dt.timestamp()
            if created_epoch > task_start:
                is_new = True
        except Exception as e:
            logger.warning(f"Time parse error: {e}")
            # Fallback: if we made it this far and UIDs are different, it's likely fine
            # assuming the setup script cleared the path first.
            is_new = True
            
    if result.get('target_uid') == result.get('source_uid'):
        # They are the same object! Agent likely moved instead of copied, or we are querying the wrong thing
        score = 0
        feedback_parts.append("FAIL: Target UID matches Source UID (Moved instead of Copied?)")
        is_new = False

    if is_new:
        score += 10
    else:
        feedback_parts.append("Creation timestamp verification failed or object is stale")
        # Penalize if likely stale
        score = max(0, score - 20)

    # ----------------------------------------------------------------
    # Final Result
    # ----------------------------------------------------------------
    passed = score >= 80  # Requires existence (30) + title (20) + structure (30)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }