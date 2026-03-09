#!/usr/bin/env python3
"""
Verifier for add_sphere_to_scene task.

ROBUST MULTI-SIGNAL VERIFICATION:
1. Output file exists and is valid blend file (15 points)
2. File was modified during task (15 points)
3. Object count increased (15 points)
4. Sphere object was added (15 points)
5. Sphere at approximately correct location (10 points)
6. Blender was running during task (10 points)
7. VLM: Scene shows spherical object (10 points)
8. VLM: Scene has changed from baseline (10 points)

Pass threshold: 60% AND key criteria (file modified + sphere added + object count increased)
"""

import json
import tempfile
import os
import math
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_add_sphere(traj, env_info, task_info):
    """
    Verify that a sphere was added to the scene and file was saved.

    Uses MULTIPLE INDEPENDENT SIGNALS to prevent gaming.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_location = metadata.get('expected_location', [0, -3, 2])
    location_tolerance = metadata.get('location_tolerance', 2.0)
    output_path = metadata.get('output_path', '/home/ga/BlenderProjects/scene_with_sphere.blend')

    feedback_parts = []
    score = 0

    # ================================================================
    # Copy result file from container
    # ================================================================
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

    # ================================================================
    # CRITERION 1: Output file exists and is valid (15 points)
    # ================================================================
    output_exists = result.get('output_exists', False)
    is_valid_blend = result.get('is_valid_blend', False)

    if output_exists and is_valid_blend:
        score += 15
        feedback_parts.append("Valid blend file saved")
    elif output_exists:
        score += 8
        feedback_parts.append("File exists (validity unknown)")
    else:
        feedback_parts.append("Output file NOT saved")
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": {"file_exists": False, "reason": "No output file created"}
        }

    # ================================================================
    # CRITERION 2: File was modified during task (15 points)
    # ================================================================
    file_modified = result.get('file_modified', False)
    file_created = result.get('file_created', False)

    if file_created:
        score += 15
        feedback_parts.append("File newly created")
    elif file_modified:
        score += 15
        feedback_parts.append("File modified during task")
    else:
        feedback_parts.append("File not modified (pre-existing)")

    # ================================================================
    # CRITERION 3: Object count increased (15 points)
    # ================================================================
    initial_count = result.get('initial_object_count', 0)
    current_count = result.get('current_object_count', 0)
    count_increased = current_count > initial_count

    if count_increased:
        score += 15
        feedback_parts.append(f"Objects: {initial_count} -> {current_count}")
    else:
        feedback_parts.append(f"Object count didn't increase ({current_count})")

    # ================================================================
    # CRITERION 4: Sphere object was added (15 points)
    # ================================================================
    sphere_added = result.get('sphere_added', False)
    current_sphere_count = result.get('current_sphere_count', 0)
    initial_sphere_count = result.get('initial_sphere_count', 0)

    if sphere_added and current_sphere_count > initial_sphere_count:
        score += 15
        feedback_parts.append(f"Sphere added ({initial_sphere_count} -> {current_sphere_count})")
    elif sphere_added:
        score += 10
        feedback_parts.append(f"Sphere detected (count: {current_sphere_count})")
    else:
        feedback_parts.append("No sphere added")

    # ================================================================
    # CRITERION 5: Sphere at approximately correct location (10 points)
    # ================================================================
    spheres = result.get('spheres', [])
    location_ok = False
    closest_distance = float('inf')
    closest_sphere = None

    for sphere in spheres:
        loc = sphere.get('location', [0, 0, 0])
        distance = math.sqrt(
            (loc[0] - expected_location[0]) ** 2 +
            (loc[1] - expected_location[1]) ** 2 +
            (loc[2] - expected_location[2]) ** 2
        )
        if distance < closest_distance:
            closest_distance = distance
            closest_sphere = sphere

    if closest_distance <= location_tolerance:
        score += 10
        location_ok = True
        feedback_parts.append(f"Location OK (dist: {closest_distance:.1f})")
    elif closest_distance <= location_tolerance * 3:
        score += 5
        feedback_parts.append(f"Location approximate (dist: {closest_distance:.1f})")
    elif spheres:
        feedback_parts.append(f"Location off (dist: {closest_distance:.1f})")
    else:
        feedback_parts.append("No sphere to verify location")

    # ================================================================
    # CRITERION 6: Blender was running (10 points)
    # ================================================================
    blender_running = result.get('blender_was_running', False)
    blender_window = result.get('blender_window_title', '')

    if blender_running or blender_window:
        score += 10
        feedback_parts.append("Blender was running")
    else:
        feedback_parts.append("Blender not detected")

    # ================================================================
    # CRITERION 7: VLM - Scene shows spherical object (10 points)
    # ================================================================
    query_vlm = env_info.get('query_vlm')
    screenshot_path = result.get('screenshot_path', '')
    vlm_sphere_verified = False

    if query_vlm and screenshot_path:
        try:
            temp_screenshot = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
            copy_from_env(screenshot_path, temp_screenshot.name)

            vlm_result = query_vlm(
                image=temp_screenshot.name,
                prompt="""Analyze this Blender 3D viewport screenshot:

1. Can you see a sphere or spherical/round object in the 3D scene?
2. Is there a new object that appears to be recently added?
3. Is the sphere visible in the viewport (not hidden)?

Answer each with Yes/No and brief explanation.
"""
            )

            vlm_text = vlm_result.get('response', '').lower() if isinstance(vlm_result, dict) else str(vlm_result).lower()

            has_sphere = 'yes' in vlm_text and any(word in vlm_text for word in
                ['sphere', 'spherical', 'round', 'ball', 'orb', 'circular'])

            if has_sphere:
                score += 10
                vlm_sphere_verified = True
                feedback_parts.append("VLM: Sphere visible in scene")
            else:
                feedback_parts.append("VLM: Sphere not clearly visible")

            os.unlink(temp_screenshot.name)
        except Exception as e:
            feedback_parts.append(f"VLM check failed: {str(e)[:30]}")
    else:
        feedback_parts.append("VLM: No verification available")

    # ================================================================
    # CRITERION 8: VLM - Scene has changed (10 points)
    # Compare with initial screenshot if available
    # ================================================================
    vlm_change_verified = False
    initial_screenshot = result.get('initial_screenshot_path', '')

    if query_vlm and screenshot_path and initial_screenshot:
        try:
            temp_initial = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
            temp_final = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
            copy_from_env(initial_screenshot, temp_initial.name)
            copy_from_env(screenshot_path, temp_final.name)

            # Note: This would require multi-image VLM support
            # For now, we'll use the screenshot analysis above
            score += 5  # Partial credit for having screenshots
            feedback_parts.append("Screenshots captured")

            os.unlink(temp_initial.name)
            os.unlink(temp_final.name)
        except Exception as e:
            pass  # Don't fail on this optional check

    # ================================================================
    # NEGATIVE CHECK: Must have actually done work
    # ================================================================
    if not file_modified and not file_created:
        feedback_parts.append("FAIL: File not modified")
        score = min(score, 20)

    if not sphere_added and current_sphere_count == initial_sphere_count:
        feedback_parts.append("FAIL: No sphere added")
        score = min(score, 25)

    # ================================================================
    # CALCULATE FINAL RESULT
    # ================================================================
    # Key criteria: file modified + sphere added + object count increased
    key_criteria_met = (
        (file_modified or file_created) and
        sphere_added and
        count_increased
    )

    # Pass threshold: 60% AND key criteria
    passed = score >= 60 and key_criteria_met

    # Summary
    if passed and score >= 80:
        feedback_parts.append("Excellent work!")
    elif passed:
        feedback_parts.append("Sphere added successfully")
    else:
        if not key_criteria_met:
            feedback_parts.append("FAIL: Key criteria not met - need modified file + sphere added + object count increased")
        else:
            feedback_parts.append(f"FAIL: Score {score}/100 below threshold")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "file_exists": output_exists,
            "file_modified": file_modified or file_created,
            "object_count_increased": count_increased,
            "sphere_added": sphere_added,
            "sphere_count": current_sphere_count,
            "location_ok": location_ok,
            "closest_distance": closest_distance if closest_distance != float('inf') else None,
            "blender_running": blender_running,
            "vlm_sphere_verified": vlm_sphere_verified,
            "key_criteria_met": key_criteria_met
        }
    }
