#!/usr/bin/env python3
"""
Verifier for record_wool_clip_harvest task.

Verification Strategy:
1. UI Dump Analysis (Primary):
   - Check if a log entry exists in the list with "Harvest" and the correct date/name snippets.
   - Since we cannot easily query an internal database on Android without root/sqlite3 access 
     in the specific app sandbox, checking the UI list view is the standard approach.

2. VLM Trajectory Analysis (Secondary):
   - Verify the agent actually typed the specific notes and date.
   - Verify the "Quantity" and "Unit" fields were filled correctly (which might not show on the main list view).
"""

import os
import sys
import json
import logging
import tempfile
import xml.etree.ElementTree as ET
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_record_wool_clip_harvest(traj, env_info, task_info):
    """
    Verifies that the wool clip harvest log was created correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_strings = metadata.get('expected_strings', [])
    log_details = metadata.get('log_details', {})
    
    score = 0
    feedback_parts = []
    
    # Temporary files for artifacts
    temp_xml = tempfile.NamedTemporaryFile(delete=False, suffix='.xml')
    temp_xml_path = temp_xml.name
    temp_xml.close()

    try:
        # =========================================================
        # 1. UI Hierarchy Verification (40 Points)
        # =========================================================
        try:
            copy_from_env("/sdcard/ui_dump.xml", temp_xml_path)
            
            # Parse XML
            tree = ET.parse(temp_xml_path)
            root = tree.getroot()
            xml_content = ET.tostring(root, encoding='unicode', method='text')
            
            # Check for key indicators in the UI
            # The list view usually shows the Log Type ("Harvest") and potentially date or part of notes/name
            
            harvest_found = "Harvest" in xml_content
            
            # Notes usually become the "name" of the log if no name is explicitly provided, 
            # or appear in the preview. We check for key phrases.
            romney_found = "Romney" in xml_content
            wool_found = "Wool" in xml_content
            
            if harvest_found:
                score += 20
                feedback_parts.append("UI: 'Harvest' log type visible")
            else:
                feedback_parts.append("UI: 'Harvest' log type NOT found in list")

            if romney_found or wool_found:
                score += 20
                feedback_parts.append("UI: Log content/notes visible in list")
            else:
                feedback_parts.append("UI: Log details not visible in list")

        except Exception as e:
            logger.error(f"UI Dump verification failed: {e}")
            feedback_parts.append(f"UI verification failed: {str(e)}")

        # =========================================================
        # 2. VLM Trajectory Verification (60 Points)
        # =========================================================
        # We need to verify details that might be hidden in the list view (like specific Quantity/Date)
        
        frames = sample_trajectory_frames(traj, n=8)
        final_frame = get_final_screenshot(traj)
        
        if frames:
            prompt = f"""
            You are verifying an agent's performance in the farmOS Field Kit app.
            The agent was tasked with creating a specific Harvest log.
            
            Target Details:
            - Type: Harvest
            - Date: May 12, 2024
            - Notes: Must mention 'Romney', 'vegetable matter', 'paper sacks'
            - Quantity: 98
            - Unit: lbs
            - Label: Greasy Wool
            
            Review the screenshots to answer:
            1. Did the agent select 'Harvest' as the Log Type?
            2. Did the agent set the Date to May 12, 2024?
            3. Did the agent enter the specific notes about 'Romney' sheep?
            4. Did the agent enter Quantity '98' with unit 'lbs'?
            5. Did the agent save the log (click checkmark/back)?
            
            Return JSON:
            {{
                "log_type_correct": boolean,
                "date_correct": boolean,
                "notes_entered": boolean,
                "quantity_correct": boolean,
                "saved_successfully": boolean
            }}
            """
            
            vlm_result = query_vlm(
                images=frames + [final_frame], 
                prompt=prompt
            )
            
            if vlm_result.get("success"):
                parsed = vlm_result.get("parsed", {})
                
                if parsed.get("log_type_correct"):
                    score += 10
                    feedback_parts.append("VLM: Log Type 'Harvest' confirmed")
                
                if parsed.get("date_correct"):
                    score += 10
                    feedback_parts.append("VLM: Date set to May 12, 2024")
                
                if parsed.get("notes_entered"):
                    score += 20
                    feedback_parts.append("VLM: Detailed notes entered correctly")
                
                if parsed.get("quantity_correct"):
                    score += 10
                    feedback_parts.append("VLM: Quantity '98 lbs' confirmed")
                
                if parsed.get("saved_successfully"):
                    score += 10
                    feedback_parts.append("VLM: Log saved successfully")
            else:
                feedback_parts.append("VLM verification failed to process images")

    finally:
        if os.path.exists(temp_xml_path):
            os.remove(temp_xml_path)

    # Final Pass Determination
    # Pass if score >= 80 (allows small VLM misses if UI dump is solid, or vice versa)
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }