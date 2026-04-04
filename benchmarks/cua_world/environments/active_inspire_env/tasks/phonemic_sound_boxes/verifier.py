#!/usr/bin/env python3
"""
Verifier for phonemic_sound_boxes task.

Scoring (100 points total):
1. Programmatic Checks (60 points):
   - File exists & Valid Format: 10 pts
   - Created during task: 5 pts
   - "Sound Boxes" title text found: 10 pts
   - Rectangle count >= 7 (3 for cat + 4 for frog): 20 pts
   - Circle count >= 5 (counters): 10 pts
   - Images imported >= 2: 5 pts

2. VLM Verification (40 points):
   - Layout check: Boxes positioned under images?
   - Counter check: Are the counters red?
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_phonemic_sound_boxes(traj, env_info, task_info):
    """
    Verify the Sound Boxes flipchart creation task.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy missing"}

    # 1. Load Programmatic Results
    try:
        tmp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp_path = tmp_file.name
        tmp_file.close()
        
        copy_from_env('/tmp/task_result.json', tmp_path)
        
        with open(tmp_path, 'r') as f:
            result = json.load(f)
            
        os.unlink(tmp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task results: {str(e)}"}

    score = 0
    feedback = []

    # --- Programmatic Scoring (60 pts max) ---

    # File Existence (10)
    if result.get('file_found') and result.get('file_valid'):
        score += 10
        feedback.append("File created successfully.")
    else:
        return {"passed": False, "score": 0, "feedback": "No valid flipchart file found."}

    # Timestamp (5)
    if result.get('created_during_task'):
        score += 5
    else:
        feedback.append("Warning: File timestamp suggests it wasn't created during this run.")

    # Title Text (10)
    if result.get('has_title_text'):
        score += 10
        feedback.append("Title 'Sound Boxes' found.")
    else:
        feedback.append("Missing title 'Sound Boxes'.")

    # Rectangle Count (20) - Expecting 3 (cat) + 4 (frog) = 7
    rects = result.get('rect_count', 0)
    if rects >= 7:
        score += 20
        feedback.append(f"Found {rects} boxes (met requirement >= 7).")
    elif rects >= 3:
        score += 10
        feedback.append(f"Found {rects} boxes (partial credit, needed 7).")
    else:
        feedback.append(f"Insufficient boxes found ({rects}).")

    # Circle Count (10) - Expecting 5 counters
    circles = result.get('circle_count', 0)
    if circles >= 5:
        score += 10
        feedback.append(f"Found {circles} counters (met requirement >= 5).")
    elif circles >= 1:
        score += 5
        feedback.append(f"Found {circles} counters (partial credit, needed 5).")
    else:
        feedback.append(f"No counters (circles) found.")

    # Image Count (5) - Expecting 2 imported images
    images = result.get('image_count', 0)
    if images >= 2:
        score += 5
        feedback.append(f"Found {images} imported images.")
    elif images == 1:
        score += 2
        feedback.append(f"Only 1 image found.")
    else:
        feedback.append("No imported images found.")


    # --- VLM Verification (40 pts max) ---
    vlm_score = 0
    
    # We need the final screenshot to check layout
    # The framework should provide a way to get the screenshot path from the container 
    # or the trajectory. Assuming 'traj' contains frames or we can get the screenshot 
    # from the export script via 'copy_from_env'.
    
    # Try to fetch the screenshot captured by export_result.sh
    try:
        screenshot_tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        screenshot_path = screenshot_tmp.name
        screenshot_tmp.close()
        copy_from_env('/tmp/task_end.png', screenshot_path)
        
        if query_vlm:
            prompt = """
            Analyze this screenshot of an educational software (ActivInspire).
            The user should have created a "Sound Boxes" activity.
            
            Look for:
            1. Layout: Are there empty square boxes positioned directly UNDER images?
               - Specifically, 3 boxes under a Cat image.
               - And 4 boxes under a Frog image.
            2. Counters: Are there red circular chips visible on the screen?
            
            Return JSON:
            {
                "layout_boxes_under_images": boolean,
                "counters_are_red": boolean,
                "counters_visible": boolean
            }
            """
            
            vlm_resp = query_vlm(image=screenshot_path, prompt=prompt)
            parsed = vlm_resp.get('parsed', {})
            
            if parsed.get('layout_boxes_under_images'):
                vlm_score += 20
                feedback.append("VLM confirmed boxes are positioned under images.")
            
            if parsed.get('counters_visible'):
                vlm_score += 10
                feedback.append("VLM confirmed counters are visible.")
                
                if parsed.get('counters_are_red'):
                    vlm_score += 10
                    feedback.append("VLM confirmed counters are red.")
                else:
                    feedback.append("VLM did not verify counters are red.")
            else:
                feedback.append("VLM did not see counters.")

        os.unlink(screenshot_path)

    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        feedback.append("Visual verification skipped due to error.")

    total_score = score + vlm_score
    passed = total_score >= 70
    
    return {
        "passed": passed,
        "score": total_score,
        "feedback": " | ".join(feedback)
    }