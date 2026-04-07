#!/usr/bin/env python3
"""
Verifier for the debug_software_rasterizer task.

Uses a multi-signal approach:
1. Strict Programmatic: Checks the results of the hidden math test suite exported in JSON.
2. Anti-Gaming: Verifies that output.png was actually updated after task start.

Pass threshold: 60/100 points AND the output file must exist/be updated.
Each of the 5 mathematical bugs is worth 20 points.
"""

import os
import json
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_rasterizer(traj, env_info, task_info):
    """
    Verify the 3D software rasterizer bug fixes.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve the bundled JSON result from the container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/rasterizer_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported results: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    test_results = result_data.get("test_results", {})
    file_stats = result_data.get("file_stats", {})
    
    score = 0
    feedback_parts = []
    
    # Anti-gaming checks
    output_exists = file_stats.get("output_exists", False)
    output_updated = file_stats.get("output_updated", False)
    
    if not output_exists:
        return {
            "passed": False,
            "score": 0,
            "feedback": "FAILED: output.png was not generated. Ensure render.py runs successfully."
        }
        
    if not output_updated:
        feedback_parts.append("[!] output.png was not modified. Render may have crashed or was untouched.")
        # We do not fail immediately, but it's highly suspicious.

    # Grade the 5 hidden test cases
    tests = {
        'test_normal_calculation': 'Backface Culling Winding Order',
        'test_zbuffer_logic': 'Z-Buffer Depth Test Reversed',
        'test_perspective_divide': 'Perspective Divide by W',
        'test_barycentric': 'Barycentric X/Y Coordinate Mix-up',
        'test_viewport_matrix': 'Viewport Y-axis Inversion'
    }

    tests_passed = 0
    
    for test_key, label in tests.items():
        if test_results.get(test_key) is True:
            score += 20
            tests_passed += 1
            feedback_parts.append(f"[+] Fixed: {label} (+20 pts)")
        else:
            feedback_parts.append(f"[-] Still Buggy: {label}")

    passed = (score >= 60) and output_exists and output_updated

    if tests_passed == 5:
        feedback_parts.insert(0, "Excellent! All rendering pipeline math bugs fixed.")
    else:
        feedback_parts.insert(0, f"{tests_passed}/5 bugs fixed.")

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }