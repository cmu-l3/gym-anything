#!/usr/bin/env python3
"""
Verifier for handheld_camera_shake task.

Criteria:
1. File saved and modified (15 pts)
2. Camera object has animation/Action data (20 pts)
3. X Rotation has Noise Modifier (25 pts)
4. Z Rotation has Noise Modifier (25 pts)
5. Noise parameters are realistic (strength 0.005-0.2, scale 2-100) (15 pts)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_handheld_camera_shake(traj, env_info, task_info):
    """
    Verify procedural noise modifiers on camera rotation.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Metadata thresholds
    meta = task_info.get('metadata', {})
    min_str = meta.get('min_strength', 0.005)
    max_str = meta.get('max_strength', 0.2)
    min_scale = meta.get('min_scale', 2.0)
    max_scale = meta.get('max_scale', 100.0)

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

    score = 0
    feedback = []
    
    # 1. File checks (15 pts)
    if result.get('output_exists') and result.get('file_modified'):
        score += 15
        feedback.append("File saved successfully")
    elif result.get('output_exists'):
        # Exists but timestamp dubious?
        score += 5
        feedback.append("File exists but timestamp check failed")
    else:
        return {"passed": False, "score": 0, "feedback": "Output file not found"}

    analysis = result.get('analysis', {})
    
    # 2. Action Data (20 pts)
    if analysis.get('camera_found') and analysis.get('action_found'):
        score += 20
        feedback.append("Camera animation data found")
    else:
        feedback.append("No animation data on Camera")
        return {"passed": False, "score": score, "feedback": ". ".join(feedback)}

    # 3. Modifiers Check (25 pts each axis)
    modifiers = analysis.get('modifiers', [])
    
    has_x_noise = False
    has_z_noise = False
    params_ok = True
    param_feedback = []

    for mod in modifiers:
        if mod.get('type') == 'NOISE':
            axis = mod.get('axis')
            strength = mod.get('strength', 0)
            scale = mod.get('scale', 0)
            
            # Check realism
            axis_params_ok = True
            if not (min_str <= strength <= max_str):
                axis_params_ok = False
                param_feedback.append(f"{axis} Strength {strength:.3f} outside realistic range ({min_str}-{max_str})")
            
            if not (min_scale <= scale <= max_scale):
                axis_params_ok = False
                param_feedback.append(f"{axis} Scale {scale:.1f} outside realistic range ({min_scale}-{max_scale})")

            if not axis_params_ok:
                params_ok = False

            if axis == 'X':
                has_x_noise = True
            elif axis == 'Z':
                has_z_noise = True

    if has_x_noise:
        score += 25
        feedback.append("X-axis Noise modifier active")
    else:
        feedback.append("Missing Noise on X-axis")

    if has_z_noise:
        score += 25
        feedback.append("Z-axis Noise modifier active")
    else:
        feedback.append("Missing Noise on Z-axis")

    # 4. Parameters Check (15 pts)
    # Only award if at least one noise modifier exists
    if (has_x_noise or has_z_noise):
        if params_ok:
            score += 15
            feedback.append("Noise parameters realistic")
        else:
            feedback.append("Noise parameters unrealistic: " + "; ".join(param_feedback))

    passed = score >= 70 and has_x_noise and has_z_noise

    return {
        "passed": passed,
        "score": score,
        "feedback": ". ".join(feedback)
    }