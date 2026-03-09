#!/usr/bin/env python3
"""
Verifier for enable_dark_theme task.

Verification Strategy:
1. Programmatic: Check Android system setting for Night Mode (40 pts)
2. Programmatic: Check if correct app is in foreground (15 pts)
3. VLM: Visual verification of dark theme implementation (30 pts)
4. VLM: Visual comparison with initial light state (15 pts)
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any

# Import VLM utilities from environment
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are verifying an Android UI task.
The goal was to enable "Dark Theme" (Dark Mode) in system settings and return to the "Flight Crew View" app.

Input Images:
1. Initial State (Light Mode)
2. Final State (Should be Dark Mode)

Analyze the FINAL screenshot:
1. Is the background color predominantly dark (black/dark gray) instead of white?
2. Is the "Flight Crew View" app visible (look for lists of flights, calendar grids, or "Friends" list)?
3. Does it look visually different from the Initial screenshot (which was white)?

Return JSON:
{
  "is_dark_background": true/false,
  "is_app_visible": true/false,
  "visually_different_from_initial": true/false,
  "confidence": "high/medium/low"
}
"""

def verify_enable_dark_theme(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify enable_dark_theme task using system state and VLM visual confirmation.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    score = 0
    feedback_parts = []
    
    # =========================================================
    # 1. Retrieve Programmatic Results (JSON)
    # =========================================================
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # Check System Setting (40 pts)
    if result_data.get("is_dark_mode_enabled", False):
        score += 40
        feedback_parts.append("✅ System Dark Mode enabled")
    else:
        feedback_parts.append("❌ System Dark Mode NOT enabled")

    # Check Foreground App (15 pts)
    if result_data.get("app_in_foreground", False):
        score += 15
        feedback_parts.append("✅ App returned to foreground")
    else:
        feedback_parts.append("❌ App not in foreground at end")

    # Anti-gaming check (Time)
    duration = result_data.get("duration_seconds", 0)
    if duration < 5:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"❌ Task completed too quickly ({duration}s). Suspicious activity."
        }

    # =========================================================
    # 2. Retrieve Screenshots for VLM
    # =========================================================
    # We need the initial screenshot from setup and final from export
    initial_ss_local = tempfile.NamedTemporaryFile(delete=False, suffix='.png').name
    
    has_initial = False
    try:
        copy_from_env("/sdcard/task_initial.png", initial_ss_local)
        has_initial = True
    except Exception:
        feedback_parts.append("⚠️ Could not retrieve initial screenshot")

    final_screenshot = get_final_screenshot(traj)
    
    if not final_screenshot or not has_initial:
        # Fallback if screenshots missing, cap score
        return {
            "passed": score >= 55,
            "score": score,
            "feedback": " | ".join(feedback_parts) + " (Visual verification skipped due to missing images)"
        }

    # =========================================================
    # 3. VLM Verification (45 pts total)
    # =========================================================
    # We pass both initial (from setup) and final (from trajectory) to VLM
    # Note: query_vlm accepts a list of images.
    
    try:
        vlm_response = query_vlm(
            prompt=VLM_PROMPT,
            images=[initial_ss_local, final_screenshot]
        )
        
        if vlm_response.get("success"):
            analysis = vlm_response.get("parsed", {})
            
            # Criterion: Dark Background (30 pts)
            if analysis.get("is_dark_background", False):
                score += 30
                feedback_parts.append("✅ Visual: Dark theme confirmed")
            else:
                feedback_parts.append("❌ Visual: UI appears light/white")

            # Criterion: Visual Change (15 pts)
            if analysis.get("visually_different_from_initial", False):
                score += 15
                feedback_parts.append("✅ Visual: Distinct change from initial state")
            else:
                feedback_parts.append("❌ Visual: No significant change detected")
                
        else:
            feedback_parts.append(f"⚠️ VLM Error: {vlm_response.get('error')}")
            
    except Exception as e:
        feedback_parts.append(f"⚠️ VLM Exception: {str(e)}")
    finally:
        if os.path.exists(initial_ss_local):
            os.unlink(initial_ss_local)

    # =========================================================
    # Final Scoring
    # =========================================================
    # Pass threshold: 55 pts (Must at least set system mode + be in app OR set mode + visual confirm)
    passed = score >= 55
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "system_check": result_data.get("is_dark_mode_enabled"),
            "app_check": result_data.get("app_in_foreground"),
            "duration": duration
        }
    }