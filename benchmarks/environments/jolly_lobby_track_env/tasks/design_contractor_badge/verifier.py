#!/usr/bin/env python3
"""
Verifier for design_contractor_badge task.

CRITERIA:
1. File Creation (40 pts): A file named 'Contractor_Badge' (any ext) exists and was created during the task.
2. Title Text (20 pts): The file contains the string "CONTRACTOR".
3. Fields (40 pts total): 
   - Company (15 pts)
   - Name (15 pts)
   - Date (10 pts)
4. VLM Verification (Penalty/Bonus): Verifies the agent actually used the designer if file analysis is ambiguous.

Pass Threshold: 80 points (Must create file + Title + at least one Field).
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_design_contractor_badge(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON
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

    score = 0
    feedback_parts = []
    
    # 1. File Existence and Timestamp Check
    found_path = result.get("found_file_path", "")
    file_mtime = result.get("file_mtime", 0)
    task_start = result.get("task_start", 0)
    
    file_created = False
    if found_path and file_mtime > task_start:
        file_created = True
        score += 40
        feedback_parts.append(f"File created: {os.path.basename(found_path)}")
    elif found_path:
        feedback_parts.append("File found but modification time is too old (pre-existing?)")
    else:
        feedback_parts.append("No 'Contractor_Badge' file found")
        # Fail immediately if no file
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No output file found. " + " | ".join(feedback_parts)
        }

    # 2. Content Check (Strings)
    content = result.get("content_check", {})
    
    # Title
    if content.get("has_title_contractor"):
        score += 20
        feedback_parts.append("Title 'CONTRACTOR' found")
    else:
        feedback_parts.append("Missing title 'CONTRACTOR'")

    # Fields
    fields_found = 0
    if content.get("has_field_company"):
        score += 15
        fields_found += 1
        feedback_parts.append("Company field found")
    if content.get("has_field_name"):
        score += 15
        fields_found += 1
        feedback_parts.append("Name field found")
    if content.get("has_field_date"):
        score += 10
        fields_found += 1
        feedback_parts.append("Date field found")
        
    if fields_found == 0:
        feedback_parts.append("No data fields detected")

    # 3. VLM Verification (Safety Check)
    # If the file checks passed but score is borderline or we want to confirm visual elements
    # Or if file checks were inconclusive (binary format obscuring strings)
    
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        vlm_prompt = """
        Review these screenshots of a user designing a badge in Lobby Track.
        1. Did the user open a Badge Designer window?
        2. Is there a badge visible with the large text "CONTRACTOR"?
        3. Did the user save the file?
        
        Answer JSON: {"designer_opened": bool, "contractor_text_visible": bool, "save_action": bool}
        """
        try:
            vlm_resp = query_vlm(images=frames, prompt=vlm_prompt)
            vlm_data = vlm_resp.get("parsed", {})
            
            # If file content check failed (maybe due to binary format) but VLM sees it, verify visually
            if not content.get("has_title_contractor") and vlm_data.get("contractor_text_visible"):
                score += 20
                feedback_parts.append("VLM confirmed 'CONTRACTOR' text visually (binary file)")
                
            # If file wasn't found but VLM sees save action, give partial hint
            if not file_created and vlm_data.get("save_action"):
                feedback_parts.append("VLM saw save action, but file not found on disk (check path)")
                
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")

    # Final Score Calculation
    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }