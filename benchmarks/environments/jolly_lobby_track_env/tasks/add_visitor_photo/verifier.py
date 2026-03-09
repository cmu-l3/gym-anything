#!/usr/bin/env python3
"""
Verifier for add_visitor_photo task in Jolly Lobby Track.

Verifies that:
1. A new photo file was created in the application's storage (primary signal).
2. The database was modified (secondary signal).
3. Visual confirmation via VLM that the photo was attached to the "Marcus Webb" record.
"""

import json
import os
import tempfile
import logging
import sys
from pathlib import Path

# Add parent directory to path to allow importing vlm_utils if needed locally
# (In production, these are available in the python environment)
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_visitor_photo(traj, env_info, task_info):
    """
    Verify that the agent attached a photo to the visitor record.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load programmatic results from the container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Criteria 1: File System Evidence (40 points)
    # Did the app create a new photo file?
    photo_found = result.get('photo_found', False)
    db_modified = result.get('db_modified', False)
    
    if photo_found:
        score += 40
        feedback_parts.append("New photo file detected in application storage")
    else:
        feedback_parts.append("No new photo file detected in application storage")

    # Criteria 2: Database Persistence (10 points)
    if db_modified:
        score += 10
        feedback_parts.append("Database modification detected")
    
    # Criteria 3: VLM Visual Verification (50 points)
    # We check the final state and trajectory
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    if not final_screen:
        feedback_parts.append("No final screenshot available")
    else:
        # VLM Query
        prompt = """
        Review this sequence of interactions with Jolly Lobby Track visitor management software.
        The goal was to add a photo to a visitor record for 'Marcus Webb'.
        
        Look for:
        1. A visitor record form for "Marcus Webb" being open.
        2. A photo being visible in the visitor's profile picture area (it should look like a person, not a blank placeholder).
        3. The user saving the record (clicking Save or OK).
        
        Answer JSON:
        {
            "visitor_record_seen": boolean,
            "visitor_name_matches": boolean,
            "photo_added_and_visible": boolean,
            "save_action_observed": boolean,
            "confidence": float (0-1)
        }
        """
        
        try:
            vlm_response = query_vlm(
                images=frames + [final_screen],
                prompt=prompt
            )
            
            if vlm_response.get("success"):
                parsed = vlm_response.get("parsed", {})
                
                if parsed.get("visitor_record_seen") and parsed.get("visitor_name_matches"):
                    score += 15
                    feedback_parts.append("VLM confirmed visitor record accessed")
                
                if parsed.get("photo_added_and_visible"):
                    score += 25
                    feedback_parts.append("VLM confirmed photo is visible in record")
                else:
                    feedback_parts.append("VLM did not see the photo in the final record")
                    
                if parsed.get("save_action_observed"):
                    score += 10
                    feedback_parts.append("VLM confirmed save action")
            else:
                feedback_parts.append("VLM verification failed")
                
        except Exception as e:
            logger.error(f"VLM error: {e}")
            feedback_parts.append(f"VLM verification error: {str(e)}")

    # Final logic
    # Must have either file evidence OR strong visual evidence to pass
    passed = score >= 60 and (photo_found or (parsed.get("photo_added_and_visible") and parsed.get("save_action_observed")))
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }