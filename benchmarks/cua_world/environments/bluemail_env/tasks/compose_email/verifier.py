#!/usr/bin/env python3
"""
Verifier for compose_email task.

HYBRID MULTI-SIGNAL VERIFICATION:
1. BlueMail was running during the task (15 points)
2. Compose window was opened (15 points)
3. VLM: Trajectory shows compose workflow (35 points)
4. VLM: Final state shows email composition activity (35 points)

Pass threshold: 50% score
"""

import json
import tempfile
import os
import sys
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_compose_email(traj, env_info, task_info):
    """Verify that the user composed an email draft in BlueMail."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})

    # Copy result file from container
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

    score = 0
    feedback_parts = []
    vlm_compose_verified = False
    vlm_final_verified = False

    # ================================================================
    # CRITERION 1: BlueMail was running (15 points)
    # ================================================================
    if result.get('bluemail_running'):
        score += 15
        feedback_parts.append("BlueMail running")
    else:
        feedback_parts.append("BlueMail not running at export time")

    # ================================================================
    # CRITERION 2: Compose window was visible (15 points)
    # ================================================================
    if result.get('compose_window_visible'):
        score += 15
        feedback_parts.append("Compose window detected")
    else:
        feedback_parts.append("No compose window detected")

    # ================================================================
    # CRITERION 3: VLM - Trajectory shows compose workflow (35 points)
    # ================================================================
    query_vlm = env_info.get('query_vlm')
    sample_trajectory_frames = env_info.get('sample_trajectory_frames')

    if query_vlm and traj and sample_trajectory_frames:
        try:
            frames = sample_trajectory_frames(traj, num_samples=5)
            if frames:
                vlm_result = query_vlm(
                    images=frames,
                    prompt="""These screenshots show an email client (BlueMail) during a compose email task.
Analyze the progression and answer in JSON format:
{
    "compose_window_visible": true/false,
    "email_fields_filled": true/false,
    "workflow_progressed": true/false,
    "explanation": "brief description"
}

Look for:
1. Did a compose/write/new email window appear at any point?
2. Were email fields (To, Subject, Body) being filled in?
3. Did the workflow progress from main window to compose to saving?"""
                )

                vlm_text = vlm_result.get('response', '').lower() if isinstance(vlm_result, dict) else str(vlm_result).lower()
                parsed = vlm_result.get('parsed', {}) if isinstance(vlm_result, dict) else {}

                compose_visible = parsed.get('compose_window_visible', False) or 'compose' in vlm_text or 'write' in vlm_text or 'new' in vlm_text
                fields_filled = parsed.get('email_fields_filled', False) or 'fill' in vlm_text or 'type' in vlm_text

                if compose_visible and fields_filled:
                    score += 35
                    vlm_compose_verified = True
                    feedback_parts.append("VLM: Compose workflow confirmed")
                elif compose_visible:
                    score += 20
                    vlm_compose_verified = True
                    feedback_parts.append("VLM: Compose window detected")
                elif 'bluemail' in vlm_text or 'email' in vlm_text:
                    score += 10
                    feedback_parts.append("VLM: Email client activity detected")
                else:
                    feedback_parts.append("VLM: Could not confirm compose workflow")
        except Exception as e:
            logger.warning(f"VLM trajectory check failed: {e}")
            feedback_parts.append(f"VLM trajectory check skipped: {str(e)[:50]}")
    else:
        feedback_parts.append("VLM: Trajectory verification not available")

    # ================================================================
    # CRITERION 4: VLM - Final state verification (35 points)
    # ================================================================
    get_final_screenshot = env_info.get('get_final_screenshot')

    if query_vlm and traj and get_final_screenshot:
        try:
            final_screenshot = get_final_screenshot(traj)
            if final_screenshot:
                vlm_result = query_vlm(
                    image=final_screenshot,
                    prompt="""Analyze this screenshot of BlueMail email client.
Answer in JSON format:
{
    "bluemail_visible": true/false,
    "compose_or_draft_visible": true/false,
    "email_content_visible": true/false,
    "explanation": "brief description"
}

Is BlueMail visible? Is there evidence of email composition, draft saving, or an email being written?"""
                )

                vlm_text = vlm_result.get('response', '').lower() if isinstance(vlm_result, dict) else str(vlm_result).lower()
                parsed = vlm_result.get('parsed', {}) if isinstance(vlm_result, dict) else {}

                bm_visible = parsed.get('bluemail_visible', False) or 'bluemail' in vlm_text or 'blue mail' in vlm_text
                email_activity = parsed.get('compose_or_draft_visible', False) or 'email' in vlm_text or 'compose' in vlm_text or 'draft' in vlm_text

                if bm_visible and email_activity:
                    score += 35
                    vlm_final_verified = True
                    feedback_parts.append("VLM: BlueMail with email composition confirmed")
                elif bm_visible:
                    score += 15
                    feedback_parts.append("VLM: BlueMail visible")
                else:
                    feedback_parts.append("VLM: Could not confirm final state")
        except Exception as e:
            logger.warning(f"VLM final screenshot check failed: {e}")
            feedback_parts.append(f"VLM final check skipped: {str(e)[:50]}")
    else:
        if not query_vlm:
            feedback_parts.append("VLM: Not available")

    # ================================================================
    # CALCULATE FINAL RESULT
    # ================================================================
    passed = score >= 50

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "bluemail_running": result.get('bluemail_running'),
            "compose_window_visible": result.get('compose_window_visible'),
            "vlm_compose_verified": vlm_compose_verified,
            "vlm_final_verified": vlm_final_verified,
            "score_breakdown": {
                "programmatic": score - (35 if vlm_compose_verified else 0) - (35 if vlm_final_verified else 0),
                "vlm": (35 if vlm_compose_verified else 0) + (35 if vlm_final_verified else 0)
            }
        }
    }


if __name__ == "__main__":
    """Test verifier with mock data."""

    TASK_INFO = {
        "metadata": {
            "expected_recipient": "marketing@example.com",
            "expected_subject": "Monthly Report Summary - January 2024",
            "expected_body_keywords": ["sales", "marketing", "campaign"]
        }
    }

    def make_mock_copy(data):
        def mock_copy(src, dst):
            with open(dst, 'w') as f:
                json.dump(data, f)
        return mock_copy

    tests_passed = 0
    tests_total = 3

    # Test 1: Do nothing
    print("=" * 60)
    print("TEST 1: Do nothing (BlueMail not running)")
    data = {"bluemail_running": False, "compose_window_visible": False, "all_windows": ""}
    r = verify_compose_email([], {"copy_from_env": make_mock_copy(data)}, TASK_INFO)
    print(f"  passed={r['passed']}, score={r['score']}")
    print(f"  feedback: {r['feedback']}")
    ok = not r['passed'] and r['score'] <= 15
    print(f"  {'PASS' if ok else 'FAIL'}: do-nothing should fail")
    tests_passed += int(ok)

    # Test 2: BlueMail running, compose window visible
    print("\n" + "=" * 60)
    print("TEST 2: BlueMail running with compose window")
    data = {"bluemail_running": True, "compose_window_visible": True, "all_windows": "BlueMail - Compose"}
    r = verify_compose_email([], {"copy_from_env": make_mock_copy(data)}, TASK_INFO)
    print(f"  passed={r['passed']}, score={r['score']}")
    print(f"  feedback: {r['feedback']}")
    ok = r['score'] >= 30
    print(f"  {'PASS' if ok else 'FAIL'}: running+compose should score >=30")
    tests_passed += int(ok)

    # Test 3: BlueMail running only
    print("\n" + "=" * 60)
    print("TEST 3: BlueMail running, no compose window")
    data = {"bluemail_running": True, "compose_window_visible": False, "all_windows": "BlueMail"}
    r = verify_compose_email([], {"copy_from_env": make_mock_copy(data)}, TASK_INFO)
    print(f"  passed={r['passed']}, score={r['score']}")
    print(f"  feedback: {r['feedback']}")
    ok = not r['passed'] and r['score'] < 50
    print(f"  {'PASS' if ok else 'FAIL'}: running only should not pass")
    tests_passed += int(ok)

    print("\n" + "=" * 60)
    print(f"RESULTS: {tests_passed}/{tests_total} tests passed")
    sys.exit(0 if tests_passed == tests_total else 1)
