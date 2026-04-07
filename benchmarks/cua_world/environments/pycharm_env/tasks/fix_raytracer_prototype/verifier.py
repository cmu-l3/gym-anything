#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_fix_raytracer_prototype(traj, env_info, task_info):
    """
    Verify the fix_raytracer_prototype task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Read result JSON
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

    # 1. Test Suite Verification (60 pts)
    # We parse the output string or rely on exit code if completely clean
    pytest_out = result.get("pytest_output", "")
    
    # Check Camera Fix (FOV)
    if "test_fov_radians_conversion PASSED" in pytest_out:
        score += 15
        feedback.append("Camera FOV fixed (15/15)")
    else:
        feedback.append("Camera FOV test failed")

    # Check Geometry Fix (Sphere Root)
    if "test_sphere_intersection_nearest PASSED" in pytest_out:
        score += 15
        feedback.append("Sphere intersection fixed (15/15)")
    else:
        feedback.append("Sphere intersection test failed")

    # Check Material Fix (Reflection)
    if "test_reflection_vector PASSED" in pytest_out:
        score += 15
        feedback.append("Reflection formula fixed (15/15)")
    else:
        feedback.append("Reflection test failed")

    # Check Engine Fix (Bias) - this test was a placeholder in setup, 
    # so we rely more on the visual check for this one, but give points if tests ran.
    # Actually, let's give points if the render analysis confirms no acne.
    # We'll allocate the last 15 logic points to the "Overall Test Pass" 
    if result.get("pytest_exit_code") == 0:
        score += 15
        feedback.append("All tests passed (15/15)")
    else:
        feedback.append("Some tests failed")

    # 2. Render Verification (40 pts)
    pixels = result.get("pixel_analysis", {})
    if result.get("render_exists") and "error" not in pixels:
        # Shadow Check
        # If bias is wrong (0), shadow area might have noise (acne), i.e., random bright pixels
        # Or if sphere intersection is wrong, might be totally black or wrong shape
        # With correct render, shadow should be dark but not pitch black (ambient) or just dark grey.
        shadow_rgb = pixels.get("shadow_rgb", [255,255,255])
        # A simple check: shadow should be darker than sky
        if sum(shadow_rgb) < 150: 
            score += 10
            feedback.append("Shadow appears dark (10/10)")
        else:
            feedback.append(f"Shadow area too bright {shadow_rgb}")

        # Reflection Check
        # Metal sphere should reflect sky. Sky is usually blue-ish/white at top.
        # If reflection vector is wrong (flattened), it might look dark or reflect ground.
        reflect_rgb = pixels.get("reflect_rgb", [0,0,0])
        # Expecting something fairly bright
        if sum(reflect_rgb) > 300: 
            score += 15
            feedback.append("Reflection appears bright (15/15)")
        else:
            feedback.append(f"Reflection too dark {reflect_rgb}")
            
        # General Render Health
        score += 15
        feedback.append("Render completed successfully (15/15)")
    else:
        feedback.append("Render output missing or invalid")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback)
    }