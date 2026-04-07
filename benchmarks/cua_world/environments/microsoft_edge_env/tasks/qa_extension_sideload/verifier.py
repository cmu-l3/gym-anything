#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from gym_anything.vlm import get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_qa_extension_sideload(traj, env_info, task_info):
    """
    Verifies that the agent has:
    1. Enabled Developer Mode.
    2. Loaded the unpacked extension from the correct path.
    3. Pinned the extension to the toolbar.
    """
    
    # 1. Setup copy from env
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 2. Get result JSON
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
            
    # 3. Scoring Criteria
    score = 0
    feedback = []
    
    # Criterion A: Developer Mode Enabled (20 pts)
    if result.get("dev_mode_enabled"):
        score += 20
        feedback.append("Developer Mode is enabled.")
    else:
        feedback.append("Developer Mode is NOT enabled.")

    # Criterion B: Extension Loaded (40 pts)
    ext_id = result.get("extension_id")
    if result.get("extension_loaded") and ext_id:
        score += 40
        feedback.append("Extension loaded successfully from correct path.")
    else:
        feedback.append("Extension NOT loaded from /home/ga/Documents/BugReporter_v2.")
        return {"passed": False, "score": score, "feedback": " ".join(feedback)}

    # Criterion C: Extension Pinned (30 pts)
    # Check if the ID is in the pinned list (Programmatic)
    # OR check via VLM if programmatic check is ambiguous (Chromium prefs vary).
    pinned_list = result.get("pinned_extensions", [])
    programmatic_pinned = ext_id in pinned_list
    
    # VLM Verification (Robustness check for pinning)
    vlm_pinned = False
    final_screenshot = get_final_screenshot(traj)
    if final_screenshot:
        prompt = (
            "Look at the browser toolbar (to the right of the address bar). "
            "Do you see a red square icon or a red bug icon? "
            "Ignore the puzzle piece icon. Reply YES or NO."
        )
        vlm_resp = query_vlm(prompt=prompt, image=final_screenshot)
        if vlm_resp and "YES" in vlm_resp.get("response", "").upper():
            vlm_pinned = True
    
    if programmatic_pinned or vlm_pinned:
        score += 30
        feedback.append("Extension appears to be pinned.")
    else:
        feedback.append("Extension is loaded but does not appear to be pinned to the toolbar.")

    # Criterion D: Clean Execution (10 pts)
    # Basic check that we got here without crashing
    score += 10

    # Pass Threshold
    passed = score >= 90
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }