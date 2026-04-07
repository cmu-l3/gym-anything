#!/usr/bin/env python3
"""
Verifier for download_offline_map_monaco task.

VERIFICATION STRATEGY:
1. Programmatic: Check if Monaco map file exists and was created during the task.
2. Visual (VLM): Verify trajectory shows menu navigation, scrolling to "Monaco", and download action.

Anti-Gaming:
- Timestamps ensure map wasn't already there.
- VLM ensures the agent actually used the UI and didn't just curl a file (though unlikely on Android without root).
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_download_offline_map_monaco(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy function not available"}

    # 1. Retrieve Programmatic Evidence
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Copy result JSON from Android device
        copy_from_env("/sdcard/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to retrieve/parse result: {e}")
        return {"passed": False, "score": 0, "feedback": f"Could not retrieve task result from device: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Analyze Programmatic Evidence
    score = 0
    feedback_parts = []
    
    monaco_found = result.get("monaco_map_found", False)
    new_file = result.get("new_file_detected", False)
    size_increased = result.get("total_maps_size_increased", False)
    app_running = result.get("app_was_running", False)
    
    # Scoring - Programmatic (Max 50)
    if app_running:
        score += 10
        feedback_parts.append("App was running.")
    
    if size_increased:
        score += 10
        feedback_parts.append("Map storage size increased.")
        
    if monaco_found and new_file:
        score += 30
        feedback_parts.append("Monaco map file successfully detected (newly created).")
    elif monaco_found:
        score += 10
        feedback_parts.append("Monaco map file found, but timestamp check failed (might be old).")
    else:
        feedback_parts.append("Monaco map file NOT found.")

    # 3. Analyze Visual Evidence (VLM) (Max 50)
    # We look for the workflow: Menu -> Offline Maps -> Scroll/Find Monaco -> Download
    frames = sample_trajectory_frames(traj, n=5)
    final_screenshot = get_final_screenshot(traj)
    
    vlm_prompt = """
    You are verifying an Android navigation task.
    Goal: Download the offline map for "Monaco".
    
    Review the screenshots for these specific steps:
    1. Did the agent open the 'Offline Maps' or 'Manage Maps' menu?
    2. Did the agent browse/scroll a list of countries?
    3. Is "Monaco" visible in any frame?
    4. Did the agent tap a download icon/button?
    5. Does the final screen show Monaco in the list of "Downloaded" maps (or a progress bar completed)?
    
    Output JSON:
    {
        "menu_opened": boolean,
        "scrolled_list": boolean,
        "monaco_seen": boolean,
        "download_action": boolean,
        "final_success": boolean,
        "explanation": "string"
    }
    """
    
    vlm_response = query_vlm(
        images=frames + [final_screenshot] if final_screenshot else frames,
        prompt=vlm_prompt
    )
    
    vlm_score = 0
    if vlm_response.get("success"):
        analysis = vlm_response.get("parsed", {})
        if analysis.get("menu_opened"): vlm_score += 10
        if analysis.get("scrolled_list"): vlm_score += 10
        if analysis.get("monaco_seen"): vlm_score += 10
        if analysis.get("download_action"): vlm_score += 10
        if analysis.get("final_success"): vlm_score += 10
        feedback_parts.append(f"VLM Analysis: {analysis.get('explanation', 'No explanation')}")
    else:
        feedback_parts.append("VLM verification failed to run.")

    score += vlm_score

    # 4. Final Verdict
    passed = (score >= 60) and monaco_found and new_file
    
    if not monaco_found:
        feedback_parts.insert(0, "FAILED: Monaco map file not found on device.")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }