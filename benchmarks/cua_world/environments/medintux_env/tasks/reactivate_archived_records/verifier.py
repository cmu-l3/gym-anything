#!/usr/bin/env python3
"""
Verifier for Reactivate Archived Records task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_reactivate_archived_records(traj, env_info, task_info):
    """
    Score the restoration of patient records.
    
    Criteria:
    1. Records present in 'fchpat' (Data storage) - 30 pts
    2. Records present in 'IndexNomPrenom' (Search index) - 40 pts
       (This is weighted higher because it's the most common mistake to miss the index table)
    3. Records removed from 'ArchivedPatients' - 20 pts
    4. No collateral damage (other archives untouched) - 10 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    total_targets = result.get("total_targets", 3)
    if total_targets == 0:
        return {"passed": False, "score": 0, "feedback": "Setup error: No targets defined"}

    # 1. Data Table Restoration (30 pts)
    # 10 pts per patient
    data_count = result.get("restored_to_data_table_count", 0)
    data_pts = (data_count / total_targets) * 30
    score += data_pts
    if data_count == total_targets:
        feedback.append("All patients restored to data table.")
    else:
        feedback.append(f"Only {data_count}/{total_targets} patients in data table.")

    # 2. Index Table Restoration (40 pts)
    # This is critical for the app to actually see the patients
    index_count = result.get("restored_to_index_table_count", 0)
    index_pts = (index_count / total_targets) * 40
    score += index_pts
    if index_count == total_targets:
        feedback.append("All patients restored to search index (visible in app).")
    else:
        feedback.append(f"Only {index_count}/{total_targets} patients in search index (likely invisible in app).")

    # 3. Archive Cleanup (20 pts)
    archive_removed_count = result.get("removed_from_archive_count", 0)
    cleanup_pts = (archive_removed_count / total_targets) * 20
    score += cleanup_pts
    if archive_removed_count == total_targets:
        feedback.append("Archived records cleaned up correctly.")
    else:
        feedback.append(f"Failed to remove {total_targets - archive_removed_count} records from archive.")

    # 4. Collateral Damage (10 pts)
    # Pass if collateral_damage is false AND we actually removed something (to avoid "deleted everything" being a pass on cleanup but fail here)
    collateral = result.get("collateral_damage", False)
    remaining = result.get("archive_remaining_count", 0)
    expected_remaining = result.get("expected_archive_remaining", 7)
    
    if not collateral and remaining == expected_remaining:
        score += 10
        feedback.append("Archive integrity maintained (no extra deletions).")
    else:
        feedback.append("Archive integrity check failed (wrong number of remaining records).")

    passed = (score >= 70) and (index_count == total_targets)
    
    return {
        "passed": passed,
        "score": int(score),
        "feedback": " ".join(feedback)
    }