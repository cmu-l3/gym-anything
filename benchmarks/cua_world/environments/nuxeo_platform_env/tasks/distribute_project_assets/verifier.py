#!/usr/bin/env python3
import json
import os
import tempfile
from datetime import datetime

def verify_distribute_project_assets(traj, env_info, task_info):
    """
    Verify the Nuxeo asset distribution task.
    Requires:
    1. 'Project Closure Report' moved to Archives (same UUID, absent from source).
    2. 'Reusable Assets' copied to Library (new UUID, present in source).
    """
    
    # 1. Setup Result Loading
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    initial = result.get('initial', {})
    final = result.get('final', {})
    
    score = 0
    feedback = []

    # --- Criteria 1: Move Report (50 pts) ---
    # Sub-check A: Exists in Archive (20 pts)
    report_in_archive_uid = final.get('report_in_archive_uid', '')
    if report_in_archive_uid:
        score += 20
        feedback.append("Report found in Archives.")
    else:
        feedback.append("Report NOT found in Archives.")

    # Sub-check B: Not in Source (20 pts)
    report_in_source_exists = final.get('report_in_source_exists', True)
    if not report_in_source_exists:
        score += 20
        feedback.append("Report successfully removed from Project Omega.")
    else:
        feedback.append("Report still exists in Project Omega (failed to move).")

    # Sub-check C: UUID Preserved (Move vs Copy check) (10 pts)
    # If it was moved, the UUID in Archive must equal the Initial UUID
    orig_report_uid = initial.get('report_uid', 'unknown')
    if report_in_archive_uid and report_in_archive_uid == orig_report_uid:
        score += 10
        feedback.append("Report UUID preserved (correctly Moved).")
    elif report_in_archive_uid:
        feedback.append("Report UUID changed (Copied instead of Moved? -10 pts).")

    # --- Criteria 2: Copy Assets (50 pts) ---
    # Sub-check A: Exists in Library (20 pts)
    assets_in_library_uid = final.get('assets_in_library_uid', '')
    if assets_in_library_uid:
        score += 20
        feedback.append("Assets folder found in Library.")
    else:
        feedback.append("Assets folder NOT found in Library.")

    # Sub-check B: Still in Source (10 pts)
    assets_in_source_uid = final.get('assets_in_source_uid', '')
    if assets_in_source_uid:
        score += 10
        feedback.append("Assets folder preserved in Project Omega.")
    else:
        feedback.append("Assets folder missing from Project Omega (Moved instead of Copied? -10 pts).")

    # Sub-check C: UUID Changed (Copy vs Move/Symlink check) (20 pts)
    # If copied, the UUID in Library MUST BE DIFFERENT from Initial UUID
    orig_assets_uid = initial.get('assets_uid', 'unknown')
    
    if assets_in_library_uid:
        if assets_in_library_uid != orig_assets_uid:
            score += 20
            feedback.append("Assets folder UUID is new (correctly Copied).")
        else:
            feedback.append("Assets folder UUID matches original (Moved or Symlinked instead of Copied? -20 pts).")

    # --- Final Result ---
    # Threshold: Need 80 points to pass (allows for minor errors but requires main actions)
    # Essential actions: Report in Archive (20), Not in Source (20), Assets in Library (20), Assets in Source (10). 
    # Total 70 base points for just getting files to right places. 
    # Need at least one "correct method" (Move vs Copy) verification to pass 80.
    
    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }