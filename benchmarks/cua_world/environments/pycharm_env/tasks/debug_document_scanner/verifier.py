#!/usr/bin/env python3
import json
import os
import tempfile

def verify_debug_document_scanner(traj, env_info, task_info):
    """
    Verify fixes for the document scanner pipeline.
    
    Scoring:
    - Bug 1 (Contour Selection): 30 pts (Test passes + Static check)
    - Bug 2 (Geometry Logic): 30 pts (Test passes + Static check)
    - Bug 3 (Threshold Crash): 20 pts (Test passes)
    - End-to-End Pipeline: 20 pts (Hidden image processed successfully)
    
    Pass Threshold: 70 pts
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    task_name = "debug_document_scanner"
    result_path = f"/tmp/{task_name}_result.json"

    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix=".json") as tmp:
            tmp_path = tmp.name
        try:
            copy_from_env(result_path, tmp_path)
            with open(tmp_path, "r") as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}

    score = 0
    feedback = []

    # --- Bug 1: Contour Selection (30 pts) ---
    # Must sort contours by area to pick the document, not noise
    if result.get("test_contour_pass", False):
        score += 20
        feedback.append("Contour selection test passed (+20)")
        if result.get("code_fix_sort", False):
            score += 10
            feedback.append("Contour sorting code verified (+10)")
    else:
        feedback.append("Contour selection test FAILED (Is contour sorting implemented?)")

    # --- Bug 2: Geometry/Ordering (30 pts) ---
    # Must correct the rect point assignment
    if result.get("test_geom_pass", False):
        score += 20
        feedback.append("Geometry logic test passed (+20)")
        if result.get("code_fix_geom", False):
            score += 10
            feedback.append("Geometry code fix verified (+10)")
    else:
        feedback.append("Geometry test FAILED (Check order_points logic)")

    # --- Bug 3: Threshold Crash (20 pts) ---
    # Must use odd block size
    if result.get("test_threshold_pass", False):
        score += 20
        feedback.append("Thresholding test passed (+20)")
    else:
        feedback.append("Thresholding test FAILED (Did you fix the blockSize?)")

    # --- End-to-End Verification (20 pts) ---
    # Run on hidden image
    if result.get("pipeline_success", False):
        aspect = result.get("output_aspect", 0)
        # Expected aspect ratio for our 300x500 receipt is 0.6
        # Allow some tolerance for perspective distortion
        if 0.5 <= aspect <= 0.7:
            score += 20
            feedback.append("Hidden image processed with correct dimensions (+20)")
        else:
            score += 10
            feedback.append(f"Hidden image processed but aspect ratio suspicious ({aspect:.2f}) (+10)")
    else:
        feedback.append("Pipeline failed on hidden test image")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }