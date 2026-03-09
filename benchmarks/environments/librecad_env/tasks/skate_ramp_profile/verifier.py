#!/usr/bin/env python3
"""
Verifier for Skate Ramp Profile task.

This verifier reads the JSON result exported by the container.
The container's export script performs the actual DXF parsing using ezdxf.
The verifier evaluates the findings against the task requirements.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_skate_ramp_profile(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load result from container
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
    feedback = []
    
    # 2. Extract Data
    file_exists = result.get('file_exists', False)
    created_fresh = result.get('file_created_during_task', False)
    geo = result.get('geometry_analysis', {})
    
    # 3. Scoring Criteria
    
    # A. File Existence & Anti-Gaming (15 pts)
    if file_exists:
        if created_fresh:
            score += 15
            feedback.append("File saved successfully.")
        else:
            score += 5
            feedback.append("File exists but timestamp indicates it wasn't created during this task.")
    else:
        return {"passed": False, "score": 0, "feedback": "Output file not found."}

    # B. Layers (15 pts)
    if geo.get('layers_correct', False):
        score += 15
        feedback.append("Correct layers (TEMPLATE, COPING, DIMENSIONS) found.")
    else:
        found = geo.get('layers_found', [])
        feedback.append(f"Missing required layers. Found: {found}")

    # C. Transition Geometry (30 pts)
    arc = geo.get('transition_arc', {})
    if arc.get('found', False):
        score += 30
        feedback.append(f"Transition arc correct (R={arc['radius']:.1f}).")
    else:
        feedback.append("Transition arc (R1800) not found at correct coordinates on TEMPLATE layer.")

    # D. Coping Geometry (20 pts)
    coping = geo.get('coping_circle', {})
    if coping.get('found', False):
        score += 20
        feedback.append("Coping circle correct.")
    else:
        feedback.append("Coping circle (R30) not found at (1800,1800) on COPING layer.")

    # E. Enclosure Lines (10 pts)
    lines_count = geo.get('enclosure_lines', 0)
    if lines_count >= 2:
        score += 10
        feedback.append("Enclosure lines detected.")
    else:
        feedback.append("Deck/Enclosure lines missing or insufficient.")

    # F. Dimensions (10 pts)
    dims_count = geo.get('dimensions_count', 0)
    if dims_count >= 2:
        score += 10
        feedback.append("Dimensions added.")
    else:
        feedback.append("Insufficient dimensions (need at least 2).")

    # 4. VLM Verification (Supplementary / Tie-breaker)
    # We use VLM to confirm the drawing "looks" like a quarter pipe
    # This catches cases where geometry might be technically correct but visually garbage (rare)
    # or provides points if file parsing failed but work is visible.
    
    final_score = score
    passed = final_score >= 85
    
    # If the programmatic score is borderline or file checks failed but app was used,
    # we can peek at VLM. But for a strict CAD task, file parsing is king.
    # We'll stick to programmatic scoring for the pass/fail determination.
    
    return {
        "passed": passed,
        "score": final_score,
        "feedback": " ".join(feedback),
        "details": result
    }