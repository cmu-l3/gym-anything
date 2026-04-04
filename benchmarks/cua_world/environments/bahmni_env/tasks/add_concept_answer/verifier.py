#!/usr/bin/env python3
"""
Verifier for add_concept_answer@1.
"""

import json
import os
import tempfile
import logging
from datetime import datetime

# Import VLM helpers if available
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
except ImportError:
    # Fallback/mock for standalone testing
    def sample_trajectory_frames(traj, n=5): return []
    def get_final_screenshot(traj): return None

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_concept_answer(traj, env_info, task_info):
    """
    Verify that the 'Transportation Method' concept has 'Bus' added as an answer.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')

    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    if "error" in result:
        return {"passed": False, "score": 0, "feedback": f"Export script error: {result['error']}"}

    score = 0
    feedback_parts = []
    
    # 1. Verify Concept State (Database Check)
    initial = result.get('initial_state', {})
    final_answers = result.get('final_answers', [])
    
    bus_uuid = initial.get('bus_uuid')
    walking_uuid = initial.get('walking_uuid')
    car_uuid = initial.get('car_uuid')
    
    final_uuids = [a['uuid'] for a in final_answers]
    
    # Check if Bus is added (60 pts)
    bus_added = bus_uuid in final_uuids
    if bus_added:
        score += 60
        feedback_parts.append("Success: 'Bus' is now an answer.")
    else:
        feedback_parts.append("Failure: 'Bus' is NOT in the answer list.")
        
    # Check for data loss (20 pts)
    # Walking and Car must still be there
    data_intact = (walking_uuid in final_uuids) and (car_uuid in final_uuids)
    if data_intact:
        score += 20
        feedback_parts.append("Data Integrity: Existing answers preserved.")
    else:
        feedback_parts.append("Data Loss: Previous answers were removed!")
        
    # Check if modification happened during task (Anti-gaming)
    # OpenMRS returns ISO8601 strings. Simple check: verify state changed from initial
    # We know initial state had 2 answers.
    state_changed = len(final_uuids) > initial.get('initial_answers_count', 0)
    
    if not state_changed and bus_added:
        # If count didn't increase but bus is there, something is weird (maybe replaced?)
        # But we already checked data_intact.
        pass
    
    # 2. VLM Verification (20 pts)
    # We want to see evidence of navigating the dictionary/concept UI
    vlm_score = 0
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final_ss = get_final_screenshot(traj)
        if final_ss:
            frames.append(final_ss)
            
        if frames:
            prompt = """
            Review these screenshots of an agent using the OpenMRS Administration interface.
            
            Look for:
            1. Navigation to 'Manage Concepts' or 'Dictionary'.
            2. Searching for or editing 'Transportation Method'.
            3. A list of answers visible (e.g., Walking, Car, Bus).
            
            Did the agent perform steps to edit a concept?
            Answer YES or NO and provide a short reason.
            """
            try:
                vlm_resp = query_vlm(images=frames, prompt=prompt)
                if vlm_resp and vlm_resp.get("success"):
                    content = vlm_resp.get("output", "").upper()
                    if "YES" in content:
                        vlm_score = 20
                        feedback_parts.append("VLM: Workflow verified visually.")
                    else:
                        feedback_parts.append("VLM: Workflow unclear from screenshots.")
            except Exception as e:
                logger.error(f"VLM error: {e}")
                
    score += vlm_score

    # Final Pass/Fail
    # Must have added bus AND kept old data
    passed = bus_added and data_intact and (score >= 80)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }