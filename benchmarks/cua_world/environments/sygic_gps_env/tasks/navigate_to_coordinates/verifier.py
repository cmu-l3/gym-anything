#!/usr/bin/env python3
"""
Verifier for navigate_to_coordinates task.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_navigate_to_coordinates(traj, env_info, task_info):
    """
    Verifies that the agent navigated to specific GPS coordinates.
    
    Verification Logic:
    1. App Status (10 pts): App must be running at the end.
    2. Workflow (40 pts): VLM checks trajectory for:
       - Search bar interaction
       - Typing of specific coordinates (48.85837, 2.29448)
       - Selection of result
    3. Final State (50 pts): VLM checks final screen for:
       - Map pin/marker
       - Location context (Paris, Eiffel Tower, etc.)
    """
    
    # 1. Setup and retrieve data from environment
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_keywords = metadata.get('expected_context_keywords', [])
    
    # Create temp directory for artifacts
    with tempfile.TemporaryDirectory() as temp_dir:
        local_result_json = os.path.join(temp_dir, "task_result.json")
        
        try:
            copy_from_env("/sdcard/task_result.json", local_result_json)
            with open(local_result_json, 'r') as f:
                result_data = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}

        score = 0
        feedback_log = []
        
        # ------------------------------------------------------------------
        # CRITERION 1: App Status (10 pts)
        # ------------------------------------------------------------------
        if result_data.get("app_running", False):
            score += 10
            feedback_log.append("App was running (+10)")
        else:
            feedback_log.append("App was NOT running (-10)")

        # ------------------------------------------------------------------
        # CRITERION 2: VLM Trajectory Verification (40 pts)
        # ------------------------------------------------------------------
        # We sample frames to see the typing process
        frames = sample_trajectory_frames(traj, n=5)
        
        traj_prompt = """
        Analyze these screenshots from a Sygic GPS Navigation task.
        The user was supposed to:
        1. Open the search bar.
        2. Type coordinates '48.85837, 2.29448'.
        3. Select the result.

        Return a JSON object with these boolean keys:
        {
            "search_opened": true/false,
            "coordinates_typed": true/false,
            "result_selected": true/false
        }
        
        For "coordinates_typed", look for the numbers '48.85' or '2.29' in an input field.
        """
        
        traj_response = query_vlm(images=frames, prompt=traj_prompt)
        
        # Handle VLM response (parse JSON if possible, otherwise string match)
        search_opened = False
        coordinates_typed = False
        result_selected = False
        
        if isinstance(traj_response, dict) and 'parsed' in traj_response:
             parsed = traj_response['parsed']
             search_opened = parsed.get('search_opened', False)
             coordinates_typed = parsed.get('coordinates_typed', False)
             result_selected = parsed.get('result_selected', False)
        else:
            # Fallback string parsing
            resp_str = str(traj_response).lower()
            search_opened = "search_opened': true" in resp_str or "search_opened\": true" in resp_str
            coordinates_typed = "coordinates_typed': true" in resp_str or "coordinates_typed\": true" in resp_str
            result_selected = "result_selected': true" in resp_str or "result_selected\": true" in resp_str

        if search_opened:
            score += 10
            feedback_log.append("Search opened (+10)")
        if coordinates_typed:
            score += 20
            feedback_log.append("Coordinates entry detected (+20)")
        if result_selected:
            score += 10
            feedback_log.append("Result selected (+10)")

        # ------------------------------------------------------------------
        # CRITERION 3: VLM Final State Verification (50 pts)
        # ------------------------------------------------------------------
        final_screenshot = get_final_screenshot(traj)
        
        final_prompt = f"""
        Analyze this final screenshot from Sygic GPS Navigation.
        The goal was to navigate to coordinates 48.85837, 2.29448 (Eiffel Tower, Paris).
        
        Return a JSON object:
        {{
            "is_map_view": true/false,
            "destination_pin_visible": true/false,
            "location_context_match": true/false,
            "reason": "Explain what location is shown"
        }}
        
        For "location_context_match", look for text like "Paris", "Eiffel", "Tour", "Champ de Mars", "France" OR the coordinates.
        """
        
        final_response = query_vlm(images=[final_screenshot], prompt=final_prompt)
        
        # Parsing
        location_confirmed = False
        destination_visible = False
        
        if isinstance(final_response, dict) and 'parsed' in final_response:
             parsed = final_response['parsed']
             location_confirmed = parsed.get('location_context_match', False)
             destination_visible = parsed.get('destination_pin_visible', False)
        else:
            resp_str = str(final_response).lower()
            location_confirmed = "location_context_match': true" in resp_str or "location_context_match\": true" in resp_str
            destination_visible = "destination_pin_visible': true" in resp_str or "destination_pin_visible\": true" in resp_str

        if destination_visible:
            score += 20
            feedback_log.append("Destination pin visible (+20)")
        
        if location_confirmed:
            score += 30
            feedback_log.append("Correct location (Paris/Eiffel) confirmed (+30)")
        else:
            feedback_log.append("Correct location context NOT found in final screenshot")

        # ------------------------------------------------------------------
        # Final Scoring
        # ------------------------------------------------------------------
        # Pass requirement: Score >= 60 AND correct coordinates were typed
        passed = score >= 60 and coordinates_typed
        
        return {
            "passed": passed,
            "score": score,
            "feedback": "; ".join(feedback_log)
        }