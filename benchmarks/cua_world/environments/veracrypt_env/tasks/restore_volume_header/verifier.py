#!/usr/bin/env python3
"""
Verifier for restore_volume_header task.

Metrics:
1. Volume header restored (can be mounted).
2. Volume is currently mounted at correct location.
3. Data inside volume is accessible.
4. Report file created with correct verification code.
5. VLM verification of GUI workflow.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_restore_volume_header(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON
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

    score = 0
    feedback_parts = []
    
    # 1. Header Restored (30 pts)
    # The script checks this by trying to mount it or checking if it is mounted
    if result.get('header_restored', False):
        score += 30
        feedback_parts.append("Volume header restored successfully.")
    else:
        feedback_parts.append("Volume header NOT restored (volume unmountable).")

    # 2. Volume Mounted (10 pts)
    if result.get('volume_mounted', False):
        score += 10
        feedback_parts.append("Volume is mounted.")
        
        # Check correct mount point (5 pts)
        expected_mp = task_info.get('metadata', {}).get('mount_point', '/home/ga/MountPoints/slot1')
        actual_mp = result.get('mount_point', '')
        if actual_mp == expected_mp:
            score += 5
            feedback_parts.append("Volume mounted at correct path.")
        else:
            feedback_parts.append(f"Volume mounted at {actual_mp} (expected {expected_mp}).")
    else:
        feedback_parts.append("Volume is NOT currently mounted.")

    # 3. Data Integrity (20 pts)
    if result.get('files_match_expected', False) and result.get('has_recovery_file', False):
        score += 20
        feedback_parts.append("Data files verified intact.")
    elif result.get('header_restored', False):
        feedback_parts.append("Volume empty or missing files.")

    # 4. Report File (25 pts)
    if result.get('report_exists', False):
        if result.get('report_created_during_task', False):
            if result.get('report_code_match', False):
                score += 25
                feedback_parts.append("Report file contains correct recovery code.")
            else:
                score += 10
                feedback_parts.append("Report file exists but code is incorrect.")
        else:
            feedback_parts.append("Report file matches old timestamp (pre-existing?).")
    else:
        feedback_parts.append("Report file not created.")

    # 5. VLM Verification (10 pts)
    # Check if we see the 'Restore Volume Header' dialog or success message
    vlm_score = 0
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final_shot = get_final_screenshot(traj)
        if final_shot:
            frames.append(final_shot)
            
        prompt = """
        Review these screenshots of a VeraCrypt recovery task.
        Look for:
        1. The 'Restore Volume Header' dialog or menu option being used.
        2. A file selection dialog choosing 'header_backup_critical.dat'.
        3. A success message indicating headers were restored/verified.
        4. The main VeraCrypt window showing a mounted volume in Slot 1.
        
        Reply JSON: {"workflow_visible": bool, "mount_visible": bool}
        """
        
        try:
            vlm_resp = query_vlm(images=frames, prompt=prompt)
            if vlm_resp.get("success"):
                parsed = vlm_resp.get("parsed", {})
                if parsed.get("workflow_visible", False) or parsed.get("mount_visible", False):
                    vlm_score = 10
                    feedback_parts.append("VLM verified recovery workflow.")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")

    score += vlm_score

    # Final check
    passed = score >= 60 and result.get('header_restored', False)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }