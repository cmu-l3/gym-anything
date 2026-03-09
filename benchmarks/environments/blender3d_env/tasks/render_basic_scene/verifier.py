#!/usr/bin/env python3
"""
Verifier for render_basic_scene task.

ROBUST MULTI-SIGNAL VERIFICATION:
1. Output file exists and is valid PNG (15 points)
2. File was created/modified during task (15 points)
3. File size reasonable for rendered image (10 points)
4. Image dimensions match expected (10 points)
5. Blender was running during task (10 points)
6. Scene was actually rendered (render time > 0) (15 points)
7. VLM: Rendered image shows 3D scene content (15 points)
8. VLM: Image is NOT just Blender UI/empty (10 points)

Pass threshold: 60% AND key criteria (file created + render performed + visual verification)
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_render_basic_scene(traj, env_info, task_info):
    """
    Verify that the scene was rendered and saved successfully.

    Uses MULTIPLE INDEPENDENT SIGNALS to prevent gaming.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_output_path = metadata.get('expected_output_path', '/home/ga/BlenderProjects/rendered_output.png')
    min_file_size_kb = metadata.get('min_file_size_kb', 50)
    expected_width = metadata.get('expected_width', 1920)
    expected_height = metadata.get('expected_height', 1080)

    feedback_parts = []
    score = 0
    max_score = 100

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
    image_format = result.get('image_format', 'unknown')

    if output_exists and image_format in ['PNG', 'JPEG', 'BMP', 'TIFF']:
        score += 15
        feedback_parts.append(f"Output file exists ({image_format})")
    elif output_exists:
        score += 8
        feedback_parts.append(f"Output file exists (format: {image_format})")
    else:
        feedback_parts.append("Output file NOT found")
        # Early exit - nothing else to check
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": {"file_exists": False, "reason": "No render output created"}
        }

    # ================================================================
    # CRITERION 2: File was created/modified during task (15 points)
    # ================================================================
    file_created = result.get('file_created', False)
    file_modified = result.get('file_modified', False)

    if file_created:
        score += 15
        feedback_parts.append("File newly created")
    elif file_modified:
        score += 12
        feedback_parts.append("File modified during task")
    else:
        feedback_parts.append("File existed before task (not modified)")

    # ================================================================
    # CRITERION 3: File size reasonable (10 points)
    # A real render should be > 50KB, complex scenes > 500KB
    # ================================================================
    file_size_kb = result.get('output_size_bytes', 0) / 1024

    if file_size_kb >= 500:  # Complex render
        score += 10
        feedback_parts.append(f"Good file size ({file_size_kb:.1f}KB)")
    elif file_size_kb >= min_file_size_kb:
        score += 7
        feedback_parts.append(f"Acceptable file size ({file_size_kb:.1f}KB)")
    elif file_size_kb >= 10:
        score += 3
        feedback_parts.append(f"Small file size ({file_size_kb:.1f}KB)")
    else:
        feedback_parts.append(f"File too small ({file_size_kb:.1f}KB)")

    # ================================================================
    # CRITERION 4: Image dimensions (10 points)
    # ================================================================
    image_width = result.get('image_width', 0)
    image_height = result.get('image_height', 0)

    # Allow 50% or higher resolution (accounting for percentage settings)
    width_ok = image_width >= expected_width * 0.4
    height_ok = image_height >= expected_height * 0.4
    exact_match = (abs(image_width - expected_width) <= 10 and
                   abs(image_height - expected_height) <= 10)

    if exact_match:
        score += 10
        feedback_parts.append(f"Exact dimensions ({image_width}x{image_height})")
    elif width_ok and height_ok:
        score += 7
        feedback_parts.append(f"Valid dimensions ({image_width}x{image_height})")
    elif image_width > 0 and image_height > 0:
        score += 3
        feedback_parts.append(f"Small dimensions ({image_width}x{image_height})")
    else:
        feedback_parts.append("Could not verify dimensions")

    # ================================================================
    # CRITERION 5: Blender was running (10 points)
    # ================================================================
    blender_was_running = result.get('blender_was_running', False)
    blender_window_title = result.get('blender_window_title', '')

    if blender_was_running or blender_window_title:
        score += 10
        feedback_parts.append("Blender was running")
    else:
        feedback_parts.append("Blender process not detected")

    # ================================================================
    # CRITERION 6: Render was actually performed (15 points)
    # Check render time, samples, or other indicators
    # ================================================================
    render_time_sec = result.get('render_time_seconds', 0)
    render_samples = result.get('render_samples', 0)
    render_started = result.get('render_started', False)

    if render_time_sec > 5:
        score += 15
        feedback_parts.append(f"Render completed ({render_time_sec:.1f}s)")
    elif render_time_sec > 0 or render_started:
        score += 10
        feedback_parts.append(f"Render performed ({render_time_sec:.1f}s)")
    elif file_created and file_size_kb > 100:
        # Infer render happened from file characteristics
        score += 8
        feedback_parts.append("Render inferred from file")
    else:
        feedback_parts.append("No render activity detected")

    # ================================================================
    # CRITERION 7: VLM Visual Verification - 3D content (15 points)
    # ================================================================
    query_vlm = env_info.get('query_vlm')
    screenshot_path = result.get('screenshot_path', '')
    rendered_image_path = result.get('rendered_image_local_path', '')
    vlm_3d_verified = False
    vlm_not_empty_verified = False

    # Try to verify the rendered output itself
    if query_vlm and (rendered_image_path or output_exists):
        try:
            # Copy the rendered image to analyze it
            temp_render = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
            copy_from_env(expected_output_path, temp_render.name)

            vlm_result = query_vlm(
                image=temp_render.name,
                prompt="""Analyze this rendered 3D image:

1. Does this appear to be a 3D rendered scene (with objects, lighting, shadows)?
2. Can you see recognizable 3D objects (cars, buildings, characters, furniture, geometric shapes)?
3. Is there visible lighting, reflections, or materials?
4. Does the image have depth and perspective (not flat 2D)?

Answer each with Yes/No and brief explanation.
"""
            )

            vlm_text = vlm_result.get('response', '').lower() if isinstance(vlm_result, dict) else str(vlm_result).lower()

            has_3d_objects = 'yes' in vlm_text and any(word in vlm_text for word in
                ['object', 'car', 'model', 'scene', 'shape', 'geometry', 'render', 'lighting', 'shadow', 'reflection'])
            has_depth = 'perspective' in vlm_text or 'depth' in vlm_text or '3d' in vlm_text

            if has_3d_objects and has_depth:
                score += 15
                vlm_3d_verified = True
                feedback_parts.append("VLM: 3D rendered content confirmed")
            elif has_3d_objects:
                score += 10
                vlm_3d_verified = True
                feedback_parts.append("VLM: 3D objects detected")
            elif 'yes' in vlm_text:
                score += 5
                feedback_parts.append("VLM: Some render content detected")
            else:
                feedback_parts.append("VLM: Could not confirm 3D content")

            os.unlink(temp_render.name)
        except Exception as e:
            feedback_parts.append(f"VLM render check failed: {str(e)[:50]}")
    else:
        feedback_parts.append("VLM: No verification available")

    # ================================================================
    # CRITERION 8: VLM - Not just Blender UI (10 points)
    # Verify the output is actual render, not screenshot of UI
    # ================================================================
    if query_vlm and screenshot_path:
        try:
            temp_screenshot = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
            copy_from_env(screenshot_path, temp_screenshot.name)

            vlm_result = query_vlm(
                image=temp_screenshot.name,
                prompt="""Is this a screenshot showing Blender 3D software?
If so, does it show:
1. A render result window/viewer (not the 3D viewport)?
2. A completed render (not in-progress)?
3. The Image Editor with a rendered image?

Answer Yes/No for each."""
            )

            vlm_text = vlm_result.get('response', '').lower() if isinstance(vlm_result, dict) else str(vlm_result).lower()

            has_render_result = any(word in vlm_text for word in
                ['render', 'result', 'complete', 'finished', 'image editor'])

            if has_render_result:
                score += 10
                vlm_not_empty_verified = True
                feedback_parts.append("VLM: Render window visible")
            elif 'blender' in vlm_text:
                score += 5
                feedback_parts.append("VLM: Blender visible")

            os.unlink(temp_screenshot.name)
        except Exception as e:
            feedback_parts.append(f"VLM UI check skipped: {str(e)[:30]}")

    # ================================================================
    # NEGATIVE CHECK: Must have actually done work
    # ================================================================
    if not file_created and not file_modified:
        feedback_parts.append("FAIL: No new render output created")
        score = min(score, 20)  # Cap score

    if file_size_kb < 5:
        feedback_parts.append("FAIL: Output file suspiciously small")
        score = min(score, 25)

    # ================================================================
    # CALCULATE FINAL RESULT
    # ================================================================
    # Key criteria: file created + (render time OR good file size) + (VLM OR dimensions OK)
    key_criteria_met = (
        (file_created or file_modified) and
        (render_time_sec > 0 or file_size_kb > 100) and
        (vlm_3d_verified or (width_ok and height_ok))
    )

    # Pass threshold: 60% AND key criteria
    passed = score >= 60 and key_criteria_met

    # Summary
    if passed and score >= 80:
        feedback_parts.append("Excellent render!")
    elif passed:
        feedback_parts.append("Render successful")
    else:
        if not key_criteria_met:
            feedback_parts.append("FAIL: Key criteria not met - need new render + visual verification")
        else:
            feedback_parts.append(f"FAIL: Score {score}/100 below threshold")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "file_exists": output_exists,
            "file_created": file_created,
            "file_modified": file_modified,
            "file_size_kb": file_size_kb,
            "dimensions": f"{image_width}x{image_height}",
            "render_time": render_time_sec,
            "blender_running": blender_was_running,
            "vlm_3d_verified": vlm_3d_verified,
            "vlm_ui_verified": vlm_not_empty_verified,
            "key_criteria_met": key_criteria_met
        }
    }
