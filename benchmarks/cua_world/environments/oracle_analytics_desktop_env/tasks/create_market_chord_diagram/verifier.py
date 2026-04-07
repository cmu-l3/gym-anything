#!/usr/bin/env python3
"""
Verifier for Oracle Analytics Desktop Task: create_market_chord_diagram
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_market_chord_diagram(traj, env_info, task_info):
    """
    Verifies that the agent created a Chord Diagram in Oracle Analytics Desktop.
    
    Criteria:
    1. Workbook 'Market_Chord_Analysis.dva' saved successfully.
    2. File created/modified during task execution.
    3. Metadata inspection confirms 'chord' viz type and correct columns.
    4. VLM verification of the visual output (Circular layout, labels).
    """
    
    # Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    score = 0
    max_score = 100
    feedback_parts = []
    
    # 1. Retrieve Programmatic Results
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # The Powershell script saves to C:\workspace\tasks\...\task_result.json
        # which maps to /workspace/tasks/... inside the container (assuming windows container mount)
        # OR we copy from the specific path.
        # Based on env setup, the windows path C:\workspace\tasks maps to /workspace/tasks
        
        copy_from_env("/workspace/tasks/create_market_chord_diagram/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result JSON: {e}")
        result = {}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    # 2. Evaluate Programmatic Criteria (60 points)
    
    # File Existence (20 pts)
    if result.get('output_exists', False):
        score += 20
        feedback_parts.append("Workbook file saved.")
    else:
        feedback_parts.append("Workbook file NOT found.")
        
    # Timestamp Check (10 pts)
    if result.get('file_created_during_task', False):
        score += 10
        feedback_parts.append("File created during session.")
    elif result.get('output_exists', False):
        feedback_parts.append("File exists but timestamp indicates it wasn't modified.")
        
    # Metadata Check (30 pts)
    viz_type_ok = result.get('viz_type_found_in_metadata', False)
    cols_ok = result.get('columns_found_in_metadata', False)
    
    if viz_type_ok:
        score += 15
        feedback_parts.append("Chord visualization type detected in metadata.")
    else:
        feedback_parts.append("Could not confirm Chord viz type in file metadata.")
        
    if cols_ok:
        score += 15
        feedback_parts.append("Correct data columns detected in metadata.")
        
    # 3. VLM Verification (40 points)
    # We use trajectory frames to ensure the agent actually worked, plus final frame for result.
    
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    
    if not final_frame:
        feedback_parts.append("No screenshots available for VLM verification.")
    else:
        # Prompt for VLM
        prompt = """
        You are verifying an Oracle Analytics Desktop task.
        The goal is to create a 'Chord Diagram' showing sales flow between 'Customer Segment' and 'Product Category'.
        
        Please analyze the provided screenshots (trajectory and final state) and answer:
        1. Is a circular Chord Diagram visible? (It looks like a circle with curved paths connecting nodes on the rim).
        2. Are the labels 'Customer Segment' (e.g. Consumer, Corporate) and 'Product Category' (e.g. Furniture, Technology) visible?
        3. Is the title 'Segment-Category Sales Flow' visible?
        4. Does the UI look like Oracle Analytics Desktop (modern BI tool interface)?
        
        Return a score from 0 to 40 based on these criteria.
        """
        
        vlm_response = query_vlm(
            prompt=prompt,
            images=frames + [final_frame]
        )
        
        # Heuristic parsing of VLM result - assuming gym_anything returns a dict with 'score' or we parse text
        # Since query_vlm returns a structured object usually, we'll try to extract specific signals if available,
        # otherwise we might need a trusted evaluator pattern.
        # For this implementation, let's assume query_vlm returns a dict with 'parsed' content.
        
        vlm_score = 0
        if vlm_response.get("success"):
            # Simple keyword check in reasoning if structured parsing fails, 
            # or rely on an explicit score field if the prompt asked for JSON.
            # Let's refine the prompt for JSON to be safe.
            json_prompt = prompt + "\nRespond in JSON: {'is_chord': bool, 'labels_visible': bool, 'title_correct': bool, 'ui_match': bool}"
            
            vlm_json = query_vlm(prompt=json_prompt, images=[final_frame])
            parsed = vlm_json.get('parsed', {})
            
            if parsed.get('is_chord'): vlm_score += 15
            if parsed.get('labels_visible'): vlm_score += 10
            if parsed.get('title_correct'): vlm_score += 10
            if parsed.get('ui_match'): vlm_score += 5
            
            feedback_parts.append(f"VLM Visual Verification: {vlm_score}/40")
        else:
            feedback_parts.append("VLM verification failed to run.")
            
        score += vlm_score

    # Final tally
    passed = (score >= 70) and result.get('output_exists', False) and result.get('viz_type_found_in_metadata', False)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }