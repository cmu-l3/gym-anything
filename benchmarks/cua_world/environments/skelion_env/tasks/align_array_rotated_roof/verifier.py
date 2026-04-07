#!/usr/bin/env python3
"""
Verifier for align_array_rotated_roof task.
Validates the presence and exact geometric alignment of solar panel components
by analyzing the JSON output extracted by the SketchUp Ruby script.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_align_array_rotated_roof(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_rotation = metadata.get('expected_rotation_deg', 34)
    tolerance = metadata.get('tolerance_deg', 2)
    min_panels = metadata.get('min_panels', 10)

    # 1. Retrieve the evaluation JSON from the Windows container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\Users\\Docker\\AppData\\Local\\Temp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Criterion 1: File Validity & Anti-Gaming (10 pts)
    file_exists = result.get('file_exists', False)
    file_mod = result.get('file_modified_during_task', False)
    
    if file_exists and file_mod:
        score += 10
        feedback_parts.append("File exists and was modified during task")
    elif file_exists:
        feedback_parts.append("FAIL: File exists but was NOT modified during task (Stale/Pre-existing file)")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}
    else:
        return {"passed": False, "score": 0, "feedback": "Target SketchUp file was not saved."}

    # Criterion 2: Panel Presence (20 pts)
    panels_found = result.get('panels_found', False)
    panel_count = result.get('panel_count', 0)
    
    if panels_found and panel_count >= min_panels:
        score += 20
        feedback_parts.append(f"Found sufficient panels ({panel_count})")
    elif panels_found and panel_count > 0:
        score += 10
        feedback_parts.append(f"Found {panel_count} panels (partial credit, expected >= {min_panels})")
    else:
        feedback_parts.append("No component instances/panels found in model")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}
        
    # Criterion 3: Geometric Alignment Check (70 pts)
    rotations = result.get('rotations', [])
    errors = []
    
    for angle in rotations:
        # A component can be facing any of 4 orthogonal directions relative to the array.
        # So we evaluate modulo 90 degrees to compare alignment with the building grid.
        mod_angle = angle % 90
        mod_expected = expected_rotation % 90
        
        diff = (mod_angle - mod_expected) % 90
        err = min(diff, 90 - diff)
        errors.append(err)
        
    avg_err = sum(errors) / len(errors) if errors else 999
    
    if avg_err <= tolerance:
        score += 70
        feedback_parts.append(f"Alignment correct (Avg rotational error: {avg_err:.1f}°, within {tolerance}° tolerance)")
    elif avg_err <= tolerance + 5.0:
        score += 35
        feedback_parts.append(f"Alignment partially correct (Avg rotational error: {avg_err:.1f}°)")
    else:
        feedback_parts.append(f"Alignment incorrect (Avg error: {avg_err:.1f}°). Panels are likely aligned to global North/South instead of the building.")

    # Optional VLM verification for visual confirmation
    vlm_score = 0
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=3)
            final = get_final_screenshot(traj)
            if final:
                vlm_res = query_vlm(
                    images=frames + [final],
                    prompt="Verify if a grid of solar panels was placed on the roof of the building in SketchUp. Respond in JSON format: {\"panels_visible\": true/false}"
                )
                if vlm_res and vlm_res.get('parsed', {}).get('panels_visible'):
                    feedback_parts.append("VLM visual confirmation passed")
                else:
                    feedback_parts.append("VLM could not visually confirm panels")
        except Exception as e:
            logger.warning(f"VLM skipped/failed: {e}")
            
    # Success threshold: 80% (requires alignment to be at least partially correct and panels present)
    passed = score >= 80
    return {"passed": passed, "score": score, "feedback": " | ".join(feedback_parts)}