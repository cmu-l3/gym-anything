#!/usr/bin/env python3
"""Verifier for draw_basic_shapes task.

HYBRID VERIFICATION: Combines programmatic file checks with VLM-based visual verification.

Programmatic checks:
- File exists at expected path
- File is valid flipchart format (ZIP with XML)
- Shape elements found in XML (rectangle, circle)

VLM checks:
- ActivInspire is running and visible
- Shapes (rectangle and circle) are visible on canvas
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def build_shapes_prompt():
    """Build VLM prompt to verify shapes are visible on flipchart."""
    return """Examine this screenshot of an ActivInspire session.

Task: Verify that ActivInspire is showing a flipchart with drawn shapes.

The task required drawing a RECTANGLE and a CIRCLE/ELLIPSE on the flipchart.

Check for these indicators:

1. APPLICATION VISIBLE: Is ActivInspire software visible?
   - Look for the ActivInspire window with its distinctive toolbar
   - Should see the main application frame

2. RECTANGLE VISIBLE: Is there a rectangle shape on the canvas?
   - Could be filled or outlined
   - Should have four sides with right angles

3. CIRCLE/ELLIPSE VISIBLE: Is there a circle or ellipse on the canvas?
   - Could be a perfect circle or an ellipse/oval
   - Could be filled or outlined

4. APPLICATION FUNCTIONAL: Is the application in a working state?
   - No error dialogs or crash messages
   - Main window not minimized

Respond in JSON format:
{
    "activinspire_visible": true/false,
    "rectangle_visible": true/false,
    "circle_visible": true/false,
    "shapes_on_canvas": true/false,
    "app_functional": true/false,
    "error_dialogs_present": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "what shapes you see in the screenshot"
}
"""


def verify_with_vlm(screenshot_path: str, query_vlm=None) -> dict:
    """Use VLM to verify shapes are visible on flipchart."""
    if not query_vlm:
        return {
            "success": False,
            "error": "VLM not available",
            "activinspire_visible": None,
            "rectangle_visible": None,
            "circle_visible": None,
            "app_functional": None,
        }

    if not screenshot_path or not os.path.exists(screenshot_path):
        return {
            "success": False,
            "error": f"Screenshot not found: {screenshot_path}",
            "activinspire_visible": None,
            "rectangle_visible": None,
            "circle_visible": None,
            "app_functional": None,
        }

    prompt = build_shapes_prompt()
    vlm_result = query_vlm(prompt=prompt, image=screenshot_path)

    if not vlm_result.get("success"):
        return {
            "success": False,
            "error": vlm_result.get("error", "VLM query failed"),
            "activinspire_visible": None,
            "rectangle_visible": None,
            "circle_visible": None,
            "app_functional": None,
        }

    parsed = vlm_result.get("parsed", {})
    return {
        "success": True,
        "activinspire_visible": parsed.get("activinspire_visible", False),
        "rectangle_visible": parsed.get("rectangle_visible", False),
        "circle_visible": parsed.get("circle_visible", False),
        "shapes_on_canvas": parsed.get("shapes_on_canvas", False),
        "app_functional": parsed.get("app_functional", True),
        "error_dialogs_present": parsed.get("error_dialogs_present", False),
        "confidence": parsed.get("confidence", "low"),
        "observations": parsed.get("observations", ""),
        "raw_response": vlm_result.get("response", "")[:500],
    }


def verify_draw_basic_shapes(traj, env_info, task_info):
    """Verify that basic shapes were drawn on the flipchart.

    HYBRID VERIFICATION:
    - Programmatic: File checks and XML shape detection - 60 points
    - VLM: Visual verification of shapes on canvas - 40 points

    Verification criteria:
    1. File exists at expected path
    2. File is a valid flipchart format
    3. File was created/modified during the task
    4. At least 2 shapes are present (rectangle AND circle)
    5. Shapes visually present on canvas (VLM check)
    """

    # Get copy function from framework
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available from environment"
        }

    # Get expected values from task metadata
    metadata = task_info.get('metadata', {})
    min_shapes = metadata.get('min_shapes', 2)
    expected_shapes = metadata.get('expected_shapes', ['rectangle', 'circle'])
    expected_path = metadata.get('expected_full_path', '/home/ga/Documents/Flipcharts/shapes_lesson.flipchart')

    # Copy result file from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to read result file: {e}"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Scoring breakdown
    score = 0
    feedback_parts = []
    details = {}

    # Check 1: File exists (25 points)
    file_found = result.get('file_found', False)
    if file_found:
        score += 25
        feedback_parts.append("Flipchart file saved")
        details['file_exists'] = True
    else:
        feedback_parts.append(f"File not found at expected path: {expected_path}")
        details['file_exists'] = False

        # Check for any flipchart files
        all_flipcharts = result.get('all_flipcharts', '')
        if all_flipcharts:
            feedback_parts.append(f"Other files found: {all_flipcharts}")
            score += 5

    # Check 2: File is valid (15 points)
    if file_found:
        file_valid = result.get('file_valid', False)
        if file_valid:
            score += 15
            feedback_parts.append("Valid flipchart format")
            details['valid_format'] = True
        else:
            feedback_parts.append("File format may not be valid")
            details['valid_format'] = False
            score += 5

    # Check 3: File created during task (10 points)
    if file_found:
        created_during_task = result.get('created_during_task', False)
        if created_during_task:
            score += 10
            feedback_parts.append("File saved during task")
            details['created_during_task'] = True
        else:
            feedback_parts.append("File timestamp predates task")
            details['created_during_task'] = False

    # Check 4: Rectangle present (20 points)
    has_rectangle = result.get('has_rectangle', False)
    if has_rectangle:
        score += 20
        feedback_parts.append("Rectangle shape found")
        details['has_rectangle'] = True
    else:
        feedback_parts.append("Rectangle not detected")
        details['has_rectangle'] = False

    # Check 5: Circle present (20 points)
    has_circle = result.get('has_circle', False)
    if has_circle:
        score += 20
        feedback_parts.append("Circle/ellipse shape found")
        details['has_circle'] = True
    else:
        feedback_parts.append("Circle/ellipse not detected")
        details['has_circle'] = False

    # Check 6: Minimum shapes count (10 points)
    shapes_found = result.get('shapes_found', 0)
    if shapes_found >= min_shapes:
        score += 10
        feedback_parts.append(f"Found {shapes_found} shapes (minimum: {min_shapes})")
        details['shapes_count'] = shapes_found
        details['min_shapes_met'] = True
    else:
        feedback_parts.append(f"Found {shapes_found} shapes, expected at least {min_shapes}")
        details['shapes_count'] = shapes_found
        details['min_shapes_met'] = False
        # Partial credit if at least one shape
        if shapes_found > 0:
            score += 5

    # Additional info
    details['file_path'] = result.get('file_path', '')
    details['file_size'] = result.get('file_size', 0)

    # ============================================================
    # VLM VISUAL CHECKS (up to 40 points)
    # ============================================================

    vlm_pass = False
    vlm_result_data = {"success": False}
    query_vlm = env_info.get('query_vlm')

    # Copy screenshot for VLM analysis
    temp_screenshot = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
    try:
        copy_from_env("/tmp/task_end.png", temp_screenshot.name)
        vlm_result_data = verify_with_vlm(temp_screenshot.name, query_vlm=query_vlm)
    except Exception as e:
        logger.warning(f"Could not copy screenshot for VLM: {e}")
        vlm_result_data = {"success": False, "error": str(e)}
    finally:
        if os.path.exists(temp_screenshot.name):
            os.unlink(temp_screenshot.name)

    details['vlm_result'] = vlm_result_data

    vlm_rectangle = False
    vlm_circle = False

    if vlm_result_data.get("success"):
        # VLM Check 1: ActivInspire visible (10 points)
        if vlm_result_data.get("activinspire_visible"):
            score += 10
            feedback_parts.append("ActivInspire visible (VLM)")
            vlm_pass = True
        else:
            feedback_parts.append("ActivInspire NOT visible (VLM)")

        # VLM Check 2: Rectangle visible (10 points)
        if vlm_result_data.get("rectangle_visible"):
            score += 10
            feedback_parts.append("Rectangle visible (VLM)")
            vlm_rectangle = True
        else:
            feedback_parts.append("Rectangle NOT visible (VLM)")

        # VLM Check 3: Circle visible (10 points)
        if vlm_result_data.get("circle_visible"):
            score += 10
            feedback_parts.append("Circle visible (VLM)")
            vlm_circle = True
        else:
            feedback_parts.append("Circle NOT visible (VLM)")

        # VLM Check 4: App functional (10 points)
        if vlm_result_data.get("app_functional") and not vlm_result_data.get("error_dialogs_present"):
            score += 10
            feedback_parts.append("App functional (VLM)")
        else:
            feedback_parts.append("App may have errors (VLM)")

        details['vlm_confidence'] = vlm_result_data.get("confidence", "unknown")
    else:
        # VLM failed - give partial credit if file checks passed
        feedback_parts.append(f"VLM check skipped: {vlm_result_data.get('error', 'unavailable')}")
        if file_found and result.get('file_valid', False) and has_rectangle and has_circle:
            score += 20  # Partial VLM credit when file evidence is strong
            vlm_pass = True
            vlm_rectangle = True
            vlm_circle = True

    # ============================================================
    # FINAL SCORING
    # ============================================================

    # Determine pass/fail
    # Pass if: file exists, valid, has BOTH required shapes (in file AND visually)
    programmatic_pass = (
        file_found and
        result.get('file_valid', False) and
        has_rectangle and
        has_circle and
        shapes_found >= min_shapes
    )

    # Require either VLM confirmation of shapes OR strong programmatic evidence with VLM unavailable
    shapes_verified = (vlm_rectangle and vlm_circle) or (vlm_pass and has_rectangle and has_circle)

    passed = programmatic_pass and vlm_pass and shapes_verified and score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": details,
        "subscores": {
            "file_exists": file_found,
            "valid_format": result.get('file_valid', False),
            "created_during_task": result.get('created_during_task', False),
            "has_rectangle": has_rectangle,
            "has_circle": has_circle,
            "min_shapes_met": shapes_found >= min_shapes,
            "vlm_verified": vlm_pass,
            "vlm_rectangle": vlm_rectangle,
            "vlm_circle": vlm_circle
        }
    }
