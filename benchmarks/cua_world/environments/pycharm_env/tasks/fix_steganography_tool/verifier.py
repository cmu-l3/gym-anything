#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_fix_steganography_tool(traj, env_info, task_info):
    """
    Verify fixes for steganography tool.
    
    Criteria:
    1. Visual Fidelity (30 pts): test_image_fidelity pass + correct mask code
    2. Message Recovery (30 pts): test_round_trip pass + correct base conversion
    3. Terminator (20 pts): test_terminator pass + break condition
    4. No Regression (20 pts): All tests pass cleanly
    
    Pass threshold: 60
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment access failed"}

    task_name = "fix_steganography_tool"
    result_path = f"/tmp/{task_name}_result.json"

    # Fetch result file
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
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}

    score = 0
    feedback = []

    # Check Fidelity (Bug 1)
    # The destructive mask (0x00) turns images black.
    # The correct mask (0xFE) preserves content.
    if result.get("test_fidelity_pass", False):
        score += 30
        feedback.append("Criterion 1: Visual fidelity restored (30/30)")
    else:
        feedback.append("Criterion 1 Fail: Encoded image is still visually corrupted")

    # Check Message Recovery (Bug 2)
    # Base 10 vs Base 2 conversion error
    if result.get("test_round_trip_pass", False):
        score += 30
        feedback.append("Criterion 2: Round-trip encoding/decoding works (30/30)")
    else:
        feedback.append("Criterion 2 Fail: Message cannot be decoded correctly")

    # Check Terminator (Bug 3)
    # Reading past end of message
    if result.get("test_terminator_pass", False):
        score += 20
        feedback.append("Criterion 3: Terminator handled correctly (20/20)")
    else:
        feedback.append("Criterion 3 Fail: Decoder reads garbage past message end")

    # Check Clean Pass
    if result.get("pytest_exit_code") == 0 and result.get("tests_failed") == 0:
        score += 20
        feedback.append("Criterion 4: Test suite passes cleanly (20/20)")
    
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }