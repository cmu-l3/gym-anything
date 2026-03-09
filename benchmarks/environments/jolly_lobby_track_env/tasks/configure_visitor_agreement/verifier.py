#!/usr/bin/env python3
"""
Verifier for configure_visitor_agreement task.

Verification Strategy:
1. File Evidence (30 pts):
   - User took the requested screenshot.
   - Screenshot was created during task execution.
2. System State (30 pts):
   - Config files were modified (implies saving).
   - Agreement text key phrases found in config files/registry.
3. VLM Verification (40 pts):
   - Analyzes user screenshot to confirm UI state:
     - Settings panel visible.
     - Agreement text correctly entered.
     - "Enabled" checkbox checked.

Anti-gaming:
- Checks timestamps of screenshots and files.
- VLM ensures the screenshot actually shows the app, not just a text editor.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_visitor_agreement(traj, env_info, task_info):
    """
    Verify that the visitor agreement was configured correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # Load result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # ---------------------------------------------------------
    # Criterion 1: User Screenshot Evidence (15 pts)
    # ---------------------------------------------------------
    screenshot_exists = result.get("screenshot_exists", False)
    screenshot_valid = result.get("screenshot_created_during_task", False)
    screenshot_size = result.get("screenshot_size", 0)
    
    user_screenshot_path = result.get("screenshot_path", "")

    if screenshot_exists and screenshot_valid and screenshot_size > 10000:
        score += 15
        feedback_parts.append("✅ Evidence screenshot created successfully")
    elif screenshot_exists:
        score += 5
        feedback_parts.append("⚠️ Screenshot exists but timestamp/size is suspicious")
    else:
        feedback_parts.append("❌ User did not save the confirmation screenshot")

    # ---------------------------------------------------------
    # Criterion 2: Configuration Persistence (35 pts)
    # ---------------------------------------------------------
    config_modified = result.get("config_files_modified", False)
    text_found = result.get("agreement_text_found_in_config", False)
    
    if config_modified:
        score += 10
        feedback_parts.append("✅ Configuration files modified (Save detected)")
    else:
        feedback_parts.append("⚠️ No configuration file changes detected (Did you save?)")

    if text_found:
        score += 25
        feedback_parts.append("✅ Agreement text found in system configuration")
    else:
        feedback_parts.append("❌ Agreement text NOT found in configuration files (Check text accuracy and save status)")

    # ---------------------------------------------------------
    # Criterion 3: VLM Verification (50 pts)
    # ---------------------------------------------------------
    # We prefer the user's specific screenshot if it exists, otherwise fall back to final state
    image_to_verify = None
    
    # Try to fetch the user's screenshot specifically
    if screenshot_exists and user_screenshot_path:
        # We need to copy the image out of the container to use it with VLM
        try:
            local_img = tempfile.NamedTemporaryFile(delete=False, suffix='.png').name
            copy_from_env(user_screenshot_path, local_img)
            image_to_verify = local_img
            feedback_parts.append("ℹ️ Verifying user-provided screenshot")
        except Exception:
            logger.warning("Could not copy user screenshot, falling back to trajectory")

    # Fallback to final screenshot from export_result
    if not image_to_verify:
        image_to_verify = get_final_screenshot(traj)
        feedback_parts.append("ℹ️ Verifying final state screenshot")

    if image_to_verify:
        vlm_prompt = """
        You are verifying a task in Jolly Lobby Track software.
        Goal: Configure the Visitor Agreement settings.
        
        Analyze the screenshot and look for the following specific elements:
        1. Is a "Settings", "Configuration", or "Options" window visible (not just the main dashboard)?
        2. Is the "Visitor Agreement", "NDA", or "Policy" section visible?
        3. Is there a checkbox/toggle that appears ENABLED/CHECKED for the agreement?
        4. Is the specific text visible: "By signing in, I acknowledge that I may be exposed to confidential information... Morrison & Associates"?
        
        Respond in JSON:
        {
            "settings_window_visible": true/false,
            "agreement_enabled": true/false,
            "text_matches": true/false,
            "reasoning": "brief explanation"
        }
        """
        
        vlm_res = query_vlm(vlm_prompt, image=image_to_verify)
        
        if vlm_res.get("success"):
            parsed = vlm_res.get("parsed", {})
            if parsed.get("settings_window_visible"):
                score += 10
                feedback_parts.append("✅ Settings window visible")
            
            if parsed.get("agreement_enabled"):
                score += 15
                feedback_parts.append("✅ Agreement feature appears enabled")
            else:
                feedback_parts.append("❌ Agreement feature does not appear enabled")
                
            if parsed.get("text_matches"):
                score += 25
                feedback_parts.append("✅ Agreement text content verified visually")
            else:
                feedback_parts.append("❌ Agreement text does not match expected content visually")
                
            # Clean up temp file if we created one
            if image_to_verify and image_to_verify != get_final_screenshot(traj):
                try:
                    os.unlink(image_to_verify)
                except:
                    pass
        else:
            feedback_parts.append("⚠️ VLM verification failed to run")
    else:
        feedback_parts.append("❌ No valid screenshot available for visual verification")

    # ---------------------------------------------------------
    # Final Scoring
    # ---------------------------------------------------------
    # Pass threshold: 60 points (Requires at least some config evidence OR strong visual evidence)
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }