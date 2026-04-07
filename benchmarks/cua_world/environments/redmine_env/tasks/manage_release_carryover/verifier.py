#!/usr/bin/env python3
import json
import os
import tempfile

def verify_manage_release_carryover(traj, env_info, task_info):
    """
    Verifies the manage_release_carryover task.
    
    Criteria:
    1. Version 'v2.4-stable' must be Closed or Locked.
    2. Issues that were initially Open must have been moved to 'v2.5-beta'.
    3. Issues that were initially Closed must remain in 'v2.4-stable'.
    """
    
    # 1. Retrieve result file
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

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

    # Check for script errors
    if 'error' in result:
        return {"passed": False, "score": 0, "feedback": f"Verification script error: {result['error']}"}

    # Extract Data
    setup = result.get('setup_data', {})
    final = result.get('final_state', {})
    
    source_version_id = setup.get('source_version_id')
    target_version_id = setup.get('target_version_id')
    
    score = 0
    feedback = []

    # CRITERION 1: Version Status (40 pts)
    # Status 'closed' or 'locked' are acceptable for preventing changes
    v_status = final.get('source_version_status', '').lower()
    if v_status in ['closed', 'locked']:
        score += 40
        feedback.append(f"Version status correctly set to '{v_status}'.")
    else:
        feedback.append(f"Version status is '{v_status}' (expected 'closed' or 'locked').")

    # CRITERION 2: Moved Issues (30 pts)
    # Check if 'ids_to_move' are now in target_version_id
    moved_issues = final.get('moved_issues', [])
    correctly_moved_count = 0
    total_to_move = len(moved_issues)
    
    for issue in moved_issues:
        # We accept if they are in the target version
        if issue.get('fixed_version_id') == target_version_id:
            correctly_moved_count += 1
        # Or if they are NOT in the source version (partial credit logic could apply, but strict here)
        
    if total_to_move > 0:
        move_score = (correctly_moved_count / total_to_move) * 30
        score += move_score
        if correctly_moved_count == total_to_move:
            feedback.append("All unfinished issues moved correctly.")
        else:
            feedback.append(f"{correctly_moved_count}/{total_to_move} unfinished issues moved.")

    # CRITERION 3: History Preserved (30 pts)
    # Check if 'ids_to_keep' are STILL in source_version_id
    kept_issues = final.get('kept_issues', [])
    correctly_kept_count = 0
    total_to_keep = len(kept_issues)
    
    for issue in kept_issues:
        if issue.get('fixed_version_id') == source_version_id:
            correctly_kept_count += 1
            
    if total_to_keep > 0:
        keep_score = (correctly_kept_count / total_to_keep) * 30
        score += keep_score
        if correctly_kept_count == total_to_keep:
            feedback.append("All completed issues preserved in original version.")
        else:
            feedback.append(f"{correctly_kept_count}/{total_to_keep} completed issues preserved.")

    # Final Check
    passed = (score >= 99) # Strict pass requirement for data integrity
    
    return {
        "passed": passed,
        "score": int(score),
        "feedback": " ".join(feedback)
    }