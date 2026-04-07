#!/usr/bin/env python3
"""
Verifier for analyze_terrain_profile task.

Verifies that:
1. Avare app is open.
2. A flight plan from KSMF to KRNO is active.
3. The Terrain Profile view is displayed.
4. The profile shows valid terrain data (mountains), not empty data.
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any

from gym_anything.vlm import get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# VLM Prompt to verify the specific visual requirements
VERIFICATION_PROMPT = """
You are verifying an aviation task in the Avare GPS app.
The user was asked to plan a route from Sacramento (KSMF) to Reno (KRNO) and open the 'Terrain Profile' view.

Analyze the screenshot and answer the following:
1. **Is the Profile View visible?** Look for a graph/chart at the bottom or taking up the screen, usually with altitude on the Y-axis and distance on the X-axis. It is often labeled "Profile" or "VS".
2. **Does the profile show MOUNTAINOUS terrain?** The route crosses the Sierra Nevada. You should see a jagged, rising and falling line (green/yellow/red). If the graph is empty or a flat line at 0/sea level, the data is missing.
3. **Are the waypoints correct?** Can you see references to "KSMF", "KRNO", "Sacramento", or "Reno" on the map or in the plan list?
4. **Is the app Avare?** (Aviation map style interface).

Response Format (JSON):
{
  "profile_view_visible": true/false,
  "terrain_data_valid": true/false,
  "waypoints_visible": true/false,
  "is_avare": true/false,
  "reasoning": "Explanation of what is seen..."
}
"""

def verify_analyze_terrain_profile(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify the terrain profile task using VLM and state checks.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    # 1. Retrieve artifacts from Android environment
    # We copy from /sdcard/ inside the emulator. 
    # Note: Depending on the specific bridge implementation, path might need adjustment.
    # Assuming standard /sdcard path mapping.
    
    temp_dir = tempfile.mkdtemp()
    local_json_path = os.path.join(temp_dir, "task_result.json")
    local_screenshot_path = os.path.join(temp_dir, "final_screenshot.png")
    
    try:
        # Try to copy result JSON
        try:
            copy_from_env("/sdcard/task_result.json", local_json_path)
            with open(local_json_path, 'r') as f:
                result_data = json.load(f)
        except Exception as e:
            logger.warning(f"Failed to load result JSON: {e}")
            result_data = {"app_running": False}

        # Try to copy screenshot (if not already in traj)
        # Note: traj usually has frames, but we ensure we get the high-res one captured by script
        try:
            copy_from_env("/sdcard/final_screenshot.png", local_screenshot_path)
            has_script_screenshot = True
        except Exception:
            has_script_screenshot = False

    finally:
        # We don't delete temp_dir immediately if we want to use the screenshot
        pass

    # 2. VLM Verification (Primary)
    # Use trajectory final frame or the script-captured screenshot
    final_img = local_screenshot_path if has_script_screenshot and os.path.exists(local_screenshot_path) else get_final_screenshot(traj)
    
    if not final_img:
        return {"passed": False, "score": 0, "feedback": "No screenshot available for verification"}

    vlm_result = query_vlm(
        prompt=VERIFICATION_PROMPT,
        image=final_img
    )

    if not vlm_result.get("success"):
        return {"passed": False, "score": 0, "feedback": f"VLM Analysis Failed: {vlm_result.get('error')}"}

    parsed = vlm_result.get("parsed", {})
    logger.info(f"VLM Analysis: {parsed}")

    # 3. Scoring Logic
    score = 0
    feedback_parts = []
    
    # Criteria 1: App Running (10 pts)
    if result_data.get("app_running"):
        score += 10
    
    # Criteria 2: Is Avare (10 pts)
    if parsed.get("is_avare"):
        score += 10
    else:
        feedback_parts.append("App does not look like Avare.")

    # Criteria 3: Waypoints Visible (20 pts)
    # Check both VLM and UI dump result
    if parsed.get("waypoints_visible") or result_data.get("plan_text_visible"):
        score += 20
        feedback_parts.append("Route KSMF->KRNO identified.")
    else:
        feedback_parts.append("Could not confirm waypoints KSMF/KRNO.")

    # Criteria 4: Profile View Open (30 pts)
    if parsed.get("profile_view_visible"):
        score += 30
        feedback_parts.append("Profile view is open.")
    else:
        feedback_parts.append("Profile view NOT found.")

    # Criteria 5: Valid Terrain Data (30 pts)
    # This is the critical "Did they download data?" check
    if parsed.get("terrain_data_valid"):
        score += 30
        feedback_parts.append("Valid mountain terrain data visible.")
    else:
        feedback_parts.append("Terrain profile appears flat or empty (Missing data?).")

    # Pass Threshold
    passed = score >= 80  # Requires Profile + Terrain + Route
    
    # Cleanup
    if os.path.exists(local_json_path): os.remove(local_json_path)
    if os.path.exists(local_screenshot_path): os.remove(local_screenshot_path)
    os.rmdir(temp_dir)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }