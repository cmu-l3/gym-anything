#!/usr/bin/env python3
"""
Verifier for force_stop_and_restart task.

Verification Logic:
1. Process ID Verification (Primary):
   - Initial PID must exist.
   - Final PID must exist (app must be running at end).
   - Final PID must be DIFFERENT from Initial PID (proves restart).

2. VLM Verification (Secondary):
   - Trajectory must show Android Settings -> Apps.
   - Trajectory must show "Force Stop" button interaction.
   - Final screenshot must show the app open.

Scoring:
- 40 pts: App Process Restarted (PID changed)
- 30 pts: VLM confirms Settings/Force Stop workflow
- 30 pts: App is running and visible at the end
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_force_stop_and_restart(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # ================================================================
    # 1. Retrieve Result JSON
    # ================================================================
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Extract Data
    initial_pid = result.get("initial_pid")
    final_pid = result.get("final_pid")
    app_running = result.get("app_running", False)

    feedback_parts = []
    score = 0
    pid_check_passed = False

    # ================================================================
    # 2. PID Verification (40 pts)
    # ================================================================
    if initial_pid and initial_pid != "null" and final_pid and final_pid != "null":
        if initial_pid != final_pid:
            score += 40
            pid_check_passed = True
            feedback_parts.append("✅ App process successfully restarted (PID changed)")
        else:
            feedback_parts.append("❌ PID did not change (App was not killed or didn't restart)")
    else:
        if not app_running:
             feedback_parts.append("❌ App is not running at task end")
        else:
             feedback_parts.append("❌ Could not verify PIDs")

    # ================================================================
    # 3. App Visibility Check (30 pts)
    # ================================================================
    # Simple check: is app running?
    if app_running:
        score += 15
        feedback_parts.append("✅ App process is active")
    
    # VLM check for visibility on screen
    final_screenshot = get_final_screenshot(traj)
    if final_screenshot:
        vis_prompt = """
        Is the 'Flight Crew View' app visible on the screen? 
        Look for a list of friends/crew, flight information, or the app's login/welcome screen.
        If you see the Android Settings or Home Screen, answer No.
        Return JSON: {"app_visible": true/false}
        """
        vis_result = query_vlm(prompt=vis_prompt, image=final_screenshot)
        if vis_result.get("success") and vis_result.get("parsed", {}).get("app_visible"):
            score += 15
            feedback_parts.append("✅ App UI is visible")
        else:
            feedback_parts.append("⚠️ App process running but UI may not be visible")

    # ================================================================
    # 4. Trajectory Verification (30 pts)
    # ================================================================
    # We need to ensure they actually went to settings and didn't just crash the app or swipe it away
    frames = sample_trajectory_frames(traj, n=5)
    
    traj_prompt = """
    Review these screenshots of an agent's actions on Android.
    The goal was to: Navigate to Settings -> Apps -> Flight Crew View -> Force Stop.

    1. Do you see the Android Settings menu or 'App Info' screen?
    2. Do you see a 'Force Stop' button?
    3. Do you see a confirmation dialog for Force Stop?

    Return JSON:
    {
        "visited_settings": true/false,
        "saw_force_stop": true/false,
        "saw_confirmation": true/false
    }
    """
    
    traj_result = query_vlm(images=frames, prompt=traj_prompt)
    
    if traj_result.get("success"):
        parsed = traj_result.get("parsed", {})
        if parsed.get("visited_settings"):
            score += 10
            feedback_parts.append("✅ Visited Settings")
        else:
            feedback_parts.append("❌ Did not visit Settings")
            
        if parsed.get("saw_force_stop") or parsed.get("saw_confirmation"):
            score += 20
            feedback_parts.append("✅ Attempted Force Stop")
        else:
            feedback_parts.append("❌ Did not see Force Stop controls")
    else:
        feedback_parts.append("⚠️ Could not verify trajectory")

    # ================================================================
    # Final Result
    # ================================================================
    passed = (score >= 80) and pid_check_passed and app_running

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }