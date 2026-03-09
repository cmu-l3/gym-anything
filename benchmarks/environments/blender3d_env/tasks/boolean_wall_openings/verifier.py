#!/usr/bin/env python3
"""
Verifier for boolean_wall_openings task.

CRITERIA:
1. Boolean cuts applied (Face count increased significantly) (30 pts)
2. Modifiers applied cleanly (No unapplied boolean modifiers left) (15 pts)
3. Cutters hidden or deleted (Cleanup) (15 pts)
4. Render output exists and is valid (25 pts)
5. Blend file saved and modified (15 pts)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_boolean_wall_openings(traj, env_info, task_info):
    """
    Verify boolean operations were performed, applied, and scene cleaned up.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
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

    # Extract data
    scene = result.get('scene_analysis', {})
    blend_exists = result.get('blend_exists', False)
    file_modified = result.get('file_modified_during_task', False)
    render_exists = result.get('render_exists', False)
    render_size = result.get('render_size', 0)
    
    # Gate: If nothing saved, 0 points
    if not blend_exists and not render_exists:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No output files (blend or render) found."
        }

    score = 0
    feedback = []

    # 1. Check Face Count (Did boolean happen?) (30 pts)
    # A simple cube has 6 faces. 
    # One boolean difference with a cube usually adds internal faces.
    # 3 cuts should result in significantly more faces (>15).
    current_faces = scene.get('face_count', 0)
    initial_faces = result.get('initial_face_count', 6)
    
    # Threshold: If face count increased by at least 10, booleans likely worked
    if current_faces >= 15:
        score += 30
        feedback.append(f"Geometry modified (faces: {current_faces})")
    elif current_faces > initial_faces:
        score += 15
        feedback.append(f"Geometry slightly modified (faces: {current_faces}), possibly incomplete cuts")
    else:
        feedback.append("Geometry unchanged (no holes cut)")

    # 2. Check Unapplied Modifiers (15 pts)
    # Task requires Applying modifiers
    unapplied = scene.get('unapplied_boolean_count', 0)
    if scene.get('wall_found') and unapplied == 0:
        # Only award if booleans actually happened (check face count)
        if current_faces >= 15:
            score += 15
            feedback.append("Modifiers applied cleanly")
        else:
            feedback.append("No modifiers found (but no geometry change either)")
    elif unapplied > 0:
        feedback.append(f"{unapplied} Boolean modifiers left unapplied")

    # 3. Cleanup: Cutters hidden/deleted (15 pts)
    cutters = scene.get('cutters_status', {})
    cutters_clean = 0
    total_cutters = 3
    
    for name, status in cutters.items():
        if not status.get('exists'):
            cutters_clean += 1 # Deleted is good
        elif status.get('hide_viewport') and status.get('hide_render'):
            cutters_clean += 1 # Hidden is good
            
    if cutters_clean == total_cutters:
        score += 15
        feedback.append("All cutters hidden/deleted")
    elif cutters_clean > 0:
        points = int(15 * (cutters_clean / total_cutters))
        score += points
        feedback.append(f"{cutters_clean}/{total_cutters} cutters cleaned up")
    else:
        feedback.append("Cutters still visible")

    # 4. Render Output (25 pts)
    if render_exists and render_size > 10000: # >10KB
        score += 25
        feedback.append("Render output valid")
    elif render_exists:
        score += 10
        feedback.append("Render file exists but small")
    else:
        feedback.append("No render output")

    # 5. Blend File Saved (15 pts)
    if blend_exists and file_modified and scene.get('valid_file'):
        score += 15
        feedback.append("Blend file saved")
    elif blend_exists:
        feedback.append("Blend file exists but timestamp suggests no save")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback)
    }