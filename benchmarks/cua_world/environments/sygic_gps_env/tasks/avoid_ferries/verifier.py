#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logger = logging.getLogger(__name__)

def verify_avoid_ferries(traj, env_info, task_info):
    """
    Verifies that the agent enabled 'Avoid Ferries' in Sygic GPS.
    
    Verification Logic:
    1. VLM: Analyzes trajectory to ensure navigation to Settings > Route Planning.
    2. VLM: Analyzes final screenshot to verify 'Ferries' option is visible and toggled ON.
    3. Programmatic: Checks UI dump (if available) to confirm presence of 'Ferries' text.
    """
    
    # Setup helpers
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # Temporary directory for artifacts
    with tempfile.TemporaryDirectory() as temp_dir:
        # Retrieve artifacts
        local_result_json = os.path.join(temp_dir, "task_result.json")
        local_ui_dump = os.path.join(temp_dir, "ui_dump.xml")
        
        try:
            copy_from_env("/sdcard/task_result.json", local_result_json)
            copy_from_env("/sdcard/ui_dump.xml", local_ui_dump)
        except Exception as e:
            logger.warning(f"Failed to copy artifacts: {e}")
            # We can still proceed with VLM verification of the trajectory

        # Load JSON result
        task_data = {}
        if os.path.exists(local_result_json):
            with open(local_result_json, 'r') as f:
                try:
                    task_data = json.load(f)
                except:
                    pass

        # === Criterion 1: Programmatic UI Text Check (20 pts) ===
        # Verify we are on a screen that mentions "Ferries"
        ui_score = 0
        ui_feedback = []
        ui_text_found = False
        
        if os.path.exists(local_ui_dump):
            with open(local_ui_dump, 'r', encoding='utf-8', errors='ignore') as f:
                dump_content = f.read().lower()
                if "ferries" in dump_content or "ferry" in dump_content:
                    ui_score = 20
                    ui_text_found = True
                    ui_feedback.append("UI contains 'Ferries' text")
                else:
                    ui_feedback.append("UI dump does not contain 'Ferries' (wrong screen?)")
        else:
            ui_feedback.append("No UI dump available for text check")

        # === Criterion 2: VLM Visual Verification (80 pts) ===
        # Analyze trajectory and final state
        
        # Get frames
        frames = sample_trajectory_frames(traj, n=4)
        final_screen = get_final_screenshot(traj)
        
        if final_screen is None:
             return {"passed": False, "score": 0, "feedback": "No screenshots available"}
            
        all_images = frames + [final_screen]
        
        prompt = """
        You are verifying a task in the Sygic GPS Navigation app.
        The user was asked to: Navigate to Settings -> Route Planning -> Enable 'Avoid Ferries'.
        
        Examine the screenshots, especially the final one.
        
        1. Did the user navigate to a Settings or Route menu?
        2. Is the "Ferries" (or "Ferry lines") option visible on the screen?
        3. Is the toggle/checkbox for Ferries switched ON?
           - Sygic toggles usually turn BLUE or have a highlighted indicator when ON.
           - If it is grey/dim, it is OFF.
           
        Return JSON:
        {
            "navigated_to_settings": true/false,
            "ferries_option_visible": true/false,
            "ferries_toggled_on": true/false,
            "confidence": "low/medium/high"
        }
        """
        
        vlm_result = query_vlm(images=all_images, prompt=prompt)
        
        if not vlm_result.get("success"):
            return {"passed": False, "score": 0, "feedback": "VLM verification failed"}
            
        analysis = vlm_result.get("parsed", {})
        
        # Scoring logic
        vlm_score = 0
        
        if analysis.get("navigated_to_settings"):
            vlm_score += 20
        else:
            ui_feedback.append("VLM did not observe navigation to settings")
            
        if analysis.get("ferries_option_visible"):
            vlm_score += 20
        else:
            ui_feedback.append("VLM did not see 'Ferries' option")
            
        if analysis.get("ferries_toggled_on"):
            vlm_score += 40
        else:
            ui_feedback.append("VLM determined 'Ferries' toggle is OFF")

        # Combine scores
        total_score = ui_score + vlm_score
        
        # Pass threshold: 75 points (Requires mostly correct nav + toggle ON or text match)
        passed = total_score >= 75
        
        final_feedback = f"Score: {total_score}/100. " + "; ".join(ui_feedback)

        return {
            "passed": passed,
            "score": total_score,
            "feedback": final_feedback
        }