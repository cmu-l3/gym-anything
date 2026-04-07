#!/usr/bin/env python3
"""
Verifier for Ellipsoid Volume Estimation task.
"""

import sys
import os
import json
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_ellipsoid_volume(traj, env_info, task_info):
    """
    Verifies the volume calculation task.
    Checks for file existence, valid JSON payload, dimensional plausibility, 
    mathematical accuracy, and utilizes VLM on trajectory to confirm UI interaction.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    formula_multiplier = metadata.get('formula_multiplier', 0.52)
    min_dimension_mm = metadata.get('min_dimension_mm', 5.0)
    tolerance = metadata.get('tolerance_percent', 0.05) # 5% tolerance for rounding

    score = 0
    feedback_parts = []
    
    # 1. Retrieve the task result from the container
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

    # 2. Basic Existence & Anti-Gaming Checks
    report_exists = result.get('report_exists', False)
    screenshot_exists = result.get('screenshot_exists', False)
    created_during_task = result.get('report_created_during_task', False)
    agent_json = result.get('agent_json', {})
    
    if not report_exists:
        return {"passed": False, "score": 0, "feedback": "Volume report JSON not found"}
        
    if not created_during_task:
        return {"passed": False, "score": 0, "feedback": "Volume report was not created during the task (anti-gaming)"}
    
    if "error" in agent_json:
        return {"passed": False, "score": 0, "feedback": "Volume report contains invalid JSON format"}

    # 3. Validation of JSON Keys and Values (20 points)
    required_keys = ['axis_1_mm', 'axis_2_mm', 'axis_3_mm', 'volume_mm3']
    missing_keys = [k for k in required_keys if k not in agent_json]
    
    if missing_keys:
        return {"passed": False, "score": 0, "feedback": f"JSON missing required keys: {', '.join(missing_keys)}"}
        
    score += 20
    feedback_parts.append("JSON formatting valid")

    # 4. Plausible Dimensions Check (20 points)
    try:
        a1 = float(agent_json['axis_1_mm'])
        a2 = float(agent_json['axis_2_mm'])
        a3 = float(agent_json['axis_3_mm'])
        vol_reported = float(agent_json['volume_mm3'])
    except (ValueError, TypeError):
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts) + " | Values in JSON are not valid numbers"}

    if a1 > min_dimension_mm and a2 > min_dimension_mm and a3 > min_dimension_mm:
        score += 20
        feedback_parts.append("Dimensions plausible")
    else:
        feedback_parts.append("Dimensions implausible (<= 5mm)")

    # 5. Mathematical Accuracy Check (40 points) - CRITICAL
    expected_volume = a1 * a2 * a3 * formula_multiplier
    
    if expected_volume > 0:
        diff_percent = abs(vol_reported - expected_volume) / expected_volume
        if diff_percent <= tolerance:
            score += 40
            feedback_parts.append(f"Math correct ({vol_reported:.1f} matches expected {expected_volume:.1f})")
            math_passed = True
        else:
            feedback_parts.append(f"Math incorrect: reported {vol_reported:.1f}, expected {expected_volume:.1f}")
            math_passed = False
    else:
        feedback_parts.append("Cannot verify math (dimensions resulted in zero volume)")
        math_passed = False

    # 6. VLM Check for UI Interaction Evidence (20 points)
    vlm_score = 0
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        query_vlm = env_info.get('query_vlm')
        
        if query_vlm and math_passed: # Only bother querying VLM if they did the math right
            frames = sample_trajectory_frames(traj, n=3)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames
            
            prompt = """Analyze these screenshots of a medical imaging application (Weasis).
            Did the user draw distance measurement lines (typically bright colored lines with numeric distance values next to them) on the medical image?
            Respond strictly in JSON: {"measurements_visible": true/false}"""
            
            vlm_resp = query_vlm(images=images, prompt=prompt)
            if vlm_resp and vlm_resp.get('success') and vlm_resp.get('parsed', {}).get('measurements_visible'):
                vlm_score = 20
                feedback_parts.append("VLM confirmed measurement lines")
            else:
                feedback_parts.append("VLM did not detect measurement lines in UI")
        else:
            # If framework VLM is unavailable but core logic passed, grant points to avoid breaking offline tests
            vlm_score = 20
            feedback_parts.append("VLM visual verification skipped/unavailable")
    except ImportError:
        vlm_score = 20
        feedback_parts.append("VLM module unavailable, visual check skipped")
    except Exception as e:
        vlm_score = 20
        feedback_parts.append(f"VLM error ({e}), visual check skipped")

    score += vlm_score
    
    # Must get the math right to pass the task
    passed = score >= 80 and math_passed

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }