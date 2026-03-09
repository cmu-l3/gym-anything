#!/usr/bin/env python3
"""
Verifier for Add Living Room Area Rug task (DreamPlan).
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_living_room_area_rug(traj, env_info, task_info):
    """
    Verify that an area rug was created in the living room.
    
    Criteria:
    1. Screenshot file exists and was created during task (20 pts)
    2. VLM: Rug is visible (40 pts)
    3. VLM: It is an *area* rug (has border), not wall-to-wall (30 pts)
    4. VLM: Texture looks like carpet/fabric (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve JSON result from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Note: In Windows envs, paths might be mapped differently, 
        # but copy_from_env usually handles the internal container path.
        # We assume the export script wrote to C:\tmp\task_result.json which maps to /tmp/task_result.json 
        # or the framework handles the path conversion.
        copy_from_env("C:\\tmp\\task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read result JSON: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to read task results"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
            
    # Retrieve user-saved screenshot for VLM analysis
    # The user saved it to Documents\rug_design.png
    user_screenshot_path = result.get("expected_output_path", "")
    local_screenshot_path = tempfile.NamedTemporaryFile(delete=False, suffix='.png').name
    screenshot_available = False
    
    if result.get("output_exists"):
        try:
            copy_from_env(user_screenshot_path, local_screenshot_path)
            screenshot_available = True
        except Exception as e:
            logger.warning(f"Could not copy user screenshot: {e}")

    # SCORING
    score = 0
    feedback = []
    
    # Crit 1: File mechanics (20 pts)
    if result.get("output_exists") and result.get("file_created_during_task"):
        score += 20
        feedback.append("Screenshot file created successfully.")
    elif result.get("output_exists"):
        score += 10
        feedback.append("Screenshot file exists but timestamp is uncertain.")
    else:
        feedback.append("No screenshot file found.")

    # Crit 2, 3, 4: VLM Verification (80 pts)
    if screenshot_available:
        # Use the user's explicit screenshot for primary VLM check
        # as it likely has the best camera angle set by the agent
        prompt = """
        Analyze this screenshot of a room design in DreamPlan software.
        
        I am looking for a newly added 'Area Rug' in the living room.
        
        1. Is there a rug visible in the center of the room?
        2. Is it an 'area rug' (meaning you can see the original floor - e.g. wood/tile - surrounding it), or does it cover the whole floor?
        3. Does the rug texture look like carpet or fabric, distinct from the surrounding floor?
        
        Respond in JSON:
        {
            "rug_visible": boolean,
            "is_area_rug": boolean,
            "distinct_texture": boolean,
            "description": "string"
        }
        """
        
        vlm_response = query_vlm(prompt=prompt, image=local_screenshot_path)
        
        if vlm_response.get("success"):
            data = vlm_response.get("parsed", {})
            
            if data.get("rug_visible"):
                score += 40
                feedback.append("VLM confirmed rug visibility.")
                
                if data.get("is_area_rug"):
                    score += 30
                    feedback.append("VLM confirmed it is an area rug (has border).")
                else:
                    feedback.append("VLM suggests the rug might be wall-to-wall (penalty applied).")
                    
                if data.get("distinct_texture"):
                    score += 10
                    feedback.append("VLM confirmed distinct carpet texture.")
            else:
                feedback.append("VLM could not clearly see the rug.")
        else:
            feedback.append("VLM analysis failed.")
            
        # Cleanup
        if os.path.exists(local_screenshot_path):
            os.unlink(local_screenshot_path)
    else:
        feedback.append("Skipping VLM check (no screenshot).")

    # Anti-gaming: Check trajectory frames if screenshot failed or for extra confidence
    # (Optional fallback logic could go here)

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }