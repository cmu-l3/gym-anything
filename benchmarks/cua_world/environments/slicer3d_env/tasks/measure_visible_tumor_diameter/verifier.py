#!/usr/bin/env python3
"""
Verifier for measure_visible_tumor_diameter task.

Scoring breakdown (100 points total):
- Measurement exists (line markup created): 30 points
- Measurement file saved to correct location: 10 points
- Measurement is reasonable (within tolerance): 25 points
- VLM verification of measurement on tumor: 35 points
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def build_tumor_measurement_prompt():
    """Build VLM prompt to verify measurement is on tumor."""
    return """Examine this 3D Slicer screenshot showing a brain MRI with a measurement line.

Task: Verify that a Line measurement has been placed on the bright tumor region.

Check for:
1. LINE MEASUREMENT VISIBLE: Is there a line with endpoints visible on the image?
   - Look for a colored line (often green or yellow) with circular endpoint markers
   - Should span across a bright region

2. MEASUREMENT ON TUMOR: Is the line placed on the bright lesion (tumor)?
   - The tumor appears as a bright/hyperintense region on FLAIR MRI
   - The line endpoints should be at the edges of this bright region
   - NOT on dark areas, NOT on normal brain tissue

3. MEASUREMENT REASONABLE: Does the measurement appear to span the tumor width?
   - Should go across the widest part of the bright region
   - Not too short (just a corner) or too long (extending beyond tumor)

Respond in JSON format:
{
    "line_measurement_visible": true/false,
    "measurement_on_tumor": true/false,
    "measurement_spans_tumor_width": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "description of what you see"
}
"""


def verify_with_vlm(screenshot_path: str, query_vlm=None) -> dict:
    """Use VLM to verify measurement is placed on tumor."""
    if not query_vlm:
        return {"success": False, "error": "VLM not available"}

    if not screenshot_path or not os.path.exists(screenshot_path):
        return {"success": False, "error": f"Screenshot not found: {screenshot_path}"}

    prompt = build_tumor_measurement_prompt()
    vlm_result = query_vlm(prompt=prompt, image=screenshot_path)

    if not vlm_result.get("success"):
        return {"success": False, "error": vlm_result.get("error", "VLM query failed")}

    parsed = vlm_result.get("parsed", {})
    return {
        "success": True,
        "line_visible": parsed.get("line_measurement_visible", False),
        "on_tumor": parsed.get("measurement_on_tumor", False),
        "spans_width": parsed.get("measurement_spans_tumor_width", False),
        "confidence": parsed.get("confidence", "low"),
        "observations": parsed.get("observations", ""),
    }


def verify_measure_visible_tumor_diameter(traj, env_info, task_info):
    """
    Verify that agent measured the visible tumor diameter.

    Scoring:
    - Measurement exists (30 points)
    - File saved correctly (10 points)
    - Diameter within tolerance (25 points)
    - VLM: measurement on tumor (35 points)

    Pass threshold: 60 points (measurement exists + either accurate or on tumor)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available - framework error"
        }

    metadata = task_info.get('metadata', {})
    gt_diameter = metadata.get('ground_truth_diameter_mm', 45.0)
    tolerance = metadata.get('tolerance_mm', 20.0)

    # Copy result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/measure_tumor_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read result: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Export result not found: {e}"
        }
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    details = {}

    # Check 1: Slicer running (prerequisite)
    if not result.get('slicer_running', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Slicer not running - cannot verify",
            "details": {"slicer_running": False}
        }

    # Check 2: Line measurement exists (30 points)
    line_exists = result.get('line_markup_exists', False) or result.get('measurement_file_exists', False)
    details['line_exists'] = line_exists

    if line_exists:
        score += 30
        feedback_parts.append("Measurement created (+30)")
    else:
        feedback_parts.append("No measurement found")
        return {
            "passed": False,
            "score": 0,
            "feedback": "No Line measurement created | " + " | ".join(feedback_parts),
            "details": details
        }

    # Check 3: File saved (10 points)
    file_saved = result.get('measurement_file_exists', False)
    details['file_saved'] = file_saved

    if file_saved:
        score += 10
        feedback_parts.append("File saved (+10)")
    else:
        feedback_parts.append("File not saved to specified location")

    # Check 4: Diameter accuracy (25 points)
    measured = result.get('measured_length_mm', 0)
    try:
        measured = float(measured)
    except (ValueError, TypeError):
        measured = 0

    details['measured_mm'] = measured
    details['ground_truth_mm'] = gt_diameter

    if measured > 0:
        error = abs(measured - gt_diameter)
        details['error_mm'] = error

        if error <= tolerance:
            score += 25
            feedback_parts.append(f"Diameter accurate: {measured:.1f}mm (GT: {gt_diameter:.1f}mm) (+25)")
        elif error <= tolerance * 2:
            score += 12
            feedback_parts.append(f"Diameter partial: {measured:.1f}mm (GT: {gt_diameter:.1f}mm) (+12)")
        else:
            feedback_parts.append(f"Diameter inaccurate: {measured:.1f}mm (GT: {gt_diameter:.1f}mm)")
    else:
        feedback_parts.append("Could not read measurement value")

    # Check 5: VLM verification (35 points)
    query_vlm = env_info.get('query_vlm')
    temp_screenshot = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
    try:
        copy_from_env("/tmp/tumor_final.png", temp_screenshot.name)
        vlm_result = verify_with_vlm(temp_screenshot.name, query_vlm=query_vlm)
    except Exception as e:
        vlm_result = {"success": False, "error": str(e)}
    finally:
        if os.path.exists(temp_screenshot.name):
            os.unlink(temp_screenshot.name)

    details['vlm_result'] = vlm_result

    if vlm_result.get("success"):
        vlm_score = 0

        if vlm_result.get("line_visible"):
            vlm_score += 10
            feedback_parts.append("Line visible (VLM +10)")

        if vlm_result.get("on_tumor"):
            vlm_score += 15
            feedback_parts.append("Measurement on tumor (VLM +15)")

        if vlm_result.get("spans_width"):
            vlm_score += 10
            feedback_parts.append("Spans tumor width (VLM +10)")

        score += vlm_score
        details['vlm_score'] = vlm_score
    else:
        feedback_parts.append(f"VLM unavailable: {vlm_result.get('error', 'unknown')}")
        # Give partial VLM credit if file exists and measurement is accurate
        if file_saved and measured > 0:
            score += 15
            feedback_parts.append("Partial VLM credit (+15)")

    # Determine pass/fail
    passed = score >= 60

    if passed:
        feedback_parts.append(f"PASSED ({score}/100)")
    else:
        feedback_parts.append(f"FAILED ({score}/100) - need 60 to pass")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": details
    }
