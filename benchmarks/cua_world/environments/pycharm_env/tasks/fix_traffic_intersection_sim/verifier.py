#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_fix_traffic_intersection_sim(traj, env_info, task_info):
    """
    Verify fixes for traffic simulation logic bugs.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy failed"}

    # Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/fix_traffic_intersection_sim_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Criterion 1: Bug 1 (Vehicle Gap Acceptance) - 30 pts
    # Checks: Test pass + Code fix + Zero collisions in sim
    c1_passed = False
    if result.get('bug1_fixed_code') or (result.get('sim_collisions', 99) == 0):
        # Code logic looks fixed or outcome is correct
        c1_passed = True
        score += 30
        feedback_parts.append("Bug 1 Fixed (Safe Turns)")
    else:
        feedback_parts.append("Bug 1 NOT Fixed (Unsafe Turns/Collisions)")

    # Criterion 2: Bug 2 (Signal Transition) - 30 pts
    # Checks: Test pass + Code fix + Zero violations in sim
    c2_passed = False
    if result.get('bug2_fixed_code') or (result.get('sim_violations', 99) == 0):
        c2_passed = True
        score += 30
        feedback_parts.append("Bug 2 Fixed (Amber Phase Added)")
    else:
        feedback_parts.append("Bug 2 NOT Fixed (Missing Amber Phase)")

    # Criterion 3: Bug 3 (Intersection Queue Starvation) - 30 pts
    # Checks: Test pass + Code fix + Throughput > 1 (V3 gets processed)
    c3_passed = False
    # Throughput check: Main.py creates 2 vehicles in queue. V3 is last.
    # If bug exists, V3 (index 1) is never reached loop range(1). Throughput <= 1.
    if result.get('bug3_fixed_code') or result.get('sim_throughput', 0) >= 2:
        c3_passed = True
        score += 30
        feedback_parts.append("Bug 3 Fixed (Queue Starvation Resolved)")
    else:
        feedback_parts.append("Bug 3 NOT Fixed (Queue Starvation)")

    # Criterion 4: No Regression (All tests pass) - 10 pts
    if result.get('all_tests_pass'):
        score += 10
        feedback_parts.append("All Tests Passed")
    else:
        feedback_parts.append(f"{result.get('tests_failed')} Tests Failed")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }