#!/usr/bin/env python3
"""
Verifier for search_email task.

HYBRID MULTI-SIGNAL VERIFICATION:
1. BlueMail was running (15 points)
2. VLM: Trajectory shows search workflow (40 points)
3. VLM: Final state shows search results or opened email (45 points)

Pass threshold: 50% score
"""

import json
import tempfile
import os
import sys
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_search_email(traj, env_info, task_info):
    """Verify that the user searched for and found emails in BlueMail."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    search_keyword = metadata.get('search_keyword', 'Sequences Window')

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
    vlm_search_verified = False
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
    # CRITERION 2: VLM - Trajectory shows search workflow (40 points)
    # ================================================================
    query_vlm = env_info.get('query_vlm')
    sample_trajectory_frames = env_info.get('sample_trajectory_frames')

    if query_vlm and traj and sample_trajectory_frames:
        try:
            frames = sample_trajectory_frames(traj, num_samples=5)
            if frames:
                vlm_result = query_vlm(
                    images=frames,
                    prompt=f"""These screenshots show an email client (BlueMail) during a search task.
The user was asked to search for emails containing '{search_keyword}'.
Analyze the progression and answer in JSON format:
{{
    "search_bar_used": true/false,
    "search_term_typed": true/false,
    "search_results_visible": true/false,
    "email_opened": true/false,
    "explanation": "brief description"
}}

Look for:
1. Did the user click on a search bar or search icon?
2. Was a search term typed?
3. Were search results displayed?
4. Was an email opened/read?"""
                )

                vlm_text = vlm_result.get('response', '').lower() if isinstance(vlm_result, dict) else str(vlm_result).lower()
                parsed = vlm_result.get('parsed', {}) if isinstance(vlm_result, dict) else {}

                search_used = parsed.get('search_bar_used', False) or 'search' in vlm_text
                results_visible = parsed.get('search_results_visible', False) or 'result' in vlm_text
                email_opened = parsed.get('email_opened', False) or 'open' in vlm_text or 'read' in vlm_text

                if search_used and (results_visible or email_opened):
                    score += 40
                    vlm_search_verified = True
                    feedback_parts.append("VLM: Search workflow confirmed")
                elif search_used:
                    score += 25
                    vlm_search_verified = True
                    feedback_parts.append("VLM: Search activity detected")
                elif 'bluemail' in vlm_text or 'email' in vlm_text:
                    score += 10
                    feedback_parts.append("VLM: Email client activity detected")
                else:
                    feedback_parts.append("VLM: Could not confirm search workflow")
        except Exception as e:
            logger.warning(f"VLM trajectory check failed: {e}")
            feedback_parts.append(f"VLM trajectory check skipped: {str(e)[:50]}")
    else:
        feedback_parts.append("VLM: Trajectory verification not available")

    # ================================================================
    # CRITERION 3: VLM - Final state verification (45 points)
    # ================================================================
    get_final_screenshot = env_info.get('get_final_screenshot')

    if query_vlm and traj and get_final_screenshot:
        try:
            final_screenshot = get_final_screenshot(traj)
            if final_screenshot:
                vlm_result = query_vlm(
                    image=final_screenshot,
                    prompt=f"""Analyze this screenshot of BlueMail email client.
The user was searching for emails about '{search_keyword}'.
Answer in JSON format:
{{
    "bluemail_visible": true/false,
    "search_results_or_email_visible": true/false,
    "email_content_visible": true/false,
    "explanation": "brief description"
}}

Is BlueMail visible? Are search results displayed or is an email open showing content related to the search?"""
                )

                vlm_text = vlm_result.get('response', '').lower() if isinstance(vlm_result, dict) else str(vlm_result).lower()
                parsed = vlm_result.get('parsed', {}) if isinstance(vlm_result, dict) else {}

                bm_visible = parsed.get('bluemail_visible', False) or 'bluemail' in vlm_text or 'blue mail' in vlm_text
                search_results = parsed.get('search_results_or_email_visible', False) or 'search' in vlm_text or 'result' in vlm_text or 'email' in vlm_text

                if bm_visible and search_results:
                    score += 45
                    vlm_final_verified = True
                    feedback_parts.append("VLM: Search results/email content confirmed")
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
            "search_keyword": search_keyword,
            "vlm_search_verified": vlm_search_verified,
            "vlm_final_verified": vlm_final_verified,
            "score_breakdown": {
                "programmatic": score - (40 if vlm_search_verified else 0) - (45 if vlm_final_verified else 0),
                "vlm": (40 if vlm_search_verified else 0) + (45 if vlm_final_verified else 0)
            }
        }
    }


if __name__ == "__main__":
    """Test verifier with mock data."""

    TASK_INFO = {
        "metadata": {
            "search_keyword": "Sequences Window",
            "expected_min_results": 1
        }
    }

    def make_mock_copy(data):
        def mock_copy(src, dst):
            with open(dst, 'w') as f:
                json.dump(data, f)
        return mock_copy

    tests_passed = 0
    tests_total = 2

    # Test 1: Do nothing
    print("=" * 60)
    print("TEST 1: BlueMail not running")
    data = {"bluemail_running": False, "initial_matching_count": 1, "all_windows": ""}
    r = verify_search_email([], {"copy_from_env": make_mock_copy(data)}, TASK_INFO)
    print(f"  passed={r['passed']}, score={r['score']}")
    ok = not r['passed']
    print(f"  {'PASS' if ok else 'FAIL'}: should fail")
    tests_passed += int(ok)

    # Test 2: BlueMail running
    print("\n" + "=" * 60)
    print("TEST 2: BlueMail running")
    data = {"bluemail_running": True, "initial_matching_count": 1, "all_windows": "BlueMail"}
    r = verify_search_email([], {"copy_from_env": make_mock_copy(data)}, TASK_INFO)
    print(f"  passed={r['passed']}, score={r['score']}")
    ok = r['score'] >= 15
    print(f"  {'PASS' if ok else 'FAIL'}: should have score >=15")
    tests_passed += int(ok)

    print("\n" + "=" * 60)
    print(f"RESULTS: {tests_passed}/{tests_total} tests passed")
    sys.exit(0 if tests_passed == tests_total else 1)
