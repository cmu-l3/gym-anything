#!/usr/bin/env python3
"""
Verifier for record_daily_egg_harvest task.

Strategy:
1. UI State Verification (40 pts):
   - Checks if a log with title "Daily Egg Collection - Red Barn" exists in the final list.
   - Checks if "Harvest" type is visible.
   
2. VLM Trajectory Verification (60 pts):
   - Since the final list view might not show Quantity/Notes details, we use VLM 
     on trajectory frames to verify the agent actually entered the correct data 
     (22, dozen, specific notes) during the creation process.
"""

import json
import os
import sys
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_egg_harvest(traj, env_info, task_info):
    """
    Verifies that the daily egg harvest log was created with correct details.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_title = metadata.get('expected_title', "Daily Egg Collection - Red Barn")
    expected_notes_snippet = metadata.get('expected_notes_snippet', "oyster shell hopper")

    score = 0
    feedback_parts = []
    
    # =========================================================
    # PART 1: UI State Verification (Final State) - 40 Points
    # =========================================================
    try:
        # Retrieve result JSON
        temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/sdcard/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
        os.unlink(temp_json.name)
        
        # Check Title
        if result_data.get("title_found_in_ui", False):
            score += 25
            feedback_parts.append(f"SUCCESS: Log title '{expected_title}' found in list.")
        else:
            feedback_parts.append(f"FAIL: Log title '{expected_title}' NOT found in final list.")

        # Check Type
        if result_data.get("type_found_in_ui", False):
            score += 15
            feedback_parts.append("SUCCESS: 'Harvest' log type indication found.")
        else:
            feedback_parts.append("FAIL: 'Harvest' type text not found in UI (or log not created).")
            
    except Exception as e:
        logger.error(f"Error reading task result: {e}")
        feedback_parts.append("FAIL: Could not verify final UI state (export failed).")

    # =========================================================
    # PART 2: VLM Trajectory Verification - 60 Points
    # =========================================================
    # We need to verify the inputs (Quantity: 22, Unit: dozen, Notes content)
    # These are likely hidden in the final list view, so we look at the workflow.
    
    frames = sample_trajectory_frames(traj, n=8)  # Sample frames to catch data entry
    
    prompt = f"""
    You are verifying an Android app automation task.
    The agent was supposed to create a 'Harvest' log in farmOS Field Kit with specific details.
    
    Review the sequence of screenshots and answer the following questions:
    
    1. Did the agent select "Harvest" as the log type? (It might default to Activity, so look for a change or Harvest being selected).
    2. Did the agent enter the quantity "22"?
    3. Did the agent enter the unit "dozen" (or "dozens")?
    4. Did the agent enter notes containing "{expected_notes_snippet}"?
    5. Did the agent save the log (click a checkmark or back arrow)?
    
    Return a JSON object with boolean values:
    {{
        "harvest_selected": true/false,
        "quantity_correct": true/false,
        "unit_correct": true/false,
        "notes_entered": true/false,
        "saved": true/false
    }}
    """
    
    try:
        vlm_response = query_vlm(images=frames, prompt=prompt)
        
        if vlm_response.get("success"):
            parsed = vlm_response.get("parsed", {})
            
            # Scoring VLM findings
            if parsed.get("harvest_selected", False):
                score += 10
                feedback_parts.append("VLM: Confirmed 'Harvest' type selected.")
            else:
                feedback_parts.append("VLM: Could not confirm 'Harvest' type selection.")

            if parsed.get("quantity_correct", False):
                score += 15
                feedback_parts.append("VLM: Confirmed Quantity '22' entered.")
            else:
                feedback_parts.append("VLM: Could not confirm Quantity '22'.")

            if parsed.get("unit_correct", False):
                score += 10
                feedback_parts.append("VLM: Confirmed Unit 'dozen' entered.")
            else:
                feedback_parts.append("VLM: Could not confirm Unit 'dozen'.")

            if parsed.get("notes_entered", False):
                score += 15
                feedback_parts.append(f"VLM: Confirmed notes containing '{expected_notes_snippet}'.")
            else:
                feedback_parts.append("VLM: Could not confirm specific notes text.")
                
            if parsed.get("saved", False):
                score += 10
                feedback_parts.append("VLM: Confirmed save action.")
            else:
                feedback_parts.append("VLM: Could not confirm save action.")
        else:
            feedback_parts.append("VLM: Analysis failed, cannot verify data entry steps.")
            
    except Exception as e:
        logger.error(f"VLM error: {e}")
        feedback_parts.append(f"VLM: Verification error: {e}")

    # =========================================================
    # Final Decision
    # =========================================================
    passed = score >= 90  # High threshold because data accuracy is critical for records
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }