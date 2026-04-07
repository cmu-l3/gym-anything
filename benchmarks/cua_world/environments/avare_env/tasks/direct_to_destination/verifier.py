#!/usr/bin/env python3
"""
Verifier for direct_to_destination task (Avare GPS).

Verification Logic:
1. Programmatic Check (45 pts):
   - Inspects Avare's internal state (Preferences/Files) for "KSAC" or "SAC".
   - Verifies data was modified during task execution (anti-gaming).
   - Penalizes if the wrong airport (KSMF) is found.
   
2. VLM Check (55 pts):
   - Uses trajectory frames to verify the user actually used the UI workflow.
   - Checks for "Find" screen usage.
   - Checks for visual confirmation of "Sacramento Executive" or "KSAC" on map/list.
   
Pass Threshold: 60/100
"""

import json
import tempfile
import os
import logging
import sys
from pathlib import Path

# Add parent directory to path to allow importing vlm_utils if needed
sys.path.insert(0, str(Path(__file__).parent.parent))
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
except ImportError:
    # Fallback for when running outside full gym-anything environment
    def sample_trajectory_frames(traj, n=5): return []
    def get_final_screenshot(traj): return None
    def query_vlm(**kwargs): return {"success": False, "error": "VLM not available"}

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_direct_to_destination(traj, env_info, task_info):
    """
    Verify agent set Direct-To KSAC in Avare.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # 1. Fetch Programmatic Results
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/data/local/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            prog_result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result JSON: {e}")
        prog_result = {}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
            
    # 2. Score Programmatic Evidence (Max 45 pts)
    prog_score = 0
    feedback_parts = []
    
    destination_found = prog_result.get("destination_found", False)
    wrong_airport = prog_result.get("wrong_airport_found", False)
    files_modified = prog_result.get("files_modified_during_task", False)
    
    if destination_found:
        if files_modified:
            prog_score += 45
            feedback_parts.append("✅ Destination KSAC/SAC found in app state (Verified new)")
        else:
            prog_score += 20
            feedback_parts.append("⚠️ Destination found but timestamp unclear (Possible pre-existing)")
    else:
        feedback_parts.append("❌ Destination KSAC not found in app internal state")
        
    if wrong_airport:
        prog_score = 0 # Immediate fail for wrong airport in this specific task context
        feedback_parts.append("❌ Wrong airport detected (KSMF instead of KSAC)")

    # 3. Score VLM Evidence (Max 55 pts)
    vlm_score = 0
    
    # We need screenshots to proceed
    frames = sample_trajectory_frames(traj, n=4)
    final_shot = get_final_screenshot(traj)
    
    if final_shot:
        all_images = frames + [final_shot]
        
        prompt = """
        Review this sequence of screenshots from the Avare Aviation GPS app.
        The user task is to: Find and set "Sacramento Executive Airport" (KSAC) as the destination.
        
        Please verify the following steps:
        1. Did the user open the "Find" or Search screen?
        2. Is "KSAC" or "SAC" typed into a search box?
        3. Do you see "Sacramento Executive" in a list of results?
        4. In the final state, is KSAC/Sacramento Executive shown as the active destination (e.g., magenta line pointing to it, or listed in the top data bar)?
        
        Return a JSON object with boolean keys:
        - "find_screen_opened": true/false
        - "search_input_correct": true/false
        - "result_selected": true/false
        - "final_destination_visible": true/false
        """
        
        vlm_resp = query_vlm(images=all_images, prompt=prompt)
        
        if vlm_resp.get("success"):
            analysis = vlm_resp.get("parsed", {})
            
            if analysis.get("find_screen_opened"):
                vlm_score += 10
            if analysis.get("search_input_correct"):
                vlm_score += 15
            if analysis.get("result_selected"):
                vlm_score += 15
            if analysis.get("final_destination_visible"):
                vlm_score += 15
                
            feedback_parts.append(f"VLM Analysis: {json.dumps(analysis)}")
        else:
            feedback_parts.append("⚠️ VLM analysis failed")
            # Fallback: if programmatic was perfect, grant partial VLM points
            if prog_score == 45:
                vlm_score = 30
                feedback_parts.append("Granted partial VLM points based on strong programmatic evidence.")

    total_score = prog_score + vlm_score
    passed = total_score >= 60 and destination_found and not wrong_airport
    
    return {
        "passed": passed,
        "score": min(100, total_score),
        "feedback": " | ".join(feedback_parts)
    }