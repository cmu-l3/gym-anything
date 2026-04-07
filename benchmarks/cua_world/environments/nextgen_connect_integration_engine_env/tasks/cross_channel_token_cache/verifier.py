#!/usr/bin/env python3
"""
Verifier for cross_channel_token_cache task.
"""

import json
import tempfile
import os

def verify_cross_channel_token_cache(traj, env_info, task_info):
    """
    Verify the shared state implementation using results from active testing.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file
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

    # Extract data
    initial_count = int(result.get('initial_channel_count', 0))
    final_count = int(result.get('final_channel_count', 0))
    tests = result.get('functional_tests', {})
    
    listening_tm = tests.get('token_manager_listening', False)
    listening_ds = tests.get('data_sender_listening', False)
    cycle_a = tests.get('cycle_a_passed', False)
    cycle_b = tests.get('cycle_b_passed', False)
    errors = tests.get('errors', [])
    
    score = 0
    feedback_parts = []
    
    # 1. Channels created (20 pts)
    if final_count >= initial_count + 2:
        score += 20
        feedback_parts.append("Two new channels detected")
    elif final_count > initial_count:
        score += 10
        feedback_parts.append(f"Only {final_count - initial_count} new channel(s) detected (expected 2)")
    else:
        feedback_parts.append("No new channels created")

    # 2. Ports Listening (10 pts)
    if listening_tm and listening_ds:
        score += 10
        feedback_parts.append("Both ports (6661, 6662) are listening")
    elif listening_tm or listening_ds:
        score += 5
        feedback_parts.append("One port is listening")
    else:
        feedback_parts.append("Target ports are NOT listening")

    # 3. Cycle A: Basic Functionality (35 pts)
    # Proves JSON input -> GlobalMap -> HL7 Output read
    if cycle_a:
        score += 35
        feedback_parts.append("Cycle A PASSED: Token correctly cached and applied")
    else:
        feedback_parts.append("Cycle A FAILED: First token not applied correctly")

    # 4. Cycle B: Dynamic Update (35 pts)
    # Proves variable is shared and mutable, not hardcoded
    if cycle_b:
        score += 35
        feedback_parts.append("Cycle B PASSED: Token update reflected in output (Dynamic GlobalMap confirmed)")
    else:
        feedback_parts.append("Cycle B FAILED: Updated token not reflected in output")

    if errors:
        feedback_parts.append(f"Errors: {'; '.join(errors[:3])}")

    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }