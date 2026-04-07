#!/usr/bin/env python3
"""
Verifier for the fix_svg_animation_generator task.

Checks whether the agent fixed the 5 injected bugs in the SVG generator.
Verification relies primarily on the test suite execution results captured
in export_result.sh, since original test files are restored before running.

Each bug fix is worth 20 points (total 100, pass threshold 60).
"""

import os
import json
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_svg_animator(traj, env_info, task_info):
    """
    Verify that the SVG animator bug fixes pass the restored test suite.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy the result JSON from the container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/svg_animator_result.json", temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8') as f:
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

    score = 0
    feedback_parts = []
    tests = result.get("tests", {})

    # 1. Bug 1: Bézier Interpolator parameters swapped
    if tests.get("test_cubic_bezier_asymmetric") == "passed":
        score += 20
        feedback_parts.append("✅ Bézier interpolation fixed")
    else:
        feedback_parts.append("❌ Bézier interpolation still broken")

    # 2. Bug 2: HSL to RGB sector mapping shifted
    # Check both red (sector 0) and blue (sector 4) mapping
    if tests.get("test_hsl_to_rgb_red") == "passed" and tests.get("test_hsl_to_rgb_blue") == "passed":
        score += 20
        feedback_parts.append("✅ HSL to RGB conversion fixed")
    else:
        feedback_parts.append("❌ HSL to RGB conversion still broken")

    # 3. Bug 3: SVG path arc flags swapped
    if tests.get("test_arc_to_flag_order") == "passed":
        score += 20
        feedback_parts.append("✅ SVG arc flag order fixed")
    else:
        feedback_parts.append("❌ SVG arc flag order still broken")

    # 4. Bug 4: Timeline drops last frame (exclusive range bound)
    if tests.get("test_generate_frame_times") == "passed":
        score += 20
        feedback_parts.append("✅ Timeline frame boundary fixed")
    else:
        feedback_parts.append("❌ Timeline frame boundary still broken")

    # 5. Bug 5: ViewBox width/height swapped
    if tests.get("test_render_svg_viewbox") == "passed":
        score += 20
        feedback_parts.append("✅ ViewBox dimensions fixed")
    else:
        feedback_parts.append("❌ ViewBox dimensions still broken")

    # General safety check
    if "error" in tests:
        feedback_parts.append(f"⚠️ Test suite runtime error: {tests['error']}")
    elif not tests:
        feedback_parts.append("⚠️ No test results found in export data")

    # Evaluate final criteria
    pass_threshold = task_info.get("metadata", {}).get("pass_threshold", 60)
    passed = score >= pass_threshold

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }