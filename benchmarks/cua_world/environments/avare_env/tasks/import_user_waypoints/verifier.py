#!/usr/bin/env python3
"""
Verifier for import_user_waypoints task.

Verification Strategy:
1. UI Text Verification (Primary): Check if "LZ_ALPHA" appears in the final UI dump or screenshot.
2. VLM Verification (Robustness): Use VLM to confirm the Search/Find interface is active and shows the result.
3. Process Verification: Analyze trajectory to see if "Import" menus were accessed.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_import_user_waypoints(traj, env_info, task_info):
    """
    Verify that the agent imported the GPX file and found the waypoint.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_waypoint = metadata.get('target_waypoint', "LZ_ALPHA")

    feedback_parts = []
    score = 0
    
    # 1. Retrieve Data from Environment
    temp_dir = tempfile.mkdtemp()
    try:
        # Get result JSON
        result_file = os.path.join(temp_dir, "task_result.json")
        try:
            copy_from_env("/sdcard/task_result.json", result_file)
            with open(result_file, 'r') as f:
                result_data = json.load(f)
        except Exception as e:
            logger.error(f"Failed to load task result: {e}")
            result_data = {}

        # Get UI Dump
        ui_dump_file = os.path.join(temp_dir, "ui_dump.xml")
        ui_content = ""
        try:
            copy_from_env("/sdcard/ui_dump.xml", ui_dump_file)
            with open(ui_dump_file, 'r', encoding='utf-8', errors='ignore') as f:
                ui_content = f.read()
        except Exception:
            logger.warning("UI dump not found or unreadable")

        # 2. Check Database/Internal State (if available)
        if result_data.get("db_check_success", False):
            score += 30
            feedback_parts.append("Confirmed data present in internal database.")
        
        # 3. Check UI Text (Direct Search)
        # We look for the target waypoint string in the XML dump
        ui_confirmed = False
        if target_waypoint in ui_content:
            ui_confirmed = True
            score += 40
            feedback_parts.append(f"Found '{target_waypoint}' in screen text.")
        
        # 4. VLM Verification (Visual confirmation)
        # We check if the final screen looks like a search result
        final_screenshot = get_final_screenshot(traj)
        
        vlm_prompt = f"""
        The user is trying to find a custom waypoint named '{target_waypoint}' in an aviation app.
        
        Please analyze the screenshot and determine:
        1. Is the "Find" or "Search" interface visible?
        2. Is the text '{target_waypoint}' visible on the screen?
        3. Does it look like a search result (e.g. list item with distance/bearing)?
        
        Return JSON:
        {{
            "search_interface_visible": true/false,
            "target_visible": true/false,
            "is_search_result": true/false
        }}
        """
        
        vlm_result = query_vlm(
            prompt=vlm_prompt,
            image=final_screenshot
        )
        
        vlm_data = vlm_result.get("parsed", {})
        
        if vlm_data.get("target_visible", False):
            if not ui_confirmed: # Don't double count if UI dump already found it
                score += 40
                feedback_parts.append(f"Visual confirmation of '{target_waypoint}'.")
            
            if vlm_data.get("is_search_result", False):
                score += 20
                feedback_parts.append("Confirmed valid search result format.")
            elif vlm_data.get("search_interface_visible", False):
                score += 10
                feedback_parts.append("Search interface is active.")
        else:
            if not ui_confirmed:
                feedback_parts.append(f"'{target_waypoint}' NOT found in visual analysis.")

        # 5. Trajectory Verification (Process)
        # Check if they actually went through an import flow
        frames = sample_trajectory_frames(traj, n=5)
        
        process_prompt = """
        Review these screenshots of the user's workflow.
        Did the user access a "Menu", "Tools", or "Import" screen?
        Did they select a file named "company_lz.gpx"?
        
        Return JSON:
        {
            "accessed_menu": true/false,
            "file_selection_visible": true/false
        }
        """
        
        process_result = query_vlm(
            prompt=process_prompt,
            images=frames
        )
        
        proc_data = process_result.get("parsed", {})
        if proc_data.get("file_selection_visible", False):
            score += 10
            feedback_parts.append("File selection step observed.")
        elif proc_data.get("accessed_menu", False):
            score += 5
            feedback_parts.append("Menu navigation observed.")

    finally:
        import shutil
        shutil.rmtree(temp_dir, ignore_errors=True)

    # Final scoring logic
    # Pass if we definitely found the text either in UI dump or VLM, AND score is decent
    passed = (ui_confirmed or vlm_data.get("target_visible", False)) and score >= 60

    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " ".join(feedback_parts)
    }