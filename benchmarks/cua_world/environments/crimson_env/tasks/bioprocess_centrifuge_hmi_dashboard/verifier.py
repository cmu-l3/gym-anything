#!/usr/bin/env python3
"""
Verifier for bioprocess_centrifuge_hmi_dashboard.

Uses HYBRID VERIFICATION:
1. Programmatic Checks: Validates file existence, file size, and creation timestamps.
2. VLM Checks: Inspects trajectory frames and the final screenshot to confirm HMI 
   layout matches the ISA-101 design prompt specifications.
"""

import os
import json
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def build_vlm_prompt():
    return """Examine these screenshots of the Red Lion Crimson 3.0 interface.
Evaluate the final HMI display (Page 1) against the following ISA-101 design requirements.

Please check for:
1. crimson_ui_active: Is the Crimson 3.0 User Interface editing screen clearly visible?
2. dark_background: Is the main display page background set to a Dark Gray or very dark color?
3. title_text: Is there a text primitive reading 'Centrifuge 101 Overview' (or very similar)?
4. data_boxes: Are there at least three numeric data boxes (representing tags like Bowl_Speed, Feed_Rate, Diff_Pressure) visible?
5. gauge_present: Is there a circular gauge or bar graph indicator visible?
6. gauge_label: Is there a text label saying 'Vibration' or 'Vibration Monitor' next to the gauge?
7. button_present: Is there a control button visible?
8. button_label: Is there a text label saying 'Feed Pump' or 'Pump Control' on or next to the button?

Respond strictly in JSON format:
{
    "crimson_ui_active": true/false,
    "dark_background": true/false,
    "title_text": true/false,
    "data_boxes_count": <integer count of data boxes visible>,
    "gauge_present": true/false,
    "gauge_label": true/false,
    "button_present": true/false,
    "button_label": true/false,
    "observations": "<brief summary of what you see>"
}"""


def verify_centrifuge_hmi(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    query_vlm = env_info.get("query_vlm")
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get("metadata", {})
    min_size = metadata.get("min_file_size_bytes", 1000)
    
    score = 0
    feedback_parts = []
    
    # --- 1. Programmatic Verification ---
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp_path = tmp.name
        tmp.close()
        try:
            # Note: Windows container uses C:/tmp/... or standard /tmp/... mapping.
            copy_from_env("C:/tmp/task_result.json", tmp_path)
            with open(tmp_path, "r", encoding="utf-8") as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result JSON not found - export failed."}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    project_exists = result.get("project_exists", False)
    file_created = result.get("file_created_during_task", False)
    file_size = result.get("file_size_bytes", 0)
    app_running = result.get("app_was_running", False)

    if project_exists and file_created:
        score += 20
        feedback_parts.append("File 'centrifuge_main.c3' correctly created.")
    elif project_exists:
        feedback_parts.append("File exists but was NOT modified during the task (possible gaming).")
    else:
        feedback_parts.append("Project file not saved.")

    if file_size > min_size:
        score += 10
        feedback_parts.append(f"File size valid ({file_size} bytes).")
    else:
        feedback_parts.append(f"File size too small ({file_size} bytes).")

    # Early exit if the foundational programmatic conditions fail
    if not (project_exists and file_created):
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    # --- 2. VLM Verification ---
    if not query_vlm:
        feedback_parts.append("VLM not available for visual checks. Awarding partial pass.")
        # If VLM isn't hooked up, pass conditionally based on file constraints
        return {"passed": score >= 30, "score": score, "feedback": " | ".join(feedback_parts)}

    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        frames = sample_trajectory_frames(traj, n=3)
        final_frame = get_final_screenshot(traj)
        images = frames + [final_frame] if final_frame else frames
        
        if not images:
            feedback_parts.append("No screenshots available for VLM.")
            return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

        vlm_resp = query_vlm(prompt=build_vlm_prompt(), images=images)
        parsed = vlm_resp.get("parsed", {})
        
        # Scoring VLM Criteria (70 points total)
        if parsed.get("crimson_ui_active", False):
            score += 10
            
        if parsed.get("dark_background", False):
            score += 10
            feedback_parts.append("Dark background verified.")
            
        if parsed.get("title_text", False):
            score += 10
            feedback_parts.append("Title text verified.")
            
        boxes_count = parsed.get("data_boxes_count", 0)
        if isinstance(boxes_count, int) and boxes_count >= 3:
            score += 15
            feedback_parts.append("3+ Data Boxes verified.")
        elif isinstance(boxes_count, int) and boxes_count > 0:
            score += 5
            
        if parsed.get("gauge_present", False) and parsed.get("gauge_label", False):
            score += 15
            feedback_parts.append("Labeled Gauge verified.")
            
        if parsed.get("button_present", False) and parsed.get("button_label", False):
            score += 10
            feedback_parts.append("Labeled Button verified.")
            
    except ImportError:
        feedback_parts.append("Could not import VLM tools.")
    except Exception as e:
        feedback_parts.append(f"VLM evaluation error: {e}")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }