#!/usr/bin/env python3
"""
Verifier for create_timeline_state_machine task.
Executes robust static analysis on the created scripts and verifies visual trajectories.
"""

import json
import tempfile
import os
import re
import logging

try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
except ImportError:
    pass

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_timeline_state_machine(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Safely retrieve exported result JSON from the Windows environment
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\temp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1. File Structure (10 points)
    if result.get("target_dir_exists") and result.get("py_exists") and result.get("talon_exists"):
        score += 10
        feedback.append("✅ File structure properly created.")
    else:
        feedback.append("❌ Missing required directories or files.")

    py_content = result.get("py_content", "")
    talon_content = result.get("talon_content", "")

    # 2. Command Mapping (15 points)
    cmds_found = 0
    if re.search(r"timeline date\s*<.*?>\s*:\s*.*timeline_set_date", talon_content, re.IGNORECASE): cmds_found += 4
    if re.search(r"timeline actor\s*<.*?>\s*:\s*.*timeline_set_actor", talon_content, re.IGNORECASE): cmds_found += 4
    if re.search(r"timeline event\s*<.*?>\s*:\s*.*timeline_set_event", talon_content, re.IGNORECASE): cmds_found += 4
    if re.search(r"timeline commit\s*:\s*.*timeline_commit", talon_content, re.IGNORECASE): cmds_found += 3

    score += cmds_found
    feedback.append(f"Command mapping score: {cmds_found}/15")

    # 3. State Management (15 points)
    state_score = 0
    if "Module(" in py_content and ("action_class" in py_content or "@mod.action_class" in py_content):
        state_score += 5
    # Look for global usage or class attributes managing state
    if re.search(r"(global|self\.)\s*[a-zA-Z_]*(date|actor|event)", py_content, re.IGNORECASE):
        state_score += 6
    # Check if empty states are handled before commit
    if "None" in py_content or '""' in py_content or "''" in py_content:
        state_score += 4

    score += state_score
    feedback.append(f"State management score: {state_score}/15")

    # 4. Data Persistence (20 points)
    persist_score = 0
    if "master_timeline.csv" in py_content:
        persist_score += 5
    # Detect file opening/writing methods handling CSV
    if ("open(" in py_content) and ("csv.writer" in py_content or ".write(" in py_content or ".append(" in py_content):
        persist_score += 15
        
    score += persist_score
    feedback.append(f"Data persistence score: {persist_score}/20")

    # 5. Auto-Sorting (20 points)
    sort_score = 0
    if "csv.reader" in py_content or "readlines(" in py_content:
        sort_score += 5
    # Ensure they attempt to sort the data payload
    if ".sort(" in py_content or "sorted(" in py_content:
        sort_score += 15
        
    score += sort_score
    feedback.append(f"Auto-sorting score: {sort_score}/20")

    # 6. Notification API (10 points)
    notify_score = 0
    if "app.notify(" in py_content:
        notify_score = 10
        
    score += notify_score
    feedback.append(f"Notification API score: {notify_score}/10")

    # 7. VLM Verification - Trajectory checks (10 points)
    vlm_score = 0
    try:
        query_vlm = env_info.get('query_vlm')
        if query_vlm:
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            if frames and final:
                prompt = "Did the agent actively write or edit Python and Talon configuration code in a text editor like Notepad or VS Code? Respond strictly with 'YES' or 'NO'."
                vlm_result = query_vlm(images=frames + [final], prompt=prompt)
                if vlm_result and "YES" in vlm_result.get("text", "").upper():
                    vlm_score = 10
                    feedback.append("✅ VLM: Editor trajectory activity confirmed.")
                else:
                    feedback.append("❌ VLM: Could not confirm editor activity.")
            else:
                feedback.append("⚠️ VLM skipped: Trajectory frames missing.")
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        feedback.append(f"⚠️ VLM error occurred.")
        vlm_score = 0 # Fallback 0 for VLM if missing context

    score += vlm_score

    # 8. Anti-gaming check
    if not (result.get("py_created_during_task") and result.get("talon_created_during_task")):
        feedback.append("❌ WARNING: The required files were NOT modified during the task window (Do Nothing attempt). Applying strict penalty.")
        score = int(score * 0.2)

    # Calculate pass (80 points required including data persistence + auto-sorting minimums)
    key_criteria_met = persist_score >= 15 and sort_score >= 15 and result.get("py_created_during_task")
    passed = (score >= 80) and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": result
    }