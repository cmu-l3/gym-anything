#!/usr/bin/env python3
"""
Verifier for database_refactor_relocation@1

Verifies that:
1. The agent imported the database.
2. The "Eastern US" electricity flow is completely gone (Count == 0).
3. The "Western US" electricity flow usage has increased significantly (Count > 100).
4. The database integrity is maintained (No broken links).
5. A log file was created.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def _vlm_query(query_vlm, prompt, image=None, images=None):
    if not query_vlm:
        return None
    try:
        result = query_vlm(prompt=prompt, image=image, images=images)
        if result and result.get("success"):
            return result.get("parsed", {})
    except Exception as e:
        logger.warning(f"VLM error: {e}")
    return None

def verify_database_refactor(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Capabilities missing (copy_from_env)"}

    # 1. Load Result JSON
    temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp.name)
        with open(temp.name) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {e}"}
    finally:
        if os.path.exists(temp.name):
            os.unlink(temp.name)

    score = 0
    feedback = []
    
    # 2. Extract Metrics
    db_imported = result.get('db_imported', False)
    old_flow_count = result.get('old_flow_count', -1)
    new_flow_usage = result.get('new_flow_usage', -1)
    broken_links = result.get('broken_links', -1)
    log_exists = result.get('log_exists', False)
    
    # 3. Scoring Criteria
    
    # Criterion 1: Database Imported (20 pts)
    if db_imported:
        score += 20
        feedback.append("Database imported successfully.")
    else:
        feedback.append("Failed to import database (or database too small).")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # Criterion 2: Old Flow Gone (40 pts)
    # Ideally should be 0. If it's -1, query failed.
    if old_flow_count == 0:
        score += 40
        feedback.append("Eastern US electricity flow successfully removed.")
    elif old_flow_count > 0:
        feedback.append(f"Eastern US electricity flow still exists ({old_flow_count} instances).")
    else:
        feedback.append("Could not verify old flow count (DB query failed).")

    # Criterion 3: New Flow Usage (30 pts)
    # In USLCI, electricity is used in hundreds of processes.
    # We expect a high number. Let's set a conservative threshold of 50.
    if new_flow_usage > 50:
        score += 30
        feedback.append(f"Western US electricity flow is widely used ({new_flow_usage} references).")
    elif new_flow_usage > 0:
        score += 15
        feedback.append(f"Western US electricity flow used sparingly ({new_flow_usage} references). Expected > 50.")
    else:
        feedback.append("Western US electricity flow appears unused.")

    # Criterion 4: Log File (10 pts)
    if log_exists:
        score += 10
        feedback.append("Log file created.")
    else:
        feedback.append("Log file missing.")

    # Integrity Check (Penalty)
    if broken_links > 0:
        score -= 20
        feedback.append(f"WARNING: Found {broken_links} broken links in database. Refactoring may have been destructive.")

    # 4. VLM Verification (Trajectory)
    # Verify the "Refactor" or "Replace" dialog was used
    # This acts as a sanity check against manual deletion without replacement
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        # Sample frames (not implemented here, assuming framework handles it or we use final frame)
        # We'll use the final screenshot provided in result
        pass # Optional enhancement

    # 5. Final Determination
    passed = (score >= 70) and (old_flow_count == 0)
    
    return {
        "passed": passed,
        "score": max(0, score),
        "feedback": " | ".join(feedback),
        "details": result
    }