#!/usr/bin/env python3
"""
Verifier for configure_exoskeleton_ankle_biomechanics task.

Parses the Webots world file to extract the HingeJointParameters and PositionSensor
resolution for the Ankle and Knee joints, scoring them against biomechanical reference values.
"""

import json
import tempfile
import os
import logging
import math

logger = logging.getLogger(__name__)

def extract_block(content, start_idx):
    """Extracts a brace-enclosed block from content starting at start_idx."""
    start_brace = content.find('{', start_idx)
    if start_brace == -1:
        return ""
    
    depth = 0
    end_brace = -1
    for i in range(start_brace, len(content)):
        if content[i] == '{':
            depth += 1
        elif content[i] == '}':
            depth -= 1
            if depth == 0:
                end_brace = i
                break
                
    if end_brace != -1:
        return content[start_brace:end_brace+1]
    return ""

def get_joint_params(wbt_content, joint_def):
    """Finds the HingeJointParameters block for a given joint DEF and extracts properties."""
    idx = wbt_content.find(joint_def)
    if idx == -1:
        return {}
        
    param_idx = wbt_content.find('HingeJointParameters', idx)
    if param_idx == -1:
        return {}
        
    block = extract_block(wbt_content, param_idx)
    
    params = {}
    for param in ['minStop', 'maxStop', 'springConstant', 'dampingConstant']:
        import re
        m = re.search(rf'{param}\s+([-\d.]+)', block)
        if m:
            params[param] = float(m.group(1))
    return params

def get_sensor_resolution(wbt_content, sensor_name):
    """Finds the resolution field associated with a specific sensor name."""
    idx = wbt_content.find(f'"{sensor_name}"')
    if idx == -1:
        return None
        
    # Search backwards and forwards within a small window to find resolution
    window = wbt_content[max(0, idx-100):min(len(wbt_content), idx+100)]
    import re
    m = re.search(r'resolution\s+([-\d.]+)', window)
    if m:
        return float(m.group(1))
    return None

def verify_configure_exoskeleton_ankle_biomechanics(traj, env_info, task_info):
    """Verifies that the HingeJointParameters and sensor resolution were correctly set."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})
    output_path = metadata.get('output_path', '/home/ga/Desktop/exoskeleton_biomechanics.wbt')
    
    # Read export result
    export_result = {}
    try:
        res_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        res_file.close()
        copy_from_env('/tmp/exoskeleton_result.json', res_file.name)
        with open(res_file.name) as f:
            export_result = json.load(f)
        os.unlink(res_file.name)
    except Exception:
        pass

    score = 0
    feedback_parts = []
    
    if export_result.get('file_exists') and export_result.get('file_modified_during_task'):
        score += 10
        feedback_parts.append("World file properly saved")
    elif export_result.get('file_exists'):
        score += 5
        feedback_parts.append("World file found, but modification timestamp check failed")
    else:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Output file not found at {output_path}. Must save using File > Save World As."
        }

    # Copy and read the .wbt file
    wbt_file = tempfile.NamedTemporaryFile(delete=False, suffix='.wbt')
    wbt_file.close()
    wbt_content = ""

    try:
        copy_from_env(output_path, wbt_file.name)
        with open(wbt_file.name, 'r', errors='replace') as f:
            wbt_content = f.read()
        os.unlink(wbt_file.name)
    except Exception as e:
        logger.warning(f"Could not copy .wbt file: {e}")
        try: os.unlink(wbt_file.name)
        except Exception: pass

    if not wbt_content or len(wbt_content) < 100:
        return {"passed": False, "score": score, "feedback": "Saved world file is empty or corrupted."}

    # Extract parameters
    ankle_params = get_joint_params(wbt_content, 'DEF ANKLE_JOINT')
    knee_params = get_joint_params(wbt_content, 'DEF KNEE_JOINT')
    ankle_res = get_sensor_resolution(wbt_content, 'ankle_sensor')

    # Tolerances
    tol_angle = metadata.get('tolerances', {}).get('angle', 0.02)
    tol_imp = metadata.get('tolerances', {}).get('impedance_percent', 0.05)

    ankle_rom_correct = 0
    ankle_imp_correct = 0

    # Evaluate Ankle ROM Constraints (10 pts each)
    if 'minStop' in ankle_params and math.isclose(ankle_params['minStop'], metadata['expected_ankle_min_stop'], abs_tol=tol_angle):
        score += 10
        ankle_rom_correct += 1
        feedback_parts.append("Ankle minStop correct")
    else:
        feedback_parts.append(f"Ankle minStop incorrect or missing (expected {metadata['expected_ankle_min_stop']})")

    if 'maxStop' in ankle_params and math.isclose(ankle_params['maxStop'], metadata['expected_ankle_max_stop'], abs_tol=tol_angle):
        score += 10
        ankle_rom_correct += 1
        feedback_parts.append("Ankle maxStop correct")
    else:
        feedback_parts.append(f"Ankle maxStop incorrect or missing (expected {metadata['expected_ankle_max_stop']})")

    # Evaluate Ankle Impedance (10 pts each)
    if 'springConstant' in ankle_params and math.isclose(ankle_params['springConstant'], metadata['expected_ankle_spring'], rel_tol=tol_imp):
        score += 10
        ankle_imp_correct += 1
        feedback_parts.append("Ankle springConstant correct")
    else:
        feedback_parts.append(f"Ankle springConstant incorrect or missing (expected {metadata['expected_ankle_spring']})")

    if 'dampingConstant' in ankle_params and math.isclose(ankle_params['dampingConstant'], metadata['expected_ankle_damping'], rel_tol=tol_imp):
        score += 10
        ankle_imp_correct += 1
        feedback_parts.append("Ankle dampingConstant correct")
    else:
        feedback_parts.append(f"Ankle dampingConstant incorrect or missing (expected {metadata['expected_ankle_damping']})")

    # Evaluate Ankle Sensor Resolution (15 pts)
    if ankle_res is not None and math.isclose(ankle_res, metadata['expected_ankle_resolution'], rel_tol=0.1):
        score += 15
        feedback_parts.append("Ankle sensor resolution correct")
    else:
        feedback_parts.append(f"Ankle sensor resolution incorrect or missing (expected {metadata['expected_ankle_resolution']})")

    # Evaluate Knee ROM Constraints (10 pts each)
    if 'minStop' in knee_params and math.isclose(knee_params['minStop'], metadata['expected_knee_min_stop'], abs_tol=tol_angle):
        score += 10
        feedback_parts.append("Knee minStop correct")
    else:
        feedback_parts.append(f"Knee minStop incorrect or missing (expected {metadata['expected_knee_min_stop']})")

    if 'maxStop' in knee_params and math.isclose(knee_params['maxStop'], metadata['expected_knee_max_stop'], abs_tol=tol_angle):
        score += 10
        feedback_parts.append("Knee maxStop correct")
    else:
        feedback_parts.append(f"Knee maxStop incorrect or missing (expected {metadata['expected_knee_max_stop']})")

    # Evaluate Knee Damping (15 pts)
    if 'dampingConstant' in knee_params and math.isclose(knee_params['dampingConstant'], metadata['expected_knee_damping'], rel_tol=tol_imp):
        score += 15
        feedback_parts.append("Knee dampingConstant correct")
    else:
        feedback_parts.append(f"Knee dampingConstant incorrect or missing (expected {metadata['expected_knee_damping']})")

    # Pass logic: Must have overall score >= 70, with both ankle impedances configured, and at least one ROM constraint correct
    passed = (score >= 70) and (ankle_imp_correct == 2) and (ankle_rom_correct >= 1)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }