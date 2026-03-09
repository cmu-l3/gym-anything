#!/usr/bin/env python3
"""
Verifier for scroll_one_slice_measure_aorta task.

Scoring:
- Measurement exists: 25 points
- Scrolled from initial: 15 points
- Diameter accuracy: 30 points
- VLM: measurement on aorta: 20 points
- File saved: 10 points
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def build_aorta_prompt():
    """Build VLM prompt to verify aorta measurement."""
    return """Examine this 3D Slicer screenshot showing an abdominal CT scan.

Task: Verify that a Line measurement has been placed on the aorta.

Check for:
1. LINE MEASUREMENT VISIBLE: Is there a line with endpoints?
   - Look for a colored line (green/yellow) with circular endpoint markers
   - Should span across a circular structure

2. MEASUREMENT ON AORTA: Is the line on the correct vessel?
   - The aorta is the large CIRCULAR vessel
   - Located to the LEFT of the spine (bright white bone)
   - It's anterior to the spine, roughly in the center-left of the abdomen
   - NOT the IVC (which is to the RIGHT of the aorta)

3. MEASUREMENT SPANS DIAMETER: Does the line go across the vessel?
   - Should measure the full width of the circular structure
   - Not just a partial measurement

Respond in JSON format:
{
    "line_measurement_visible": true/false,
    "measurement_on_aorta": true/false,
    "measurement_spans_diameter": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "description"
}
"""


def verify_with_vlm(screenshot_path: str, query_vlm=None) -> dict:
    """Use VLM to verify aorta measurement."""
    if not query_vlm:
        return {"success": False, "error": "VLM not available"}

    if not screenshot_path or not os.path.exists(screenshot_path):
        return {"success": False, "error": "Screenshot not found"}

    prompt = build_aorta_prompt()
    vlm_result = query_vlm(prompt=prompt, image=screenshot_path)

    if not vlm_result.get("success"):
        return {"success": False, "error": vlm_result.get("error", "VLM failed")}

    parsed = vlm_result.get("parsed", {})
    return {
        "success": True,
        "line_visible": parsed.get("line_measurement_visible", False),
        "on_aorta": parsed.get("measurement_on_aorta", False),
        "spans_diameter": parsed.get("measurement_spans_diameter", False),
        "confidence": parsed.get("confidence", "low"),
    }


def verify_scroll_one_slice_measure_aorta(traj, env_info, task_info):
    """Verify scroll and measure aorta task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Framework error"}

    metadata = task_info.get('metadata', {})
    gt_diameter = metadata.get('ground_truth_diameter_mm', 25.0)
    tolerance = metadata.get('tolerance_mm', 10.0)

    # Copy result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/scroll_aorta_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"No result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    details = {}

    if not result.get('slicer_running', False):
        return {"passed": False, "score": 0, "feedback": "Slicer not running"}

    # Check 1: Measurement exists (25 points)
    measurement_exists = result.get('measurement_file_exists', False)
    measured = float(result.get('measured_length_mm', 0))
    details['measurement_exists'] = measurement_exists
    details['measured_mm'] = measured

    if measurement_exists and measured > 0:
        score += 25
        feedback_parts.append(f"Measurement created ({measured:.1f}mm) (+25)")
    else:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No measurement created",
            "details": details
        }

    # Check 2: Scrolled from initial (15 points)
    initial_pos = float(result.get('initial_slice_position', 0))
    current_pos = float(result.get('current_slice_position', 0))
    optimal_pos = float(result.get('optimal_slice_position', 0))
    details['initial_position'] = initial_pos
    details['current_position'] = current_pos
    details['optimal_position'] = optimal_pos

    scroll_distance = abs(current_pos - initial_pos)
    if scroll_distance > 1.0:  # Scrolled at least a bit
        score += 15
        feedback_parts.append(f"Scrolled ({scroll_distance:.1f}mm) (+15)")
    else:
        feedback_parts.append("Did not scroll from initial position")

    # Check 3: File saved (10 points)
    if measurement_exists:
        score += 10
        feedback_parts.append("File saved (+10)")

    # Check 4: Diameter accuracy (30 points)
    error = abs(measured - gt_diameter)
    details['diameter_error_mm'] = error

    if error <= tolerance:
        score += 30
        feedback_parts.append(f"Diameter accurate ({error:.1f}mm error) (+30)")
    elif error <= tolerance * 2:
        score += 15
        feedback_parts.append(f"Diameter partial ({error:.1f}mm error) (+15)")
    else:
        feedback_parts.append(f"Diameter inaccurate ({error:.1f}mm error)")

    # Check 5: VLM verification (20 points)
    query_vlm = env_info.get('query_vlm')
    temp_screenshot = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
    try:
        copy_from_env("/tmp/scroll_aorta_final.png", temp_screenshot.name)
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
            vlm_score += 5
        if vlm_result.get("on_aorta"):
            vlm_score += 10
        if vlm_result.get("spans_diameter"):
            vlm_score += 5
        score += vlm_score
        feedback_parts.append(f"VLM (+{vlm_score})")
    else:
        if measurement_exists:
            score += 10
            feedback_parts.append("VLM unavailable, partial (+10)")

    passed = score >= 50

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) + f" | {'PASSED' if passed else 'FAILED'} ({score}/100)",
        "details": details
    }
