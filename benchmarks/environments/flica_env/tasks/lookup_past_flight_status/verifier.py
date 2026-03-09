#!/usr/bin/env python3
"""
Verifier for lookup_past_flight_status task.

Criteria:
1. Agent must capture a screenshot of the result (File Check).
2. The UI must show the correct flight number (AA100) (UI Dump / VLM).
3. The UI must show a date corresponding to 'Yesterday' (UI Dump / VLM).
4. The trajectory must show interaction with a date picker (VLM).
"""

import json
import os
import tempfile
import logging
from datetime import datetime, timedelta
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_past_flight_lookup(traj, env_info, task_info):
    """
    Verifies that the agent looked up flight AA100 for yesterday's date.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env or not query_vlm:
        return {"passed": False, "score": 0, "feedback": "System error: Missing copy_from_env or query_vlm"}

    score = 0
    feedback_parts = []
    max_score = 100

    # ------------------------------------------------------------------
    # 1. Retrieve Artifacts
    # ------------------------------------------------------------------
    temp_dir = tempfile.mkdtemp()
    try:
        # Get JSON result
        local_json_path = os.path.join(temp_dir, "task_result.json")
        try:
            copy_from_env("/sdcard/task_result.json", local_json_path)
            with open(local_json_path, 'r') as f:
                result_data = json.load(f)
        except Exception:
            result_data = {}
            feedback_parts.append("Failed to load task result JSON")

        # Get UI Dump
        local_dump_path = os.path.join(temp_dir, "ui_dump.xml")
        ui_dump_content = ""
        try:
            copy_from_env("/sdcard/ui_dump.xml", local_dump_path)
            with open(local_dump_path, 'r', encoding='utf-8', errors='ignore') as f:
                ui_dump_content = f.read()
        except Exception:
            pass # UI dump might fail if app crashed

        # Get device date from setup
        local_date_path = os.path.join(temp_dir, "task_initial_date.txt")
        device_date_str = ""
        try:
            copy_from_env("/sdcard/task_initial_date.txt", local_date_path)
            with open(local_date_path, 'r') as f:
                device_date_str = f.read().strip()
        except Exception:
            device_date_str = datetime.now().strftime("%Y-%m-%d") # Fallback to host date

    finally:
        import shutil
        shutil.rmtree(temp_dir, ignore_errors=True)

    # ------------------------------------------------------------------
    # 2. Evaluate File Existence (20 pts)
    # ------------------------------------------------------------------
    if result_data.get("output_exists") and result_data.get("file_created_during_task"):
        score += 20
        feedback_parts.append("Screenshot saved successfully (20/20)")
    else:
        feedback_parts.append("Screenshot NOT saved or not created during task (0/20)")

    # ------------------------------------------------------------------
    # 3. Calculate "Yesterday"
    # ------------------------------------------------------------------
    try:
        today = datetime.strptime(device_date_str, "%Y-%m-%d")
        yesterday = today - timedelta(days=1)
        # Formats likely to appear in UI
        yesterday_formats = [
            yesterday.strftime("%b %-d"),  # Oct 24
            yesterday.strftime("%b %d"),   # Oct 24
            yesterday.strftime("%m/%d"),   # 10/24
            yesterday.strftime("%A"),      # Thursday (if app shows day name)
            "Yesterday"
        ]
        logger.info(f"Looking for date formats: {yesterday_formats}")
    except Exception as e:
        logger.error(f"Date calculation error: {e}")
        yesterday_formats = ["Yesterday"]

    # ------------------------------------------------------------------
    # 4. Text-based Verification (UI Dump) (30 pts)
    # ------------------------------------------------------------------
    ui_score = 0
    
    # Check for Flight Number
    if "AA100" in ui_dump_content or "AA 100" in ui_dump_content:
        ui_score += 15
        feedback_parts.append("Flight AA100 found in UI (15/15)")
    else:
        feedback_parts.append("Flight AA100 NOT found in UI (0/15)")

    # Check for Date
    date_found = False
    for fmt in yesterday_formats:
        if fmt in ui_dump_content:
            date_found = True
            break
            
    if date_found:
        ui_score += 15
        feedback_parts.append("Correct past date found in UI (15/15)")
    else:
        # Don't penalize yet, VLM might catch it if UI dump missed text
        feedback_parts.append("Date text not explicitly found in dump (checking VLM...)")
    
    score += ui_score

    # ------------------------------------------------------------------
    # 5. VLM Verification (Trajectory & Final State) (50 pts)
    # ------------------------------------------------------------------
    # We need to verify:
    # A) Did they interact with a date picker? (Process)
    # B) Does the final result show the right info? (Outcome)
    
    frames = sample_trajectory_frames(traj, n=5)
    final_screen = get_final_screenshot(traj)
    
    if final_screen:
        all_images = frames + [final_screen]
    else:
        all_images = frames

    prompt = f"""
    You are evaluating an agent's performance on an Android flight tracking app.
    Task: Search for Flight AA100 for the date '{yesterday_formats[0]}' (Yesterday).

    Review the screenshots sequence.
    1. Did the agent navigate to a flight search or tracking screen?
    2. Did the agent interact with a DATE SELECTOR or Calendar to change the date from Today? (Crucial)
    3. In the final result, is 'AA100' visible?
    4. In the final result, is the date '{yesterday_formats[0]}' (or yesterday/previous day) visible?

    Respond in JSON:
    {{
        "search_accessed": boolean,
        "date_picker_used": boolean,
        "final_flight_correct": boolean,
        "final_date_correct": boolean,
        "reasoning": "string"
    }}
    """

    vlm_result = query_vlm(images=all_images, prompt=prompt)
    
    vlm_score = 0
    if vlm_result and vlm_result.get("success"):
        parsed = vlm_result.get("parsed", {})
        
        if parsed.get("search_accessed"):
            vlm_score += 10
        
        if parsed.get("date_picker_used"):
            vlm_score += 20  # High value on process
            feedback_parts.append("VLM confirmed date picker usage")
        else:
            feedback_parts.append("VLM did not see date picker usage")

        # If UI dump failed to find flight/date, give points if VLM sees it
        if parsed.get("final_flight_correct") and "Flight AA100 found" not in str(feedback_parts):
            score += 15 # Recover lost points
            feedback_parts.append("VLM found flight AA100")
            
        if parsed.get("final_date_correct") and "Correct past date" not in str(feedback_parts):
            score += 15 # Recover lost points
            feedback_parts.append("VLM found correct date")
        elif parsed.get("final_date_correct"):
             vlm_score += 10 # Bonus confirmation
             
        feedback_parts.append(f"VLM Reasoning: {parsed.get('reasoning')}")
    else:
        feedback_parts.append("VLM verification failed to run")

    score += vlm_score
    score = min(score, 100) # Cap at 100

    # ------------------------------------------------------------------
    # Final Result
    # ------------------------------------------------------------------
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }