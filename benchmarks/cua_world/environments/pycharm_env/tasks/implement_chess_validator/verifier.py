#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_implement_chess_validator(traj, env_info, task_info):
    """
    Verify that the chess move validator was implemented correctly.
    Criteria:
    1. Tests passed (score based on passed count)
    2. Files modified during task
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Read result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    passed_count = result.get("tests_passed", 0)
    failed_count = result.get("tests_failed", 0)
    total_tests = passed_count + failed_count
    
    score = 0
    feedback = []

    # Scoring breakdown
    # Total ~42 tests implies approx 2.4 pts per test
    # We use the specific category flags for weighted scoring
    
    if result.get("pawn_pass"):
        score += 15
        feedback.append("Pawn moves implemented")
    if result.get("knight_pass"):
        score += 10
        feedback.append("Knight moves implemented")
    if result.get("rook_pass"):
        score += 10
        feedback.append("Rook moves implemented")
    if result.get("check_pass"):
        score += 25
        feedback.append("Check detection implemented")
    if result.get("game_pass"):
        score += 20
        feedback.append("Integration game replay passed")
    
    # Remaining points for general test coverage
    # If 100% tests passed, cap at 100
    if failed_count == 0 and total_tests > 0:
        score = 100
        feedback.append("All tests passed!")
    elif total_tests > 0:
        ratio = passed_count / total_tests
        # Add remaining 20 pts based on ratio
        score += int(20 * ratio)
    
    # Anti-gaming check
    if not result.get("files_modified", False):
        score = 0
        feedback = ["Files were not modified during the task."]
    
    score = min(100, score)
    passed = score >= task_info['metadata'].get('pass_threshold', 60)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": result
    }