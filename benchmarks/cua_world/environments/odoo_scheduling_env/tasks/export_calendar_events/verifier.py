#!/usr/bin/env python3
"""
Verifier for export_calendar_events task.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_export_calendar_events(traj, env_info, task_info):
    """
    Verifies that the agent exported calendar events to a CSV file.
    
    Scoring Criteria:
    1. File Existence & Location (15 pts)
    2. CSV Validity (10 pts)
    3. Required Columns (Subject, Start, End) (15 pts)
    4. Data Quantity (Rows >= 10) (15 pts)
    5. Data Integrity (Matches Odoo DB) (15 pts)
    6. Anti-gaming (Time check) (10 pts)
    7. VLM Workflow Verification (20 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    max_score = 100
    feedback_parts = []
    
    # 1. Retrieve analysis result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # --- Programmatic Checks (80 pts total) ---

    # 1. File Existence & Location (15 pts)
    if result.get("file_found"):
        if result.get("location_status") == "correct":
            score += 15
            feedback_parts.append("File found at correct path.")
        else:
            score += 8 # Partial credit for finding it in Downloads
            feedback_parts.append("File found, but in fallback location (e.g. Downloads).")
    else:
        feedback_parts.append("No export file found.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. CSV Validity (10 pts)
    if result.get("is_valid_csv"):
        score += 10
    else:
        feedback_parts.append("File is not a valid CSV.")

    # 3. Required Columns (15 pts)
    cols = []
    if result.get("has_subject"): cols.append("Subject")
    if result.get("has_start"): cols.append("Start")
    if result.get("has_stop"): cols.append("End")
    
    if len(cols) == 3:
        score += 15
        feedback_parts.append("All required columns present.")
    elif len(cols) > 0:
        score += 5 * len(cols)
        feedback_parts.append(f"Missing columns. Found: {', '.join(cols)}.")
    else:
        feedback_parts.append("No required columns found.")

    # 4. Data Quantity (15 pts)
    row_count = result.get("row_count", 0)
    if row_count >= 10:
        score += 15
        feedback_parts.append(f"Row count good ({row_count}).")
    elif row_count > 0:
        score += 5
        feedback_parts.append(f"Row count low ({row_count}).")
    else:
        feedback_parts.append("File is empty.")

    # 5. Data Integrity (15 pts)
    matches = result.get("db_match_count", 0)
    if matches >= 5:
        score += 15
        feedback_parts.append(f"Content matches Odoo database ({matches} events).")
    elif matches >= 1:
        score += 5
        feedback_parts.append("Some content matches Odoo database.")
    else:
        feedback_parts.append("Content does not match known Odoo events.")

    # 6. Anti-gaming (10 pts)
    if result.get("file_created_after_start"):
        score += 10
    else:
        feedback_parts.append("File timestamp predates task start.")

    # --- VLM Verification (20 pts) ---
    # We check if the agent actually used the List View and Export Dialog
    
    frames = sample_trajectory_frames(traj, n=5)
    final_frame = get_final_screenshot(traj)
    all_frames = frames + [final_frame] if final_frame else frames

    prompt = """
    Analyze these screenshots of an Odoo agent performing a task.
    The task is to export calendar events to CSV.
    
    Look for these specific visual milestones:
    1. LIST VIEW: The Odoo Calendar switched to a list/table view (rows of text instead of calendar grid).
    2. EXPORT DIALOG: A popup window titled "Export Data" with field selection options (Available fields vs Fields to export).
    
    Return JSON:
    {
        "seen_list_view": boolean,
        "seen_export_dialog": boolean,
        "confidence": "high/medium/low"
    }
    """
    
    vlm_score = 0
    try:
        vlm_resp = query_vlm(images=all_frames, prompt=prompt)
        if vlm_resp.get("success"):
            parsed = vlm_resp.get("parsed", {})
            if parsed.get("seen_list_view"):
                vlm_score += 10
            if parsed.get("seen_export_dialog"):
                vlm_score += 10
            feedback_parts.append(f"VLM: List={parsed.get('seen_list_view')}, Dialog={parsed.get('seen_export_dialog')}")
        else:
            # Fallback if VLM fails but file is perfect
            if score >= 70:
                vlm_score = 20
                feedback_parts.append("VLM failed, assuming success based on perfect file.")
    except Exception as e:
        logger.warning(f"VLM exception: {e}")
    
    score += vlm_score

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }