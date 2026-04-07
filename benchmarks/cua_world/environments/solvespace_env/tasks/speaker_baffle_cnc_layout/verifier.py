#!/usr/bin/env python3
"""
Verifier for speaker_baffle_cnc_layout task.
Parses the SolveSpace .slvs file to check geometry and parameters,
and uses VLM on trajectory frames to ensure visual correctness.
"""

import os
import json
import tempfile
import logging

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_speaker_baffle(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_width = metadata.get('expected_width', 200.0)
    expected_height = metadata.get('expected_height', 350.0)
    expected_tweeter_top_dist = metadata.get('expected_tweeter_top_dist', 80.0)
    expected_center_dist = metadata.get('expected_center_dist', 130.0)
    expected_tweeter_dia = metadata.get('expected_tweeter_dia', 75.0)
    expected_woofer_dia = metadata.get('expected_woofer_dia', 145.0)
    tolerance = metadata.get('tolerance', 0.5)

    score = 0
    feedback = []
    
    # 1. Read export result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result_data = {}
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read task result: {e}")
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    file_exists = result_data.get('file_exists', False)
    file_created_during_task = result_data.get('file_created_during_task', False)
    
    if not file_exists:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Failed: speaker_baffle.slvs was not found."
        }

    score += 15
    feedback.append("File exists (+15)")

    if file_created_during_task:
        score += 10
        feedback.append("File created/modified during task (+10)")
    else:
        feedback.append("Warning: File timestamp predates task start.")

    # 2. Parse .slvs file
    temp_slvs = tempfile.NamedTemporaryFile(delete=False, suffix='.slvs')
    slvs_content = ""
    try:
        copy_from_env("/tmp/speaker_baffle.slvs", temp_slvs.name)
        with open(temp_slvs.name, 'r', encoding='utf-8', errors='ignore') as f:
            slvs_content = f.read()
    except Exception as e:
        logger.error(f"Failed to read slvs file: {e}")
    finally:
        if os.path.exists(temp_slvs.name):
            os.unlink(temp_slvs.name)

    lines = slvs_content.split('\n')
    
    # Extract entities and parameters
    line_count = sum(1 for line in lines if "Entity.type=11000" in line)
    circle_count = sum(1 for line in lines if "Request.type=400" in line)
    
    params = []
    for line in lines:
        if "Param.val=" in line:
            try:
                val_str = line.split("=")[1].strip()
                params.append(float(val_str))
            except ValueError:
                pass
                
    if line_count >= 4 and circle_count >= 2:
        score += 10
        feedback.append("Entity counts correct (>=4 lines, >=2 circles) (+10)")
    else:
        feedback.append(f"Entity count mismatch: {line_count} lines, {circle_count} circles.")

    def has_param(target):
        return any(abs(p - target) <= tolerance for p in params)

    # Check dimensions
    has_width = has_param(expected_width)
    has_height = has_param(expected_height)
    if has_width and has_height:
        score += 15
        feedback.append("Outer rectangle dimensions (200x350) correct (+15)")
    else:
        feedback.append("Missing or incorrect outer dimensions (200x350).")

    has_tweeter_top = has_param(expected_tweeter_top_dist)
    has_centers = has_param(expected_center_dist)
    if has_tweeter_top and has_centers:
        score += 15
        feedback.append("Positional dimensions (80, 130) correct (+15)")
    else:
        feedback.append("Missing or incorrect positional dimensions (80, 130).")

    has_tweeter_size = has_param(expected_tweeter_dia) or has_param(expected_tweeter_dia / 2.0)
    has_woofer_size = has_param(expected_woofer_dia) or has_param(expected_woofer_dia / 2.0)
    if has_tweeter_size and has_woofer_size:
        score += 15
        feedback.append("Cutout sizes (75 dia, 145 dia) correct (+15)")
    else:
        feedback.append("Missing or incorrect cutout sizes.")

    # 3. VLM Trajectory Verification
    vlm_score = 0
    if query_vlm:
        try:
            frames = sample_trajectory_frames(traj, n=3)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames
            
            prompt = """
            Look at these screenshots of a SolveSpace CAD session.
            Has the user drawn a speaker baffle layout with the following characteristics?
            1. A tall, rectangular outer boundary.
            2. Two distinct circles inside the rectangle.
            3. The upper circle (tweeter) is smaller than the lower circle (woofer).
            4. The two circles are aligned vertically along the center of the rectangle.
            
            Respond in JSON format:
            {
                "is_tall_rectangle": boolean,
                "has_two_circles": boolean,
                "circles_properly_arranged": boolean,
                "confidence": "high/medium/low",
                "reasoning": "string"
            }
            """
            
            vlm_resp = query_vlm(images=images, prompt=prompt)
            if vlm_resp.get("success"):
                parsed = vlm_resp.get("parsed", {})
                if parsed.get("is_tall_rectangle"):
                    vlm_score += 5
                if parsed.get("has_two_circles"):
                    vlm_score += 5
                if parsed.get("circles_properly_arranged"):
                    vlm_score += 10
                    
                score += vlm_score
                feedback.append(f"VLM Visual Verification: {vlm_score}/20 points")
            else:
                feedback.append(f"VLM Error: {vlm_resp.get('error')}")
        except Exception as e:
            feedback.append(f"VLM verification failed: {str(e)}")
            
    # Key criteria threshold
    key_criteria_met = file_exists and has_width and has_height and has_tweeter_top and has_centers and has_tweeter_size and has_woofer_size
    
    passed = score >= 70 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback),
        "details": {
            "parameters_found": params,
            "vlm_score": vlm_score
        }
    }