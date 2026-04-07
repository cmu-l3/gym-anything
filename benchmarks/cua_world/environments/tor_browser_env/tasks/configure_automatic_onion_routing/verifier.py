#!/usr/bin/env python3
"""
Verifier for configure_automatic_onion_routing task.

Checks settings, browser bookmarks/history, and generated files to ensure
the agent successfully enabled Onion-Location automatic routing.
"""

import os
import json
import logging
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_automatic_onion_routing(traj, env_info, task_info):
    """
    Score allocation (100 total):
    - privacy.prioritizeonions.enabled = true : 25 points (GATE: REQUIRED)
    - "Auto-Routed Onions" folder exists      : 15 points
    - .onion bookmarked in folder             : 15 points
    - report file exists and is new           : 15 points
    - report contains valid v3 .onion regex   : 10 points
    - history shows .onion visit              : 10 points
    - VLM trajectory verification             : 10 points
    
    Pass threshold: >= 60 points AND gate met.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_result.close()
    
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read result JSON: {e}")
        return {"passed": False, "score": 0, "feedback": f"Failed to read export JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # 1. GATE: Settings configured
    prioritize_enabled = result.get('prioritizeonions_enabled', False)
    if prioritize_enabled:
        score += 25
        feedback_parts.append("Prioritize onions enabled (+25)")
    else:
        feedback_parts.append("GATE FAILED: privacy.prioritizeonions.enabled is NOT true (+0)")

    # 2. Folder exists
    if result.get('folder_exists', False):
        score += 15
        feedback_parts.append("Bookmark folder 'Auto-Routed Onions' exists (+15)")
    else:
        feedback_parts.append("Folder 'Auto-Routed Onions' missing (+0)")

    # 3. Bookmark inside folder
    if result.get('onion_bookmarked_in_folder', False):
        score += 15
        feedback_parts.append(".onion site bookmarked in folder (+15)")
    else:
        feedback_parts.append(".onion bookmark in folder missing (+0)")

    # 4. Report file exists and new
    if result.get('report_exists', False) and result.get('report_created_during_task', False):
        score += 15
        feedback_parts.append("Report file created (+15)")
    elif result.get('report_exists', False):
        score += 5
        feedback_parts.append("Report file exists but timestamp invalid (+5)")
    else:
        feedback_parts.append("Report file missing (+0)")

    # 5. Report contains onion
    if result.get('report_contains_onion', False):
        score += 10
        feedback_parts.append("Report contains valid v3 .onion address (+10)")
    else:
        feedback_parts.append("Report missing v3 .onion address (+0)")

    # 6. History check
    if result.get('history_has_onion_visit', False):
        score += 10
        feedback_parts.append("Browser history confirms .onion visit (+10)")
    else:
        feedback_parts.append("No .onion visit in history (+0)")

    # 7. VLM Trajectory Verification
    vlm_score = 0
    try:
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        images = frames + [final]
        if images and env_info.get("query_vlm"):
            prompt = (
                "Review these frames from a Tor Browser session. Did the user accomplish ANY of these: "
                "1. Open Settings and toggle 'Prioritize .onion sites when known', "
                "2. Visit a clearnet site and get automatically routed to a .onion site, or "
                "3. Use a text editor to write down an onion address? "
                "Respond entirely with just 'YES' or 'NO'."
            )
            vlm_response = env_info["query_vlm"](images=images, prompt=prompt)
            if "YES" in vlm_response.upper():
                vlm_score = 10
                feedback_parts.append("VLM confirms workflow actions (+10)")
            else:
                feedback_parts.append("VLM did not detect workflow actions (+0)")
        else:
            feedback_parts.append("VLM verification skipped (+0)")
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        feedback_parts.append(f"VLM verification error (+0)")
    
    score += vlm_score

    # Final threshold and gate check
    passed = (score >= 60) and prioritize_enabled
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }