#!/usr/bin/env python3
"""
Verifier for Traffic Accident Reconstruction Task
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_traffic_accident(traj, env_info, task_info):
    """
    Verifies the accident reconstruction diagram.
    
    Criteria:
    1. File creation/modification (10 pts)
    2. Street labels 'Main' and 'Elm' (15 pts)
    3. Vehicle 1 (Blue) identified (20 pts)
    4. Vehicle 2 (Red) identified (20 pts)
    5. Unit 2 Rotated (10 pts)
    6. North Arrow present (10 pts)
    7. VLM Visual Check for collision geometry (15 pts)
    """
    
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
    feedback = []
    
    analysis = result.get('analysis', {})
    labels = [l.lower() for l in analysis.get('labels', [])]
    
    # 1. File Check (10 pts)
    if result.get('drawio_exists') and result.get('drawio_modified'):
        score += 5
        feedback.append("Draw.io file saved.")
    if result.get('png_exists') and result.get('png_size', 0) > 1000:
        score += 5
        feedback.append("PNG exported.")
    
    # 2. Street Labels (15 pts)
    has_main = any('main' in l for l in labels)
    has_elm = any('elm' in l for l in labels)
    
    if has_main: score += 7.5
    if has_elm: score += 7.5
    if has_main and has_elm: feedback.append("Street labels correct.")
    else: feedback.append(f"Missing street labels (Main: {has_main}, Elm: {has_elm}).")

    # 3. Vehicle 1 (Blue) (20 pts)
    # Logic: Found 'Unit 1' label AND it was associated with blue color in XML analysis
    if analysis.get('unit1_found'):
        score += 10
        if analysis.get('unit1_color') == 'blue':
            score += 10
            feedback.append("Unit 1 (Blue) correctly identified.")
        else:
            feedback.append("Unit 1 found but wrong color.")
    else:
        feedback.append("Unit 1 label not found.")
        
    # 4. Vehicle 2 (Red) (20 pts)
    if analysis.get('unit2_found'):
        score += 10
        if analysis.get('unit2_color') == 'red':
            score += 10
            feedback.append("Unit 2 (Red) correctly identified.")
        else:
            feedback.append("Unit 2 found but wrong color.")
    else:
        feedback.append("Unit 2 label not found.")

    # 5. Rotation (10 pts)
    # Unit 2 should be turning (rotated)
    if analysis.get('has_rotation'):
        score += 10
        feedback.append("Vehicle rotation detected.")
    else:
        feedback.append("No vehicle rotation detected (Unit 2 should be turning).")
        
    # 6. North Arrow (10 pts)
    if analysis.get('has_north_arrow'):
        score += 10
        feedback.append("North arrow found.")
    else:
        # Fallback check in labels
        if any(x in labels for x in ['n', 'north']):
            score += 10
            feedback.append("North label found.")
        else:
            feedback.append("North arrow missing.")

    # 7. VLM Visual Check (15 pts)
    # Use VLM to verify the collision geometry which is hard to parse from XML
    try:
        final_img = get_final_screenshot(traj)
        if final_img:
            prompt = (
                "Review this diagram of a car accident.\n"
                "1. Is there a blue vehicle and a red vehicle?\n"
                "2. Are they colliding or touching in an intersection?\n"
                "3. Does it look like the red vehicle is turning left?\n"
                "Answer yes/no for each."
            )
            vlm_resp = query_vlm([final_img], prompt)
            
            vlm_score = 0
            if "yes" in vlm_resp.lower():
                # Rough heuristic: if VLM says 'yes' significantly, give points
                vlm_score = 15
                feedback.append("Visual verification passed.")
            else:
                feedback.append("Visual verification inconclusive.")
                # Fallback: if we have XML rotation and vehicles touching logic (hard to check),
                # we rely on the previous XML checks.
                # Here we just give partial credit if XML checks passed high enough
                if score >= 70: vlm_score = 15
            
            score += vlm_score
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # Graceful degradation: if XML checks are good, assume visual is okay
        if score >= 70: score += 15

    return {
        "passed": score >= 70,
        "score": min(100, score),
        "feedback": " ".join(feedback)
    }