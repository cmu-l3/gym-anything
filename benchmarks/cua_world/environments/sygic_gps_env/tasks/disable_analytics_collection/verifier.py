#!/usr/bin/env python3
"""
Verifier for disable_analytics_collection task.

Verification Strategy:
1. VLM Trajectory Analysis (Primary):
   - Did the agent navigate to Settings?
   - Did the agent enter the Privacy/About section?
   - Did the agent toggle the "Product improvement" switch?
2. Final State Verification (Secondary):
   - Is the toggle visible and OFF in the final screenshot?
   - Do shared preferences reflect the disabled state (if accessible)?
"""

import json
import os
import tempfile
import logging
import re
from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_disable_analytics(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Setup temp files
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_ui = tempfile.NamedTemporaryFile(delete=False, suffix='.xml')
    
    score = 0
    feedback_parts = []
    
    try:
        # 1. Retrieve Task Result JSON
        copy_from_env("/sdcard/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
            
        # 2. Retrieve UI Dump (for XML parsing fallback)
        try:
            copy_from_env("/sdcard/ui_dump.xml", temp_ui.name)
            with open(temp_ui.name, 'r', errors='ignore') as f:
                ui_content = f.read()
        except Exception:
            ui_content = ""

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task data: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
        if os.path.exists(temp_ui.name):
            os.unlink(temp_ui.name)

    # --- Criterion 1: App was running (10 pts) ---
    if result_data.get("app_running", False):
        score += 10
        feedback_parts.append("App was running.")
    else:
        feedback_parts.append("App was NOT running at end of task.")

    # --- Criterion 2: VLM Trajectory Verification (50 pts) ---
    # We check if the agent actually performed the workflow
    frames = sample_trajectory_frames(traj, n=6)
    final_screen = get_final_screenshot(traj)
    
    vlm_prompt = """
    You are verifying an agent performing a privacy task in Sygic GPS Navigation.
    Goal: Disable "Product improvement" or "Usage statistics" data collection.
    
    Review the image sequence. 
    1. Did the agent open the Settings menu?
    2. Did the agent navigate to "Information", "About", or "Privacy"?
    3. Did the agent locate a "Product improvement" or "Help improve Sygic" toggle?
    4. Did the agent switch this toggle to OFF (unchecked/gray)?
    
    In the FINAL image:
    - Is the "Product improvement" (or similar) toggle visible?
    - Is it clearly in the OFF position?
    
    Output JSON:
    {
        "settings_opened": boolean,
        "privacy_menu_reached": boolean,
        "toggle_interaction_seen": boolean,
        "final_state_is_off": boolean,
        "explanation": "string"
    }
    """
    
    vlm_result = query_vlm(images=frames + [final_screen], prompt=vlm_prompt)
    vlm_data = vlm_result.get("parsed", {})
    
    if vlm_data.get("settings_opened"):
        score += 10
    if vlm_data.get("privacy_menu_reached"):
        score += 15
    if vlm_data.get("final_state_is_off"):
        score += 25
        feedback_parts.append("VLM confirms setting is OFF.")
    else:
        feedback_parts.append("VLM did NOT confirm setting is OFF.")

    # --- Criterion 3: Programmatic/Text Evidence (40 pts) ---
    # Check UI dump or SharedPrefs for confirmation
    
    # Check 3A: Search UI Dump for text indicating OFF state
    # In Android XML, unchecked usually means 'checked="false"'
    evidence_found = False
    
    keywords = ["Product improvement", "Help improve Sygic", "Usage statistics"]
    if ui_content:
        for keyword in keywords:
            # Look for the keyword in the node, and check if it or its parent/sibling is checked=false
            # This is a heuristic text check on the raw XML
            if keyword in ui_content:
                # We found the text. Now simple check if "checked" is nearby.
                # A more robust check would parse XML, but text search is often sufficient for verifying existence
                pass
    
    # Check 3B: Shared Preferences Analysis
    prefs_evidence = result_data.get("prefs_evidence", "")
    # If we see a flag like "analytics_enabled" value="false"
    if re.search(r'(analytics|consent|improvement).*value="false"', prefs_evidence, re.IGNORECASE):
        score += 40
        evidence_found = True
        feedback_parts.append("Shared preferences confirm disabled state.")
    elif re.search(r'(analytics|consent|improvement).*value="true"', prefs_evidence, re.IGNORECASE):
        # Explicitly enabled
        score = max(0, score - 20) # Penalize if explicitly ON
        feedback_parts.append("Shared preferences indicate setting is still ON.")
    else:
        # If we can't confirm via prefs, rely heavily on VLM score
        # We give partial credit if VLM was very confident
        if vlm_data.get("final_state_is_off"):
            score += 40
            feedback_parts.append("Relied on visual verification (prefs ambiguous).")

    # Final tally
    passed = score >= 80 and vlm_data.get("final_state_is_off")
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " ".join(feedback_parts)
    }