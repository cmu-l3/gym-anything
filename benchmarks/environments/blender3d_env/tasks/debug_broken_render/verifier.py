#!/usr/bin/env python3
"""
Verifier for debug_broken_render task.

MULTI-BUG DEBUGGING VERIFICATION:
1. Camera faces scene (15 points)
2. Light energy > 0.5 (15 points)
3. Resolution >= 1280x720 (15 points)
4. Samples >= 16 (10 points)
5. BaseCube visible in render (15 points)
6. Render output saved (15 points)
7. Blend file saved (15 points)

Pass threshold: 70 (must fix the majority of bugs and produce output files)
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_debug_broken_render(traj, env_info, task_info):
    """
    Verify that all 5 planted bugs were fixed and output files were saved.

    Each criterion is evaluated independently with try/except to ensure
    partial credit even if some checks fail.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_blend = metadata.get('expected_blend_output', '/home/ga/BlenderProjects/fixed_scene.blend')
    expected_render = metadata.get('expected_render_output', '/home/ga/BlenderProjects/fixed_render.png')
    min_light_energy = metadata.get('min_light_energy', 0.5)
    min_resolution = metadata.get('min_resolution', [1280, 720])
    min_samples = metadata.get('min_samples', 16)
    target_object = metadata.get('target_object', 'BaseCube')

    feedback_parts = []
    score = 0
    max_score = 100
    details = {}

    # ================================================================
    # Load task_result.json from the environment
    # ================================================================
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read task_result.json: {e}")
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
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
            "feedback": "No output files found -- agent did not produce fixed_scene.blend or fixed_render.png"
        }

    scene = result.get('scene_analysis', {})

    # ================================================================
    # CRITERION 1: Camera faces the scene (15 points)
    # ================================================================
    try:
        camera = scene.get('camera', {})
        has_tracking = camera.get('has_tracking_constraint', False)
        faces_scene = camera.get('faces_scene', False)
        dot_product = camera.get('dot_product', 0.0)
        camera_found = camera.get('found', False)

        if not camera_found:
            feedback_parts.append("Camera: NOT FOUND in scene")
            details['camera_fixed'] = False
        elif has_tracking:
            score += 15
            feedback_parts.append("Camera: has tracking constraint (fixed)")
            details['camera_fixed'] = True
        elif faces_scene and dot_product > 0:
            score += 15
            feedback_parts.append(f"Camera: faces scene (dot={dot_product:.3f})")
            details['camera_fixed'] = True
        elif dot_product > 0:
            # Weak facing but positive
            score += 10
            feedback_parts.append(f"Camera: partially faces scene (dot={dot_product:.3f})")
            details['camera_fixed'] = True
        else:
            feedback_parts.append(f"Camera: still facing away (dot={dot_product:.3f})")
            details['camera_fixed'] = False
    except Exception as e:
        feedback_parts.append(f"Camera check failed: {str(e)[:50]}")
        details['camera_fixed'] = False

    # ================================================================
    # CRITERION 2: Light energy > 0.5 (15 points)
    # ================================================================
    try:
        light_energy = scene.get('main_light_energy', 0.0)
        light_name = scene.get('main_light_name', 'unknown')

        # Also check if any light in the scene has reasonable energy
        lights = scene.get('lights', [])
        max_energy = light_energy
        for light in lights:
            energy = light.get('energy', 0.0)
            if energy > max_energy:
                max_energy = energy

        if max_energy > min_light_energy:
            score += 15
            feedback_parts.append(f"Light: energy={max_energy:.1f} (fixed)")
            details['light_fixed'] = True
            details['light_energy'] = max_energy
        elif max_energy > 0.0:
            # Some energy but below threshold
            score += 5
            feedback_parts.append(f"Light: energy={max_energy:.1f} (too low, need >{min_light_energy})")
            details['light_fixed'] = False
            details['light_energy'] = max_energy
        else:
            feedback_parts.append(f"Light: energy=0.0 (still broken)")
            details['light_fixed'] = False
            details['light_energy'] = 0.0
    except Exception as e:
        feedback_parts.append(f"Light check failed: {str(e)[:50]}")
        details['light_fixed'] = False

    # ================================================================
    # CRITERION 3: Resolution >= 1280x720 (15 points)
    # ================================================================
    try:
        # Use effective resolution (accounts for percentage scaling)
        eff_x = scene.get('effective_resolution_x', 0)
        eff_y = scene.get('effective_resolution_y', 0)

        # Fallback to raw resolution if effective not available
        if eff_x == 0 or eff_y == 0:
            eff_x = scene.get('resolution_x', 0)
            eff_y = scene.get('resolution_y', 0)
            pct = scene.get('resolution_percentage', 100)
            eff_x = int(eff_x * pct / 100)
            eff_y = int(eff_y * pct / 100)

        min_x, min_y = min_resolution

        if eff_x >= min_x and eff_y >= min_y:
            score += 15
            feedback_parts.append(f"Resolution: {eff_x}x{eff_y} (fixed)")
            details['resolution_fixed'] = True
        elif eff_x >= 640 and eff_y >= 480:
            # Partially fixed -- better than 10x10 but not production
            score += 7
            feedback_parts.append(f"Resolution: {eff_x}x{eff_y} (improved but below {min_x}x{min_y})")
            details['resolution_fixed'] = False
        else:
            feedback_parts.append(f"Resolution: {eff_x}x{eff_y} (still broken, need {min_x}x{min_y})")
            details['resolution_fixed'] = False

        details['effective_resolution'] = f"{eff_x}x{eff_y}"
    except Exception as e:
        feedback_parts.append(f"Resolution check failed: {str(e)[:50]}")
        details['resolution_fixed'] = False

    # ================================================================
    # CRITERION 4: Samples >= 16 (10 points)
    # ================================================================
    try:
        samples = scene.get('cycles_samples', 0)
        render_engine = scene.get('render_engine', '')

        if render_engine != 'CYCLES':
            # If they switched to EEVEE, samples concept is different but acceptable
            score += 10
            feedback_parts.append(f"Samples: using {render_engine} (acceptable)")
            details['samples_fixed'] = True
        elif samples >= min_samples:
            score += 10
            feedback_parts.append(f"Samples: {samples} (fixed)")
            details['samples_fixed'] = True
        elif samples > 1:
            # Better than 1 but not enough
            score += 5
            feedback_parts.append(f"Samples: {samples} (improved but below {min_samples})")
            details['samples_fixed'] = False
        else:
            feedback_parts.append(f"Samples: {samples} (still broken, need >={min_samples})")
            details['samples_fixed'] = False

        details['cycles_samples'] = samples
    except Exception as e:
        feedback_parts.append(f"Samples check failed: {str(e)[:50]}")
        details['samples_fixed'] = False

    # ================================================================
    # CRITERION 5: BaseCube visible in render (15 points)
    # ================================================================
    try:
        cube = scene.get('base_cube', {})
        cube_found = cube.get('found', False)
        hide_render = cube.get('hide_render', True)

        if not cube_found:
            feedback_parts.append(f"{target_object}: NOT FOUND in scene")
            details['cube_visible'] = False
        elif not hide_render:
            score += 15
            feedback_parts.append(f"{target_object}: visible in render (fixed)")
            details['cube_visible'] = True
        else:
            feedback_parts.append(f"{target_object}: still hidden in render (hide_render=True)")
            details['cube_visible'] = False
    except Exception as e:
        feedback_parts.append(f"Cube visibility check failed: {str(e)[:50]}")
        details['cube_visible'] = False

    # ================================================================
    # CRITERION 6: Render output saved (15 points)
    # ================================================================
    try:
        render_exists = result.get('render_exists', False)
        render_size = result.get('render_size_bytes', 0)
        image_format = result.get('image_format', 'none')
        image_width = result.get('image_width', 0)
        image_height = result.get('image_height', 0)
        render_size_kb = render_size / 1024

        if render_exists and image_format in ['PNG', 'JPEG', 'BMP', 'TIFF']:
            if render_size_kb >= 10:
                score += 15
                feedback_parts.append(f"Render: saved ({image_format}, {render_size_kb:.1f}KB, {image_width}x{image_height})")
                details['render_saved'] = True
            else:
                # File exists but suspiciously small
                score += 8
                feedback_parts.append(f"Render: saved but very small ({render_size_kb:.1f}KB)")
                details['render_saved'] = True
        elif render_exists:
            score += 5
            feedback_parts.append(f"Render: file exists but format unclear ({image_format})")
            details['render_saved'] = True
        else:
            feedback_parts.append("Render: NOT saved (fixed_render.png not found)")
            details['render_saved'] = False

        details['render_size_kb'] = render_size_kb
        details['render_dimensions'] = f"{image_width}x{image_height}"
    except Exception as e:
        feedback_parts.append(f"Render check failed: {str(e)[:50]}")
        details['render_saved'] = False

    # ================================================================
    # CRITERION 7: Blend file saved (15 points)
    # ================================================================
    try:
        blend_exists = result.get('blend_exists', False)
        blend_size = result.get('blend_size_bytes', 0)
        blend_size_kb = blend_size / 1024

        if blend_exists and blend_size_kb >= 10:
            score += 15
            feedback_parts.append(f"Blend: saved ({blend_size_kb:.1f}KB)")
            details['blend_saved'] = True
        elif blend_exists:
            score += 8
            feedback_parts.append(f"Blend: saved but very small ({blend_size_kb:.1f}KB)")
            details['blend_saved'] = True
        else:
            feedback_parts.append("Blend: NOT saved (fixed_scene.blend not found)")
            details['blend_saved'] = False

        details['blend_size_kb'] = blend_size_kb
    except Exception as e:
        feedback_parts.append(f"Blend check failed: {str(e)[:50]}")
        details['blend_saved'] = False

    # ================================================================
    # NEGATIVE CHECKS
    # ================================================================
    # Must have produced at least one output file
    if not details.get('render_saved', False) and not details.get('blend_saved', False):
        feedback_parts.append("FAIL: No output files produced")
        score = min(score, 30)

    # ================================================================
    # CALCULATE FINAL RESULT
    # ================================================================
    bugs_fixed = sum([
        details.get('camera_fixed', False),
        details.get('light_fixed', False),
        details.get('resolution_fixed', False),
        details.get('samples_fixed', False),
        details.get('cube_visible', False),
    ])

    details['bugs_fixed'] = bugs_fixed
    details['bugs_total'] = 5

    # Pass threshold: 70
    passed = score >= 70

    # Summary
    if passed and score >= 90:
        feedback_parts.append(f"Excellent! Fixed {bugs_fixed}/5 bugs (score: {score}/100)")
    elif passed:
        feedback_parts.append(f"Passed: fixed {bugs_fixed}/5 bugs (score: {score}/100)")
    else:
        feedback_parts.append(f"FAIL: fixed {bugs_fixed}/5 bugs (score: {score}/100, need >=70)")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": details
    }
