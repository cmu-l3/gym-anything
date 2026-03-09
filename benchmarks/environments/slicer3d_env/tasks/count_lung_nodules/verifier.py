#!/usr/bin/env python3
"""
Verifier for count_lung_nodules task.

Scoring:
- Fiducials exist: 25 points
- Correct count (within ±1): 30 points
- VLM: fiducials on nodules: 35 points
- File saved: 10 points
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def build_nodule_prompt():
    """Build VLM prompt to verify fiducial placement on nodules."""
    return """Examine this 3D Slicer screenshot showing a chest CT with lung window settings.

Task: Verify that point fiducials have been placed on lung nodules.

Check for:
1. FIDUCIALS VISIBLE: Are there point markers visible on the image?
   - Look for colored dots/spheres (often red, green, or yellow)
   - May have labels like "F-1", "F-2", etc.

2. FIDUCIALS ON NODULES: Are markers placed on lung nodules?
   - Lung nodules are small, round, bright spots in dark lung tissue
   - The lung tissue appears dark/black with lung window settings
   - Nodules appear as white/gray round spots

3. REASONABLE COUNT: Are there multiple fiducials marking different nodules?
   - Each nodule should have one marker
   - Look for 2-4 markers if nodules are visible

Respond in JSON format:
{
    "fiducials_visible": true/false,
    "fiducials_on_nodules": true/false,
    "approximate_fiducial_count": <number>,
    "confidence": "low"/"medium"/"high",
    "observations": "description"
}
"""


def verify_with_vlm(screenshot_path: str, query_vlm=None) -> dict:
    """Use VLM to verify fiducial placement."""
    if not query_vlm:
        return {"success": False, "error": "VLM not available"}

    if not screenshot_path or not os.path.exists(screenshot_path):
        return {"success": False, "error": "Screenshot not found"}

    prompt = build_nodule_prompt()
    vlm_result = query_vlm(prompt=prompt, image=screenshot_path)

    if not vlm_result.get("success"):
        return {"success": False, "error": vlm_result.get("error", "VLM failed")}

    parsed = vlm_result.get("parsed", {})
    return {
        "success": True,
        "fiducials_visible": parsed.get("fiducials_visible", False),
        "on_nodules": parsed.get("fiducials_on_nodules", False),
        "vlm_count": parsed.get("approximate_fiducial_count", 0),
        "confidence": parsed.get("confidence", "low"),
    }


def verify_count_lung_nodules(traj, env_info, task_info):
    """Verify nodule counting task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Framework error"}

    metadata = task_info.get('metadata', {})
    expected_count = metadata.get('expected_nodule_count', 3)
    min_pass = metadata.get('min_fiducials_to_pass', 2)

    # Copy result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/count_nodules_result.json", temp_result.name)
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

    # Get fiducial count
    count_file = int(result.get('fiducial_count_file', 0))
    count_slicer = int(result.get('fiducial_count_slicer', 0))
    fiducial_count = max(count_file, count_slicer)
    details['fiducial_count'] = fiducial_count

    # Check 1: Fiducials exist (25 points)
    if fiducial_count > 0:
        score += 25
        feedback_parts.append(f"Fiducials created ({fiducial_count}) (+25)")
    else:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No fiducials placed",
            "details": details
        }

    # Check 2: File saved (10 points)
    if result.get('fiducial_file_exists', False):
        score += 10
        feedback_parts.append("File saved (+10)")
    else:
        feedback_parts.append("File not saved")

    # Check 3: Count accuracy (30 points)
    count_diff = abs(fiducial_count - expected_count)
    details['expected_count'] = expected_count
    details['count_diff'] = count_diff

    if count_diff == 0:
        score += 30
        feedback_parts.append(f"Exact count (+30)")
    elif count_diff == 1:
        score += 20
        feedback_parts.append(f"Count off by 1 (+20)")
    elif count_diff <= 2:
        score += 10
        feedback_parts.append(f"Count off by {count_diff} (+10)")
    else:
        feedback_parts.append(f"Count off by {count_diff}")

    # Check 4: VLM verification (35 points)
    query_vlm = env_info.get('query_vlm')
    temp_screenshot = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
    try:
        copy_from_env("/tmp/nodule_final.png", temp_screenshot.name)
        vlm_result = verify_with_vlm(temp_screenshot.name, query_vlm=query_vlm)
    except Exception as e:
        vlm_result = {"success": False, "error": str(e)}
    finally:
        if os.path.exists(temp_screenshot.name):
            os.unlink(temp_screenshot.name)

    details['vlm_result'] = vlm_result

    if vlm_result.get("success"):
        vlm_score = 0
        if vlm_result.get("fiducials_visible"):
            vlm_score += 10
        if vlm_result.get("on_nodules"):
            vlm_score += 25
        score += vlm_score
        feedback_parts.append(f"VLM (+{vlm_score})")
    else:
        # Partial credit
        if fiducial_count >= min_pass:
            score += 15
            feedback_parts.append("VLM unavailable, partial credit (+15)")

    passed = score >= 50 and fiducial_count >= min_pass

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) + f" | {'PASSED' if passed else 'FAILED'} ({score}/100)",
        "details": details
    }
