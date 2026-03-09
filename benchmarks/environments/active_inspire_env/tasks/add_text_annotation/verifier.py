#!/usr/bin/env python3
"""Verifier for add_text_annotation task.

HYBRID VERIFICATION: Combines programmatic file checks with VLM-based visual verification.

Programmatic checks:
- File exists at expected path
- File is valid flipchart format (ZIP with XML)
- Expected text content found in XML

VLM checks:
- ActivInspire is running and visible
- Flipchart with text annotation is displayed
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def build_text_annotation_prompt(expected_text: str):
    """Build VLM prompt to verify text annotation is visible."""
    return f"""Examine this screenshot of an ActivInspire session.

Task: Verify that ActivInspire is running and showing a flipchart with text annotation.

The expected text annotation is: "{expected_text}"

Check for these indicators:

1. APPLICATION VISIBLE: Is ActivInspire software visible?
   - Look for the ActivInspire window with its distinctive toolbar
   - Should see the main application frame

2. TEXT VISIBLE: Is there visible text on the flipchart canvas?
   - Look for any text that resembles the expected phrase
   - Text might be styled (bold, colored, different font)
   - Partial match counts if key words like "Welcome" or "Lesson" are visible

3. APPLICATION FUNCTIONAL: Is the application in a working state?
   - No error dialogs or crash messages
   - Main window not minimized

Respond in JSON format:
{{
    "activinspire_visible": true/false,
    "text_visible_on_canvas": true/false,
    "expected_text_found": true/false,
    "app_functional": true/false,
    "error_dialogs_present": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "what you see in the screenshot"
}}
"""


def verify_with_vlm(screenshot_path: str, expected_text: str, query_vlm=None) -> dict:
    """Use VLM to verify text annotation is visible on flipchart."""
    if not query_vlm:
        return {
            "success": False,
            "error": "VLM not available",
            "activinspire_visible": None,
            "text_visible_on_canvas": None,
            "app_functional": None,
        }

    if not screenshot_path or not os.path.exists(screenshot_path):
        return {
            "success": False,
            "error": f"Screenshot not found: {screenshot_path}",
            "activinspire_visible": None,
            "text_visible_on_canvas": None,
            "app_functional": None,
        }

    prompt = build_text_annotation_prompt(expected_text)
    vlm_result = query_vlm(prompt=prompt, image=screenshot_path)

    if not vlm_result.get("success"):
        return {
            "success": False,
            "error": vlm_result.get("error", "VLM query failed"),
            "activinspire_visible": None,
            "text_visible_on_canvas": None,
            "app_functional": None,
        }

    parsed = vlm_result.get("parsed", {})
    return {
        "success": True,
        "activinspire_visible": parsed.get("activinspire_visible", False),
        "text_visible_on_canvas": parsed.get("text_visible_on_canvas", False),
        "expected_text_found": parsed.get("expected_text_found", False),
        "app_functional": parsed.get("app_functional", True),
        "error_dialogs_present": parsed.get("error_dialogs_present", False),
        "confidence": parsed.get("confidence", "low"),
        "observations": parsed.get("observations", ""),
        "raw_response": vlm_result.get("response", "")[:500],
    }


def verify_add_text_annotation(traj, env_info, task_info):
    """Verify that text annotation was added to a flipchart.

    HYBRID VERIFICATION:
    - Programmatic: File checks and text content search - 60 points
    - VLM: Visual verification of text on canvas - 40 points

    Verification criteria:
    1. File exists at expected path
    2. File is a valid flipchart format
    3. File was created/modified during the task
    4. Expected text content is present in the flipchart
    5. ActivInspire visually shows text (VLM check)
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
    expected_text = metadata.get('expected_text', "Welcome to Today's Lesson")
    expected_path = metadata.get('expected_full_path', '/home/ga/Documents/Flipcharts/lesson_with_text.flipchart')

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

    # Check 1: File exists (30 points)
    file_found = result.get('file_found', False)
    if file_found:
        score += 30
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

    # Check 2: File is valid (20 points)
    if file_found:
        file_valid = result.get('file_valid', False)
        if file_valid:
            score += 20
            feedback_parts.append("Valid flipchart format")
            details['valid_format'] = True
        else:
            feedback_parts.append("File format may not be valid")
            details['valid_format'] = False
            score += 5

    # Check 3: File created during task (15 points)
    if file_found:
        created_during_task = result.get('created_during_task', False)
        if created_during_task:
            score += 15
            feedback_parts.append("File saved during task")
            details['created_during_task'] = True
        else:
            feedback_parts.append("File timestamp predates task")
            details['created_during_task'] = False

    # Check 4: Text content found (35 points)
    text_found = result.get('text_found', 'false')
    if text_found == 'true' or text_found is True:
        score += 35
        feedback_parts.append(f"Expected text found in flipchart")
        details['text_found'] = True
    elif text_found == 'partial':
        score += 20
        feedback_parts.append("Partial text match found")
        details['text_found'] = 'partial'
    else:
        feedback_parts.append(f"Expected text not found: '{expected_text}'")
        details['text_found'] = False

    # Additional info
    details['file_path'] = result.get('file_path', '')
    details['file_size'] = result.get('file_size', 0)
    details['expected_text'] = expected_text

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
        vlm_result_data = verify_with_vlm(temp_screenshot.name, expected_text, query_vlm=query_vlm)
    except Exception as e:
        logger.warning(f"Could not copy screenshot for VLM: {e}")
        vlm_result_data = {"success": False, "error": str(e)}
    finally:
        if os.path.exists(temp_screenshot.name):
            os.unlink(temp_screenshot.name)

    details['vlm_result'] = vlm_result_data

    if vlm_result_data.get("success"):
        # VLM Check 1: ActivInspire visible (10 points)
        if vlm_result_data.get("activinspire_visible"):
            score += 10
            feedback_parts.append("ActivInspire visible (VLM)")
            vlm_pass = True
        else:
            feedback_parts.append("ActivInspire NOT visible (VLM)")

        # VLM Check 2: Text visible on canvas (20 points)
        if vlm_result_data.get("text_visible_on_canvas"):
            score += 20
            feedback_parts.append("Text visible on canvas (VLM)")
        elif vlm_result_data.get("expected_text_found"):
            score += 20
            feedback_parts.append("Expected text found (VLM)")
        else:
            feedback_parts.append("No text visible on canvas (VLM)")

        # VLM Check 3: App functional (10 points)
        if vlm_result_data.get("app_functional") and not vlm_result_data.get("error_dialogs_present"):
            score += 10
            feedback_parts.append("App functional (VLM)")
        else:
            feedback_parts.append("App may have errors (VLM)")

        details['vlm_confidence'] = vlm_result_data.get("confidence", "unknown")
    else:
        # VLM failed - give partial credit if file checks passed
        feedback_parts.append(f"VLM check skipped: {vlm_result_data.get('error', 'unavailable')}")
        if file_found and result.get('file_valid', False) and text_found in ['true', True, 'partial']:
            score += 20  # Partial VLM credit when file evidence is strong
            vlm_pass = True

    # ============================================================
    # FINAL SCORING
    # ============================================================

    # Determine pass/fail
    # Pass if: file exists, is valid, text is found, AND visual check passes
    programmatic_pass = (
        file_found and
        result.get('file_valid', False) and
        text_found in ['true', True, 'partial']
    )
    passed = programmatic_pass and vlm_pass and score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": details,
        "subscores": {
            "file_exists": file_found,
            "valid_format": result.get('file_valid', False),
            "created_during_task": result.get('created_during_task', False),
            "text_found": text_found in ['true', True, 'partial'],
            "vlm_verified": vlm_pass
        }
    }
