#!/usr/bin/env python3
import json
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_audit_tiu_definitions(traj, env_info, task_info):
    """
    Verifies the audit_tiu_definitions task.
    1. Checks if report file exists and was created during task.
    2. Validates report content against VistA database truth (passed via JSON).
    3. Uses VLM to verify navigation to ^TIU global.
    """
    # 1. Setup and Copy Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy failed"}

    score = 0
    feedback = []
    
    # Load result JSON
    try:
        import tempfile
        with tempfile.NamedTemporaryFile(suffix=".json") as f:
            copy_from_env("/tmp/task_result.json", f.name)
            f.seek(0)
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result data: {str(e)}"}

    # Load User Report
    user_lines = []
    try:
        if result_data.get("file_exists"):
            with tempfile.NamedTemporaryFile(suffix=".txt") as f:
                copy_from_env(result_data["report_path_in_container"], f.name)
                f.seek(0)
                content = f.read().decode('utf-8', errors='ignore')
                user_lines = [line.strip() for line in content.splitlines() if line.strip()]
    except Exception as e:
        logger.warning(f"Could not read user report: {e}")

    # 2. Scoring - File Criteria (Max 20)
    if result_data.get("file_exists") and result_data.get("file_created_during_task"):
        score += 20
        feedback.append("Report file created successfully.")
    elif result_data.get("file_exists"):
        score += 10
        feedback.append("Report file exists but timestamp is uncertain.")
    else:
        feedback.append("Report file not found.")

    # 3. Scoring - Content Verification (Max 40)
    valid_titles_map = result_data.get("valid_titles_map", {})
    valid_entries_found = 0
    
    for line in user_lines:
        # Expected format: IEN | NAME | TYPE
        parts = [p.strip() for p in line.split('|')]
        if len(parts) >= 2:
            ien = parts[0]
            name = parts[1]
            # type = parts[2] if len(parts) > 2 else "" # Optional check
            
            # Check against Ground Truth
            if ien in valid_titles_map:
                # Name matching (loose to allow case diffs or punctuation)
                db_name = valid_titles_map[ien]
                if name.upper() in db_name.upper() or db_name.upper() in name.upper():
                    valid_entries_found += 1
    
    # Points per valid entry (up to 5 entries)
    entry_score = min(valid_entries_found * 8, 40)
    score += entry_score
    feedback.append(f"Found {valid_entries_found} valid Title entries in report.")

    # 4. Scoring - VLM Verification (Max 30)
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    images = frames + [final_screen] if final_screen else frames
    
    vlm_prompt = (
        "You are verifying a VistA EHR task. The user should be navigating the "
        "Text Integration Utilities global ^TIU(8925.1) in YDBGui (a web interface).\n"
        "Look at the sequence of images.\n"
        "1. Is the YDBGui web interface visible (blue header, Global Viewer)?\n"
        "2. Can you see the global name '^TIU' or '^TIU(8925.1)'?\n"
        "3. Are there list entries visible that look like document titles (e.g., 'ADDENDUM', 'NOTE')?\n"
        "Return a JSON object: {'navigated_tiu': boolean, 'confidence': float}"
    )

    vlm_result = query_vlm(images=images, prompt=vlm_prompt)
    
    vlm_passed = False
    if vlm_result and isinstance(vlm_result, dict):
        parsed = vlm_result.get('parsed', {})
        if parsed.get('navigated_tiu'):
            vlm_passed = True
            score += 30
            feedback.append("Visual verification passed: ^TIU global accessed.")
        else:
            feedback.append("Visual verification failed: Could not confirm ^TIU navigation.")
    else:
        # Fallback if VLM fails or returns string
        if "TIU" in str(vlm_result):
            score += 15
            feedback.append("Visual verification partial.")

    # 5. Scoring - App Running (Max 10)
    if result_data.get("app_running"):
        score += 10
    
    # Final Pass/Fail
    passed = (score >= 60) and (valid_entries_found >= 3)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }