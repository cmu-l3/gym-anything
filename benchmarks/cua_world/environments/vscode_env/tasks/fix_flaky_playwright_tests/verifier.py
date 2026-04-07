#!/usr/bin/env python3
"""
Verifier for the fix_flaky_playwright_tests task.

Criteria:
1. Each of the 5 tests must pass under both Fast (500ms) and Slow (3000ms) conditions.
2. Anti-Gaming: The underlying Express server must register the corresponding business 
   logic event for that test (e.g., 'LOGIN_SUCCESS', 'PAYMENT_PROCESSED'). This prevents
   an agent from simply deleting the `expect` statements or writing `expect(true).toBe(true)`.
3. Checks if the files were actually modified during the task interval.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_flaky_tests(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve output
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    test_results = result.get('test_results', {})
    server_logs = result.get('server_logs', [])
    modified_files = result.get('modified_files', [])

    expected_tests = {
        'auth.spec.js': 'LOGIN_SUCCESS',
        'checkout.spec.js': 'PAYMENT_PROCESSED',
        'search.spec.js': 'SEARCH_EXECUTED',
        'video_player.spec.js': 'VIDEO_PLAYED',
        'profile.spec.js': 'ADDRESS_DELETED'
    }

    score = 0
    feedback_parts = []
    points_per_test = 20

    for test_file, log_event in expected_tests.items():
        runs = test_results.get(test_file, [])
        # Valid if it ran exactly twice and passed both times (fast & slow latencies)
        passed_all = len(runs) == 2 and all(runs)
        
        # Anti-gaming: Ensure the browser actually hit the backend
        has_log = log_event in server_logs
        
        # Verify file was touched
        was_modified = test_file in modified_files

        if passed_all and has_log and was_modified:
            score += points_per_test
            feedback_parts.append(f"✅ {test_file}: Fixed and validated.")
        elif passed_all and has_log and not was_modified:
            # File wasn't modified after task started? Suspicious but maybe they typed too fast. Minor penalty or warning.
            score += (points_per_test - 5)
            feedback_parts.append(f"⚠️ {test_file}: Passed, but file unmodified timestamp (Gaming?)")
        elif passed_all and not has_log:
            feedback_parts.append(f"❌ {test_file}: Passed tests but backend event '{log_event}' missing. Did you remove the test actions?")
        else:
            feedback_parts.append(f"❌ {test_file}: Failed. Still flaky or broken.")

    # VLM Trajectory Verification
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            if frames and final:
                vlm_prompt = (
                    "Look at these trajectory frames of a VS Code session. "
                    "Did the user edit Playwright test files (.spec.js) to fix bugs? "
                    "Respond with a JSON object containing a boolean 'edited_tests'."
                )
                vlm_resp = query_vlm(images=frames + [final], prompt=vlm_prompt)
                if vlm_resp and vlm_resp.get("success"):
                    parsed = vlm_resp.get("parsed", {})
                    if parsed.get("edited_tests"):
                        feedback_parts.append("✅ VLM confirmed visual edits to test files.")
                    else:
                        feedback_parts.append("⚠️ VLM could not visually confirm edits.")
        except Exception as e:
            logger.warning(f"VLM verification failed to run: {e}")

    # Determine final status
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }