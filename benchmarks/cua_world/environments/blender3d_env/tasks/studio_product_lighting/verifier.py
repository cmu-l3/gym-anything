#!/usr/bin/env python3
"""
Verifier for studio_product_lighting task.

ROBUST MULTI-SIGNAL VERIFICATION (5 criteria, each in its own try/except):
1. 3+ lights of type AREA or SPOT exist (25 points)
2. Camera positioned at reasonable automotive 3/4 angle (20 points)
3. World background is dark (brightness < 0.15) (15 points)
4. Render output exists, is PNG, >100KB (25 points)
5. Blend file saved and valid (15 points)

Bonus: VLM verification of render output for studio lighting quality.

Pass threshold: score >= 70
"""

import json
import tempfile
import os
import math
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_studio_product_lighting(traj, env_info, task_info):
    """
    Verify that professional studio lighting was set up and the scene
    was rendered and saved correctly.

    Uses MULTIPLE INDEPENDENT SIGNALS with each criterion in its own
    try/except block to prevent one failure from cascading.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_blend = metadata.get('expected_blend_output', '/home/ga/BlenderProjects/studio_setup.blend')
    expected_render = metadata.get('expected_render_output', '/home/ga/BlenderProjects/product_shot.png')
    min_light_count = metadata.get('min_light_count', 3)
    accepted_light_types = metadata.get('accepted_light_types', ['AREA', 'SPOT'])
    camera_height_range = metadata.get('camera_height_range', [0.5, 3.0])
    max_world_brightness = metadata.get('max_world_brightness', 0.15)
    min_render_size_kb = metadata.get('min_render_size_kb', 100)

    feedback_parts = []
    score = 0
    details = {}

    # ================================================================
    # Load result JSON from container
    # ================================================================
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to read task result: {e}"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # ================================================================
    # GATE: If no primary output exists, agent did nothing -> score 0
    # (Lesson 22: output-existence gate prevents do-nothing scoring)
    # ================================================================
    if not result.get('blend_exists', False) and not result.get('render_exists', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "No output files found -- agent did not produce studio_setup.blend or product_shot.png"
        }

    # ================================================================
    # CRITERION 1: 3+ lights of type AREA or SPOT (25 points)
    # ================================================================
    try:
        lights = result.get('lights', [])
        current_light_count = result.get('current_light_count', 0)
        area_or_spot_count = result.get('area_or_spot_count', 0)
        light_type_counts = result.get('light_type_counts', {})
        initial_light_count = result.get('initial_light_count', 0)

        # Count lights with accepted types
        accepted_lights = [
            lt for lt in lights
            if lt.get('light_type', '') in accepted_light_types
        ]
        accepted_count = len(accepted_lights)

        if accepted_count >= min_light_count:
            score += 25
            feedback_parts.append(
                f"Lighting: {accepted_count} studio lights "
                f"({light_type_counts})"
            )
        elif accepted_count >= 2:
            score += 15
            feedback_parts.append(
                f"Lighting: {accepted_count}/{min_light_count} studio lights "
                f"(need {min_light_count}+)"
            )
        elif current_light_count >= min_light_count:
            # Has enough lights but wrong types
            score += 10
            feedback_parts.append(
                f"Lighting: {current_light_count} lights but only "
                f"{accepted_count} are AREA/SPOT"
            )
        elif current_light_count > 0:
            score += 5
            feedback_parts.append(
                f"Lighting: only {current_light_count} light(s), "
                f"need {min_light_count}+ AREA/SPOT"
            )
        else:
            feedback_parts.append("Lighting: NO lights added")

        details['light_count'] = current_light_count
        details['area_or_spot_count'] = accepted_count
        details['light_types'] = light_type_counts
        details['lights_added'] = current_light_count > initial_light_count

    except Exception as e:
        feedback_parts.append(f"Lighting check error: {str(e)[:60]}")
        details['lighting_error'] = str(e)

    # ================================================================
    # CRITERION 2: Camera positioned at automotive 3/4 angle (20 points)
    # ================================================================
    try:
        camera = result.get('camera', {})
        cam_location = camera.get('location', [0, 0, 0])
        cam_height = camera.get('height', cam_location[2] if len(cam_location) > 2 else 0)
        cam_distance = camera.get(
            'distance_from_origin',
            math.sqrt(sum(v ** 2 for v in cam_location)) if cam_location else 0
        )

        height_min, height_max = camera_height_range

        # Check height is in range
        height_ok = height_min <= cam_height <= height_max

        # Check camera is not at origin (must have been repositioned or be at a valid position)
        not_at_origin = cam_distance > 1.0

        # Check camera has a horizontal offset (3/4 view means not directly front/side/top)
        cam_x = cam_location[0] if len(cam_location) > 0 else 0
        cam_y = cam_location[1] if len(cam_location) > 1 else 0
        has_lateral_offset = abs(cam_x) > 0.5 or abs(cam_y) > 0.5

        if height_ok and not_at_origin and has_lateral_offset:
            score += 20
            feedback_parts.append(
                f"Camera: height={cam_height:.1f}m, dist={cam_distance:.1f}m"
            )
        elif not_at_origin and has_lateral_offset:
            # Camera moved but height out of range -- partial credit
            score += 12
            feedback_parts.append(
                f"Camera: positioned but height={cam_height:.1f}m "
                f"(expected {height_min}-{height_max}m)"
            )
        elif not_at_origin:
            score += 8
            feedback_parts.append(
                f"Camera: dist={cam_distance:.1f}m but limited lateral offset"
            )
        else:
            feedback_parts.append("Camera: at origin or not repositioned")

        details['camera_location'] = cam_location
        details['camera_height'] = cam_height
        details['camera_distance'] = cam_distance
        details['camera_height_ok'] = height_ok

    except Exception as e:
        feedback_parts.append(f"Camera check error: {str(e)[:60]}")
        details['camera_error'] = str(e)

    # ================================================================
    # CRITERION 3: World background is dark (15 points)
    # ================================================================
    try:
        world = result.get('world', {})
        world_color = world.get('color', [0.5, 0.5, 0.5])
        world_strength = world.get('strength', 1.0)
        world_brightness = world.get('brightness', 0.5)

        # The brightness value from export_result.sh already accounts for
        # strength: brightness = luminance * strength
        # If not computed, compute it here
        if world_brightness == 0.5 and world_color == [0.5, 0.5, 0.5]:
            # Likely default -- not changed
            pass

        # Also compute raw luminance for safety
        r, g, b = world_color[0], world_color[1], world_color[2]
        raw_luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
        effective_brightness = raw_luminance * world_strength

        # Use the smaller of both estimates to be generous
        brightness_check = min(world_brightness, effective_brightness)

        if brightness_check <= max_world_brightness:
            score += 15
            feedback_parts.append(
                f"World: dark background (brightness={brightness_check:.3f})"
            )
        elif brightness_check <= max_world_brightness * 2:
            # Close to dark
            score += 8
            feedback_parts.append(
                f"World: somewhat dark (brightness={brightness_check:.3f}, "
                f"target <{max_world_brightness})"
            )
        elif brightness_check < 0.5:
            # Darker than default but not dark enough
            score += 4
            feedback_parts.append(
                f"World: darkened but not enough "
                f"(brightness={brightness_check:.3f})"
            )
        else:
            feedback_parts.append(
                f"World: NOT dark (brightness={brightness_check:.3f}, "
                f"still at default grey?)"
            )

        details['world_color'] = world_color
        details['world_strength'] = world_strength
        details['world_brightness'] = brightness_check
        details['world_is_dark'] = brightness_check <= max_world_brightness

    except Exception as e:
        feedback_parts.append(f"World check error: {str(e)[:60]}")
        details['world_error'] = str(e)

    # ================================================================
    # CRITERION 4: Render output exists, is PNG, >100KB (25 points)
    # ================================================================
    try:
        render_exists = result.get('render_exists', False)
        render_size_bytes = result.get('render_size_bytes', 0)
        render_size_kb = render_size_bytes / 1024
        render_format = result.get('render_format', 'none')
        render_width = result.get('render_width', 0)
        render_height = result.get('render_height', 0)

        if render_exists and render_format == 'PNG' and render_size_kb >= min_render_size_kb:
            score += 25
            feedback_parts.append(
                f"Render: PNG {render_width}x{render_height}, "
                f"{render_size_kb:.0f}KB"
            )
        elif render_exists and render_size_kb >= min_render_size_kb:
            # Exists and large enough but maybe not PNG
            score += 18
            feedback_parts.append(
                f"Render: {render_format} {render_size_kb:.0f}KB "
                f"(expected PNG)"
            )
        elif render_exists and render_size_kb >= 10:
            # Exists but small
            score += 10
            feedback_parts.append(
                f"Render: exists but small ({render_size_kb:.0f}KB, "
                f"need >{min_render_size_kb}KB)"
            )
        elif render_exists:
            score += 5
            feedback_parts.append(
                f"Render: exists but tiny ({render_size_kb:.1f}KB)"
            )
        else:
            feedback_parts.append("Render: output file NOT found")

        details['render_exists'] = render_exists
        details['render_size_kb'] = render_size_kb
        details['render_format'] = render_format
        details['render_dimensions'] = f"{render_width}x{render_height}"

    except Exception as e:
        feedback_parts.append(f"Render check error: {str(e)[:60]}")
        details['render_error'] = str(e)

    # ================================================================
    # CRITERION 5: Blend file saved and valid (15 points)
    # ================================================================
    try:
        blend_exists = result.get('blend_exists', False)
        blend_valid = result.get('blend_valid', False)
        blend_created = result.get('blend_created', False)
        blend_size_bytes = result.get('blend_size_bytes', 0)
        blend_size_kb = blend_size_bytes / 1024

        if blend_exists and blend_valid and blend_size_kb > 100:
            score += 15
            feedback_parts.append(
                f"Blend: saved ({blend_size_kb:.0f}KB)"
            )
        elif blend_exists and blend_valid:
            score += 12
            feedback_parts.append(
                f"Blend: saved but small ({blend_size_kb:.0f}KB)"
            )
        elif blend_exists:
            score += 5
            feedback_parts.append(
                f"Blend: file exists but invalid format"
            )
        else:
            feedback_parts.append("Blend: output file NOT saved")

        details['blend_exists'] = blend_exists
        details['blend_valid'] = blend_valid
        details['blend_size_kb'] = blend_size_kb

    except Exception as e:
        feedback_parts.append(f"Blend check error: {str(e)[:60]}")
        details['blend_error'] = str(e)

    # ================================================================
    # BONUS: VLM verification of rendered image (up to 10 bonus points)
    # ================================================================
    vlm_verified = False
    query_vlm = env_info.get('query_vlm')

    if query_vlm and result.get('render_exists', False):
        try:
            temp_render = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
            copy_from_env(expected_render, temp_render.name)

            vlm_result = query_vlm(
                image=temp_render.name,
                prompt=(
                    "Analyze this rendered 3D image of a car/vehicle:\n\n"
                    "1. Is there a car or vehicle visible in the image?\n"
                    "2. Does the image have professional studio-style lighting "
                    "(key light, fill light, rim light visible as highlights "
                    "and reflections)?\n"
                    "3. Is the background dark (black or near-black), typical "
                    "of product photography?\n"
                    "4. Can you see distinct light reflections on the car body?\n"
                    "5. Is the camera angle a 3/4 front view (seeing front and "
                    "one side of the car)?\n\n"
                    "Answer each with Yes/No and brief explanation."
                )
            )

            vlm_text = (
                vlm_result.get('response', '').lower()
                if isinstance(vlm_result, dict)
                else str(vlm_result).lower()
            )

            has_car = 'yes' in vlm_text and any(
                word in vlm_text for word in
                ['car', 'vehicle', 'automobile', 'bmw', 'sedan']
            )
            has_studio_lighting = any(
                word in vlm_text for word in
                ['studio', 'professional', 'key light', 'rim light',
                 'reflection', 'highlight', 'three-point', '3-point']
            )
            has_dark_bg = any(
                word in vlm_text for word in
                ['dark', 'black', 'dark background', 'studio background']
            )

            vlm_signals = sum([has_car, has_studio_lighting, has_dark_bg])

            if vlm_signals >= 2:
                vlm_verified = True
                feedback_parts.append(
                    f"VLM: studio product shot confirmed "
                    f"(car={has_car}, lighting={has_studio_lighting}, "
                    f"dark_bg={has_dark_bg})"
                )
            elif vlm_signals >= 1:
                feedback_parts.append(
                    f"VLM: partial confirmation "
                    f"(car={has_car}, lighting={has_studio_lighting}, "
                    f"dark_bg={has_dark_bg})"
                )
            else:
                feedback_parts.append("VLM: could not confirm studio setup")

            details['vlm_has_car'] = has_car
            details['vlm_has_studio_lighting'] = has_studio_lighting
            details['vlm_has_dark_bg'] = has_dark_bg
            details['vlm_verified'] = vlm_verified

            os.unlink(temp_render.name)

        except Exception as e:
            feedback_parts.append(f"VLM check failed: {str(e)[:50]}")
            details['vlm_error'] = str(e)
    else:
        feedback_parts.append("VLM: not available or no render to check")

    # ================================================================
    # NEGATIVE CHECKS
    # ================================================================
    # If no lights were added at all, cap the score
    if result.get('current_light_count', 0) == 0:
        feedback_parts.append("PENALTY: No lights added to scene")
        score = min(score, 30)

    # If neither render nor blend was saved, cap the score
    if not result.get('render_exists', False) and not result.get('blend_exists', False):
        feedback_parts.append("PENALTY: No output files created")
        score = min(score, 15)

    # ================================================================
    # CALCULATE FINAL RESULT
    # ================================================================
    passed = score >= 70

    if passed and score >= 90:
        feedback_parts.append("Excellent studio setup!")
    elif passed:
        feedback_parts.append("Studio lighting task completed")
    else:
        feedback_parts.append(f"Score {score}/100 below threshold (70)")

    details['score_breakdown'] = {
        'lighting_max_25': min(25, max(0, score)),
        'total_score': score
    }

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": details
    }
