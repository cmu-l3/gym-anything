#!/usr/bin/env python3
"""
Verifier for retrieve_route_eta_duration task.

Criteria:
1. File /sdcard/trip_duration.txt exists and was created during task.
2. Content of the file matches the duration displayed on the screen (via VLM).
3. VLM trajectory confirms "San Jose" was searched and route calculated.
"""

import json
import os
import tempfile
import logging
import re
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_retrieve_route_eta_duration(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Temp files for artifacts
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json').name
    temp_screenshot = tempfile.NamedTemporaryFile(delete=False, suffix='.png').name
    
    score = 0
    feedback_parts = []
    
    try:
        # 1. Load basic result metadata
        try:
            copy_from_env("/sdcard/task_result.json", temp_result)
            with open(temp_result, 'r') as f:
                result_data = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}

        output_exists = result_data.get('output_exists', False)
        created_during_task = result_data.get('created_during_task', False)
        file_content = result_data.get('output_content', "").strip()
        app_running = result_data.get('app_running', False)

        # 2. Score Basic Criteria
        if app_running:
            score += 10
            feedback_parts.append("App is running")
        
        if output_exists:
            score += 10
            feedback_parts.append("Output file exists")
            if created_during_task:
                score += 10
                feedback_parts.append("File created during task")
            else:
                feedback_parts.append("File NOT created during task (stale?)")
            
            if len(file_content) > 0:
                score += 10
                feedback_parts.append(f"File content: '{file_content}'")
            else:
                feedback_parts.append("File is empty")
        else:
            feedback_parts.append("Output file not found")

        # 3. VLM Verification of Content & Workflow
        # We need to verify if the file content matches the screen and if the workflow was followed
        
        # Get frames for workflow verification
        frames = sample_trajectory_frames(traj, n=4)
        final_frame = get_final_screenshot(traj)
        
        # Prepare VLM prompt
        prompt = f"""
        You are verifying a GPS navigation task.
        
        Goal: Plan a route to 'San Jose, CA' and write the estimated duration to a file.
        The agent wrote: "{file_content}"
        
        Please analyze the screenshots (sequence of events + final state) and answer:
        1. Did the agent search for "San Jose" (or "San Jose, CA")?
        2. Is a route summary displayed in the final image showing distance/time?
        3. What is the estimated duration displayed on the screen?
        4. Does the text written by the agent ("{file_content}") match the duration on screen? (Allow minor format differences like '1 h 12 min' vs '1h 12m' vs '72 min').
        
        Return JSON:
        {{
            "searched_san_jose": boolean,
            "route_summary_visible": boolean,
            "screen_duration_text": "string",
            "duration_matches": boolean,
            "reason": "string"
        }}
        """
        
        vlm_response = query_vlm(
            images=frames + [final_frame], 
            prompt=prompt
        )
        
        vlm_data = vlm_response.get('parsed', {})
        
        # Score VLM results
        if vlm_data.get('searched_san_jose', False):
            score += 20
            feedback_parts.append("VLM confirmed search for San Jose")
        else:
            feedback_parts.append("VLM did not see search for San Jose")
            
        if vlm_data.get('route_summary_visible', False):
            score += 20
            feedback_parts.append("Route summary visible")
        else:
            feedback_parts.append("Route summary NOT visible")
            
        if vlm_data.get('duration_matches', False):
            score += 20
            feedback_parts.append("Duration matches screen")
        else:
            feedback_parts.append(f"Duration mismatch (Screen: {vlm_data.get('screen_duration_text')})")

        # Pass logic
        passed = score >= 80 and output_exists and vlm_data.get('duration_matches', False)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Verification error: {str(e)}"}
    finally:
        # Cleanup
        if os.path.exists(temp_result):
            os.unlink(temp_result)
        if os.path.exists(temp_screenshot):
            os.unlink(temp_screenshot)