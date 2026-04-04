#!/usr/bin/env python3
"""
Verifier for place_fiducial_at_tumor_center task.

Scoring:
- Fiducial point exists: 35 points
- VLM: fiducial on tumor: 40 points
- File saved: 15 points
- Near computed center: 10 points
"""

import json
import os
import tempfile
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def build_fiducial_prompt():
    """Build VLM prompt to verify fiducial placement."""
    return """Examine this 3D Slicer screenshot showing a brain MRI.

Task: Verify that a point fiducial has been placed on the bright tumor region.

Check for:
1. FIDUCIAL VISIBLE: Is there a point marker visible on the image?
   - Look for a colored dot/sphere marker (often red, green, or yellow)
   - May have a label like "F-1" near it

2. FIDUCIAL ON TUMOR: Is the marker placed on the bright lesion?
   - The tumor is the bright/hyperintense region on the FLAIR MRI
   - The fiducial should be INSIDE this bright region
   - NOT on dark areas or normal brain tissue

3. FIDUCIAL NEAR CENTER: Is the marker approximately centered in the tumor?
   - Should be roughly in the middle of the bright region
   - Not at the very edge

Respond in JSON format:
{
    "fiducial_visible": true/false,
    "fiducial_on_tumor": true/false,
    "fiducial_near_center": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "description"
}
"""


def verify_with_vlm(screenshot_path: str, query_vlm=None) -> dict:
    """Use VLM to verify fiducial placement."""
    if not query_vlm:
        return {"success": False, "error": "VLM not available"}

    if not screenshot_path or not os.path.exists(screenshot_path):
        return {"success": False, "error": f"Screenshot not found"}

    prompt = build_fiducial_prompt()
    vlm_result = query_vlm(prompt=prompt, image=screenshot_path)

    if not vlm_result.get("success"):
        return {"success": False, "error": vlm_result.get("error", "VLM failed")}

    parsed = vlm_result.get("parsed", {})
    return {
        "success": True,
        "fiducial_visible": parsed.get("fiducial_visible", False),
        "on_tumor": parsed.get("fiducial_on_tumor", False),
        "near_center": parsed.get("fiducial_near_center", False),
        "confidence": parsed.get("confidence", "low"),
    }


def verify_place_fiducial_at_tumor_center(traj, env_info, task_info):
    """Verify fiducial placed at tumor center."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Framework error"}

    metadata = task_info.get('metadata', {})
    tolerance = metadata.get('tolerance_mm', 25.0)

    # Copy result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/fiducial_tumor_result.json", temp_result.name)
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

    # Check 1: Fiducial exists (35 points)
    fiducial_exists = result.get('point_markup_exists', False) or result.get('fiducial_file_exists', False)
    details['fiducial_exists'] = fiducial_exists

    if fiducial_exists:
        score += 35
        feedback_parts.append("Fiducial created (+35)")
    else:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No fiducial point created",
            "details": details
        }

    # Check 2: File saved (15 points)
    file_saved = result.get('fiducial_file_exists', False)
    if file_saved:
        score += 15
        feedback_parts.append("File saved (+15)")
    else:
        feedback_parts.append("File not saved")

    # Check 3: Distance to ground truth center (10 points)
    try:
        fid_pos = [float(x) for x in result.get('fiducial_position', '0,0,0').split(',')]
        gt_pos = [float(x) for x in result.get('ground_truth_position', '0,0,0').split(',')]
        distance = math.sqrt(sum((a-b)**2 for a,b in zip(fid_pos, gt_pos)))
        details['distance_to_center_mm'] = distance

        if distance <= tolerance:
            score += 10
            feedback_parts.append(f"Near center ({distance:.1f}mm) (+10)")
        else:
            feedback_parts.append(f"Far from center ({distance:.1f}mm)")
    except:
        feedback_parts.append("Could not verify position")

    # Check 4: VLM verification (40 points)
    query_vlm = env_info.get('query_vlm')
    temp_screenshot = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
    try:
        copy_from_env("/tmp/fiducial_final.png", temp_screenshot.name)
        vlm_result = verify_with_vlm(temp_screenshot.name, query_vlm=query_vlm)
    except Exception as e:
        vlm_result = {"success": False, "error": str(e)}
    finally:
        if os.path.exists(temp_screenshot.name):
            os.unlink(temp_screenshot.name)

    details['vlm_result'] = vlm_result

    if vlm_result.get("success"):
        vlm_score = 0
        if vlm_result.get("fiducial_visible"):
            vlm_score += 10
        if vlm_result.get("on_tumor"):
            vlm_score += 20
        if vlm_result.get("near_center"):
            vlm_score += 10
        score += vlm_score
        feedback_parts.append(f"VLM (+{vlm_score})")
    else:
        # Partial credit if file exists
        if file_saved:
            score += 20
            feedback_parts.append("VLM unavailable, partial credit (+20)")

    passed = score >= 50

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) + f" | {'PASSED' if passed else 'FAILED'} ({score}/100)",
        "details": details
    }
