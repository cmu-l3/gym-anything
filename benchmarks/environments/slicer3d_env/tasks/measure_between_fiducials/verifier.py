#!/usr/bin/env python3
"""
Verifier for measure_between_fiducials task.

Scoring:
- Line measurement exists: 35 points
- Distance accuracy: 35 points
- File saved: 15 points
- Endpoints near fiducials: 15 points
"""

import json
import os
import tempfile
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def build_fiducial_measure_prompt():
    """Build VLM prompt to verify measurement between fiducials."""
    return """Examine this 3D Slicer screenshot showing a brain MRI with fiducials and a measurement.

Task: Verify that a Line measurement connects the two fiducial points.

Check for:
1. LINE MEASUREMENT VISIBLE: Is there a line measurement on the image?
   - Look for a colored line spanning across the brain
   - Should have endpoint markers

2. TWO FIDUCIALS VISIBLE: Are Point_A and Point_B fiducials visible?
   - Should see labeled point markers

3. LINE CONNECTS FIDUCIALS: Does the measurement line go from one fiducial to the other?
   - The line should span from left to right side of the brain
   - Endpoints should be at or very near the fiducial markers

Respond in JSON format:
{
    "line_measurement_visible": true/false,
    "fiducials_visible": true/false,
    "line_connects_fiducials": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "description"
}
"""


def verify_with_vlm(screenshot_path: str, query_vlm=None) -> dict:
    """Use VLM to verify the measurement."""
    if not query_vlm:
        return {"success": False, "error": "VLM not available"}

    if not screenshot_path or not os.path.exists(screenshot_path):
        return {"success": False, "error": "Screenshot not found"}

    prompt = build_fiducial_measure_prompt()
    vlm_result = query_vlm(prompt=prompt, image=screenshot_path)

    if not vlm_result.get("success"):
        return {"success": False, "error": vlm_result.get("error", "VLM failed")}

    parsed = vlm_result.get("parsed", {})
    return {
        "success": True,
        "line_visible": parsed.get("line_measurement_visible", False),
        "fiducials_visible": parsed.get("fiducials_visible", False),
        "connects_fiducials": parsed.get("line_connects_fiducials", False),
        "confidence": parsed.get("confidence", "low"),
    }


def point_distance(p1_str, p2_str):
    """Calculate distance between two points given as comma-separated strings."""
    try:
        p1 = [float(x) for x in p1_str.split(',')]
        p2 = [float(x) for x in p2_str.split(',')]
        return math.sqrt(sum((a-b)**2 for a,b in zip(p1, p2)))
    except:
        return float('inf')


def verify_measure_between_fiducials(traj, env_info, task_info):
    """Verify measurement between fiducials task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Framework error"}

    metadata = task_info.get('metadata', {})
    tolerance = metadata.get('tolerance_mm', 15.0)

    # Copy result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/measure_fiducials_result.json", temp_result.name)
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

    # Check 1: Line measurement exists (35 points)
    measurement_exists = result.get('measurement_file_exists', False)
    measured = float(result.get('measured_length_mm', 0))
    details['measurement_exists'] = measurement_exists
    details['measured_mm'] = measured

    if measurement_exists and measured > 0:
        score += 35
        feedback_parts.append(f"Line measurement created ({measured:.1f}mm) (+35)")
    else:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No line measurement created",
            "details": details
        }

    # Check 2: File saved (15 points)
    score += 15
    feedback_parts.append("File saved (+15)")

    # Check 3: Distance accuracy (35 points)
    gt_distance = float(result.get('ground_truth_distance_mm', 80.0))
    error = abs(measured - gt_distance)
    details['distance_error_mm'] = error

    if error <= tolerance:
        score += 35
        feedback_parts.append(f"Distance accurate ({error:.1f}mm error) (+35)")
    elif error <= tolerance * 2:
        score += 20
        feedback_parts.append(f"Distance partial ({error:.1f}mm error) (+20)")
    else:
        feedback_parts.append(f"Distance inaccurate ({error:.1f}mm error)")

    # Check 4: Endpoints near fiducials (15 points)
    endpoint_1 = result.get('endpoint_1', '0,0,0')
    endpoint_2 = result.get('endpoint_2', '0,0,0')
    gt_point_a = result.get('ground_truth_point_a', '0,0,0')
    gt_point_b = result.get('ground_truth_point_b', '0,0,0')

    # Check if endpoints are near the fiducials (either order)
    dist_1a = point_distance(endpoint_1, gt_point_a)
    dist_1b = point_distance(endpoint_1, gt_point_b)
    dist_2a = point_distance(endpoint_2, gt_point_a)
    dist_2b = point_distance(endpoint_2, gt_point_b)

    # Best matching (A-B or B-A order)
    match_1 = min(dist_1a + dist_2b, dist_1b + dist_2a)
    details['endpoint_match_error_mm'] = match_1

    if match_1 <= 30:  # Within 30mm total
        score += 15
        feedback_parts.append(f"Endpoints near fiducials (+15)")
    elif match_1 <= 60:
        score += 8
        feedback_parts.append(f"Endpoints partially near (+8)")
    else:
        feedback_parts.append(f"Endpoints not near fiducials")

    # VLM check (bonus confidence)
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        temp_screenshot = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        try:
            copy_from_env("/tmp/fiducial_measure_final.png", temp_screenshot.name)
            vlm_result = verify_with_vlm(temp_screenshot.name, query_vlm=query_vlm)
            details['vlm_result'] = vlm_result
        except:
            pass
        finally:
            if os.path.exists(temp_screenshot.name):
                os.unlink(temp_screenshot.name)

    passed = score >= 50

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) + f" | {'PASSED' if passed else 'FAILED'} ({score}/100)",
        "details": details
    }
