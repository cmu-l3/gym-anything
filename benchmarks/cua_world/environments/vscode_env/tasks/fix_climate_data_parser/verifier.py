#!/usr/bin/env python3
"""
Verifier for the fix_climate_data_parser task.

Evaluates if the agent correctly fixed the 5 data parsing bugs:
1. Fixed-width sign parsing extraction
2. Scaling factor adjustment
3. NOAA missing data sentinel check
4. Bounding box boolean logic
5. Valid array averaging division

Scores are assigned based on a hidden evaluation script run during the export step.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_climate_parser(traj, env_info, task_info):
    """
    Verify that the climate data parser bugs have been fixed.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        if not os.path.exists(temp_file.name) or os.path.getsize(temp_file.name) == 0:
            return {"passed": False, "score": 0, "feedback": "Result file not found or empty."}
            
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    eval_results = result.get("eval_results", {})
    errors = eval_results.get("errors", [])
    if errors:
        feedback_parts.append("Errors encountered during evaluation: " + "; ".join(errors))

    # Anti-gaming check: File modification timestamp
    if not result.get("file_modified_during_task", False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Failed: Source files were not modified during the task execution."
        }

    # Evaluate Bug 1: Sign parsing logic
    if eval_results.get("bug1_sign", False):
        score += 20
        feedback_parts.append("[+] Bug 1 (Sign Parsing): Fixed")
    else:
        feedback_parts.append("[-] Bug 1 (Sign Parsing): Not Fixed (failed extraction at index 87)")

    # Evaluate Bug 2: Scaling factor logic
    if eval_results.get("bug2_scale", False):
        score += 20
        feedback_parts.append("[+] Bug 2 (Scaling Factor): Fixed")
    else:
        feedback_parts.append("[-] Bug 2 (Scaling Factor): Not Fixed (did not divide by 10)")

    # Evaluate Bug 3: Missing data sentinel check
    if eval_results.get("bug3_sentinel", False):
        score += 20
        feedback_parts.append("[+] Bug 3 (Sentinel Value): Fixed")
    else:
        feedback_parts.append("[-] Bug 3 (Sentinel Value): Not Fixed (failed to handle '+9999')")

    # Evaluate Bug 4: Bounding Box Logic
    if eval_results.get("bug4_bbox", False):
        score += 20
        feedback_parts.append("[+] Bug 4 (Bounding Box): Fixed")
    else:
        feedback_parts.append("[-] Bug 4 (Bounding Box): Not Fixed (OR/AND logic error persists)")

    # Evaluate Bug 5: Averaging logic
    if eval_results.get("bug5_avg", False):
        score += 20
        feedback_parts.append("[+] Bug 5 (Averaging): Fixed")
    else:
        feedback_parts.append("[-] Bug 5 (Averaging): Not Fixed (still dividing by hardcoded 24)")

    pass_threshold = task_info.get("metadata", {}).get("pass_threshold", 60)
    passed = score >= pass_threshold

    feedback = "\n".join(feedback_parts)
    if passed:
        feedback = f"SUCCESS: Passed with {score} points.\n" + feedback
    else:
        feedback = f"FAILED: Scored {score} points (Threshold: {pass_threshold}).\n" + feedback

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }