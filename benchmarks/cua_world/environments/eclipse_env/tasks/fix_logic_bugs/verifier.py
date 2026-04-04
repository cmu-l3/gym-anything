#!/usr/bin/env python3
"""
Verifier for fix_logic_bugs task.

Grading Criteria:
1. Compilation Success (10 pts)
2. Discount Logic Fixed (30 pts) - Verified via hidden test
3. Shipping Logic Fixed (30 pts) - Verified via hidden test
4. Tax Logic Fixed (30 pts) - Verified via hidden test
5. VLM Verification (Bonus/Confirmation)
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_fix_logic_bugs(traj, env_info, task_info):
    """
    Verify that the agent fixed the three logic bugs in OrderService.java.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 1. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Check Compilation
    if result.get('compilation_success', False):
        score += 10
        feedback_parts.append("Project compiles.")
    else:
        feedback_parts.append("Project failed to compile.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback_parts)}

    # 3. Check Specific Bugs
    # Discount Bug
    if result.get('discount_fixed', False):
        score += 30
        feedback_parts.append("Discount logic fixed.")
    else:
        feedback_parts.append("Discount logic still incorrect.")

    # Shipping Bug
    if result.get('shipping_fixed', False):
        score += 30
        feedback_parts.append("Shipping threshold fixed.")
    else:
        feedback_parts.append("Shipping threshold still incorrect.")

    # Tax Bug
    if result.get('tax_fixed', False):
        score += 30
        feedback_parts.append("Tax switch-case fixed.")
    else:
        feedback_parts.append("Tax logic still incorrect.")

    # 4. Anti-gaming check
    if not result.get('file_modified_during_task', False):
        score = 0
        feedback_parts.append("CRITICAL: OrderService.java was not modified during the task.")

    # 5. VLM Verification (Optional but recommended)
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        # We assume VLM helper is available in the environment wrapper or imported
        # Here we mimic the utility check
        pass
    except ImportError:
        pass

    # Import VLM utility from task environment if possible, or skip
    # (Using the pattern from provided utils code)
    try:
        import sys
        # Assuming utils are in python path or accessible
        # For this output, we will simulate the check structure
        pass
    except Exception:
        pass

    passed = score >= 100
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }