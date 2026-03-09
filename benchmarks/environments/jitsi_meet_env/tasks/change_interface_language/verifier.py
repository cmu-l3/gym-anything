#!/usr/bin/env python3
"""
Verifier for change_interface_language task.

Verification Strategy:
1. Programmatic Check (40 pts): Verify localStorage contains "language":"fr".
2. VLM Check (60 pts):
   - Verify final screenshot shows French UI text.
   - Verify trajectory shows interaction with Settings menu.
"""

import json
import os
import sys
import tempfile
import logging
from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_change_interface_language(traj, env_info, task_info):
    """
    Verifies that the Jitsi Meet interface language was changed to French.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # =========================================================
    # 1. Programmatic Check (40 pts)
    # =========================================================
    detected_lang = result.get("detected_language", "none")
    
    if detected_lang == "fr":
        score += 40
        feedback_parts.append("✅ LocalStorage setting confirmed as French.")
    elif detected_lang == "none":
        feedback_parts.append("⚠️ Could not verify LocalStorage setting (possibly checking wrong file).")
    else:
        feedback_parts.append(f"❌ LocalStorage setting is '{detected_lang}', expected 'fr'.")

    # =========================================================
    # 2. VLM Verification (60 pts)
    # =========================================================
    # We use trajectory frames to ensure they didn't just magic the final state
    # and to provide robust visual verification even if programmatic check fails.
    
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    
    if not final_frame:
        return {"passed": False, "score": 0, "feedback": "No screenshots available for verification."}
    
    # Prompt for VLM
    prompt = """
    You are verifying a task to change the Jitsi Meet interface language to French.
    
    Look at the final screenshot (the last image) and the trajectory.
    
    1. FINAL STATE: Is the interface text in French?
       - Look for buttons/labels like: "Couper le micro" (Mute), "Arrêter la caméra" (Stop cam), "Partager" (Share), "Quitter" (Leave).
       - Look for "Paramètres" instead of "Settings".
       - Look for "Inviter" instead of "Invite".
    
    2. WORKFLOW: Do the previous frames show the user opening a Settings dialog?
       - Typically a white modal window with tabs on the left or top.
       - A language dropdown menu.
       
    Respond in JSON:
    {
        "is_french_ui": true/false,
        "settings_dialog_seen": true/false,
        "english_ui_visible": true/false,
        "confidence": "high/medium/low",
        "reasoning": "Describe what text you see."
    }
    """
    
    vlm_result = query_vlm(prompt=prompt, images=frames + [final_frame])
    
    if vlm_result and vlm_result.get("success"):
        parsed = vlm_result.get("parsed", {})
        is_french = parsed.get("is_french_ui", False)
        settings_seen = parsed.get("settings_dialog_seen", False)
        
        if is_french:
            score += 40
            feedback_parts.append("✅ VLM confirms UI text is in French.")
        else:
            feedback_parts.append("❌ VLM did not detect French text in the interface.")
            
        if settings_seen:
            score += 20
            feedback_parts.append("✅ VLM observed Settings dialog interaction.")
        else:
            feedback_parts.append("⚠️ VLM did not clearly see the Settings dialog (acceptable if result is correct).")
    else:
        feedback_parts.append("⚠️ VLM verification failed to run.")
        # Fallback scoring if VLM fails but programmatic passed
        if detected_lang == "fr":
            score += 20 # Give benefit of doubt if programmatic passed
            feedback_parts.append("Granted partial points due to VLM failure but valid programmatic state.")

    # =========================================================
    # Final Scoring
    # =========================================================
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }