#!/usr/bin/env python3
"""
Verifier for create_export_science_exams task.

Verification Strategy:
1. DB Check: Checks if the 3 named exam configurations exist in SEB Server's MariaDB.
2. DB Check: Checks if the specific Start URLs were properly assigned to settings.
3. FS Check: Verifies the existence of the expected .seb files in the required directory.
4. Anti-gaming: Verifies files were created after the task started and are non-empty.
5. VLM Check (Trajectory): Ensures the agent traversed the Exam Config UI.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_export_science_exams(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_configs = metadata.get('expected_configs', [])

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Trackers
    configs_found = 0
    urls_correct = 0
    files_found = 0
    files_valid = 0

    # 1 & 2. Database Evaluation
    db_configs = result.get('configs', {})
    for conf_name in expected_configs:
        data = db_configs.get(conf_name, {})
        if data.get('exists', False):
            configs_found += 1
            if data.get('url_correct', False):
                urls_correct += 1

    # Scoring configurations (30 pts max)
    config_score = configs_found * 10
    score += config_score
    feedback_parts.append(f"DB Configs: {configs_found}/{len(expected_configs)} created")

    # Scoring settings/urls (30 pts max)
    url_score = urls_correct * 10
    score += url_score
    feedback_parts.append(f"DB URLs: {urls_correct}/{len(expected_configs)} correctly set")

    # 3 & 4. File System Evaluation
    fs_files = result.get('files', {})
    dir_exists = result.get('backup_dir_exists', False)
    
    if not dir_exists:
        feedback_parts.append("Backup directory ~/Documents/ExamBackups NOT found")
    else:
        for conf_name in expected_configs:
            file_data = fs_files.get(conf_name, {})
            if file_data.get('exists', False):
                files_found += 1
                # Must be recent (> start_time) and have content (> 100 bytes for a .seb XML structure)
                if file_data.get('recent', False) and file_data.get('size_bytes', 0) > 100:
                    files_valid += 1

    # Scoring file downloads (20 pts max)
    file_score = int((files_found / len(expected_configs)) * 20)
    score += file_score
    feedback_parts.append(f"Files Exported: {files_found}/{len(expected_configs)} found")

    # Scoring file validity & naming (20 pts max)
    valid_score = int((files_valid / len(expected_configs)) * 20)
    score += valid_score
    if files_valid < files_found:
        feedback_parts.append(f"Valid/Recent Files: {files_valid}/{files_found} (Some files were old or empty)")
    else:
        feedback_parts.append(f"Valid/Recent Files: {files_valid}/{len(expected_configs)}")

    # 5. VLM Trajectory Verification (Optional additional check for anti-gaming)
    vlm_feedback = ""
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm, get_final_screenshot
        frames = sample_trajectory_frames(traj, n=3)
        final = get_final_screenshot(traj)
        
        prompt = (
            "You are evaluating a web automation agent working on Safe Exam Browser Server. "
            "Look at these screenshots. Do you see the SEB Server 'Exam Configuration' interface being used? "
            "Reply with exactly 'YES' if the agent is visibly interacting with configurations, or 'NO' if not."
        )
        vlm_result = query_vlm(images=frames + [final], prompt=prompt)
        if "YES" in vlm_result.get('answer', '').upper():
            vlm_feedback = "VLM confirmed UI interaction."
        else:
            vlm_feedback = "VLM could not confirm UI interaction."
    except Exception as e:
        vlm_feedback = "VLM check skipped."

    feedback_parts.append(vlm_feedback)

    # Final logic
    key_criteria_met = (configs_found >= 2 and files_valid >= 2)
    passed = (score >= 70) and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "configs_created": configs_found,
            "urls_correct": urls_correct,
            "files_downloaded": files_found,
            "files_valid": files_valid
        }
    }