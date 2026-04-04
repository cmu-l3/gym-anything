#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_portal_setup(traj, env_info, task_info):
    """
    Verifies the Interior Portal Light Setup task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env missing"}

    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Basic File Checks
    if not result.get("output_exists"):
        return {"passed": False, "score": 0, "feedback": "No output file found at /home/ga/BlenderProjects/portal_setup.blend"}
    
    if not result.get("output_modified"):
        return {"passed": False, "score": 0, "feedback": "Output file exists but was not saved during this session (timestamp mismatch)."}

    analysis = result.get("analysis", {})
    if not analysis.get("light_found", False):
        return {"passed": False, "score": 10, "feedback": "File saved, but no Area Light found in the scene."}

    best_light = analysis.get("best_light", {})
    
    score = 10 # Base for valid file and light existence
    feedback = []

    # 1. Check Portal Property (Critical)
    is_portal = best_light.get("is_portal", False)
    if is_portal:
        score += 30
        feedback.append("Portal property enabled.")
    else:
        feedback.append("Portal property NOT enabled.")

    # 2. Check Position (Distance from window center)
    dist = best_light.get("distance", 999)
    # Tolerance 0.5m
    if dist < 0.2:
        score += 20
        feedback.append("Position is perfect.")
    elif dist < 0.5:
        score += 15
        feedback.append("Position is acceptable.")
    elif dist < 1.0:
        score += 5
        feedback.append("Position is slightly off.")
    else:
        feedback.append(f"Light is too far from window (dist={dist:.2f}m).")

    # 3. Check Alignment (Dot product)
    # > 0.9 is good (approx 25 degrees)
    alignment = best_light.get("alignment", -1)
    if alignment > 0.9:
        score += 15
        feedback.append("Orientation is correct (pointing inward).")
    elif alignment > 0.5:
        score += 5
        feedback.append("Orientation is roughly correct.")
    else:
        feedback.append("Light is facing the wrong way.")

    # 4. Check Size
    # size_diff is abs sum difference from target [2.0, 1.5]
    size_diff = best_light.get("size_diff", 999)
    if size_diff < 0.2:
        score += 15
        feedback.append("Size matches window.")
    elif size_diff < 0.8:
        score += 5
        feedback.append("Size is roughly correct.")
    else:
        feedback.append("Light size does not match window dimensions.")

    # 5. Scene content check (basic anti-gaming)
    # If the light is a portal but position/size are defaults, penalize
    if is_portal and dist > 2.0 and size_diff > 2.0:
        score = min(score, 40)
        feedback.append("Portal enabled but placement seems random/default.")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": int(score),
        "feedback": " ".join(feedback)
    }