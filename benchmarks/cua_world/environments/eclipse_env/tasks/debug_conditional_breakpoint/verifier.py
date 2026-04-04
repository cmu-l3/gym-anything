#!/usr/bin/env python3
"""Verifier for debug_conditional_breakpoint task."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_debug_conditional_breakpoint(traj, env_info, task_info):
    """Verify the agent found the bug using the debugger without modifying code.

    Criteria:
    1. Solution file contains correct Transaction ID (50 pts)
    2. Source code integrity preserved (no printf debugging) (40 pts)
    3. Debugging evidence (VLM + System state) (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    correct_id = metadata.get('correct_transaction_id', 'TX-3842')

    score = 0
    feedback_parts = []

    # Read result JSON
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        copy_from_env("/tmp/task_result.json", tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
        os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}

    # --- Criterion 1: Correct Solution (50 points) ---
    solution_content = result.get('solution_content', '').strip()
    if correct_id in solution_content:
        score += 50
        feedback_parts.append(f"Correct Transaction ID found ({correct_id})")
    else:
        feedback_parts.append(f"Incorrect ID. Expected '{correct_id}', got '{solution_content}'")

    # --- Criterion 2: Source Code Integrity (40 points) ---
    # This prevents the agent from adding System.out.println() to find the ID
    integrity_passed = result.get('integrity_passed', False)
    if integrity_passed:
        score += 40
        feedback_parts.append("Source code unmodified (clean debugging)")
    else:
        feedback_parts.append("FAIL: Source code modified. You must use the debugger, not print statements.")
        # If integrity fails, we heavily penalize, potentially failing the task
        # But we adhere to the point structure. They lose 40 pts.

    # --- Criterion 3: Evidence of Debugging (10 points) ---
    debug_score = 0
    if result.get('breakpoint_set'):
        debug_score += 5
    if result.get('launch_config_exists'):
        debug_score += 5
    
    # VLM Verification for Debug Perspective/Conditional Breakpoint
    try:
        import sys
        sys.path.insert(0, '/workspace/utils')
        from eclipse_verification_utils import vlm_verify_eclipse_task

        vlm_result = vlm_verify_eclipse_task(
            traj, env_info,
            task_description="Use Eclipse Conditional Breakpoint to find data anomaly",
            checklist_items=[
                "Eclipse Debug perspective or Debug view is visible",
                "A breakpoint marker (blue dot) is visible in the editor gutter",
                "The Variables view shows 'currentTransaction' or 'currentBalance'",
                "Breakpoint Properties dialog or Conditional setting is visible (optional but good)"
            ]
        )
        
        if vlm_result and vlm_result.get('vlm_passed'):
            # Bonus or verification confirmation
            # If system checks failed but VLM confirms debug view, grant points
            if debug_score < 10:
                debug_score = 10
                feedback_parts.append("VLM confirmed debugging UI")
            else:
                feedback_parts.append("VLM confirmed debugging UI")
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")

    score += debug_score
    feedback_parts.append(f"Debug evidence: {debug_score}/10 pts")

    # Final Pass/Fail logic
    # Must have correct ID AND integrity passed
    passed = (correct_id in solution_content) and integrity_passed and (score >= 90)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }