#!/usr/bin/env python3
"""
Verifier for create_folder task.

HYBRID MULTI-SIGNAL VERIFICATION:
1. BlueMail was running (15 points)
2. VLM: Trajectory shows folder creation and email organization (40 points)
3. VLM: Final state shows folder with emails (45 points)

Pass threshold: 50% score
"""

import json
import tempfile
import os
import sys
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_create_folder(traj, env_info, task_info):
    """Verify that the user created a folder and moved emails in BlueMail."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_folder = metadata.get('expected_folder_name', 'Important')
    expected_min_emails = metadata.get('expected_min_emails_moved', 2)

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
    vlm_folder_verified = False
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
    # CRITERION 2: VLM - Trajectory shows folder creation (40 points)
    # ================================================================
    query_vlm = env_info.get('query_vlm')
    sample_trajectory_frames = env_info.get('sample_trajectory_frames')

    if query_vlm and traj and sample_trajectory_frames:
        try:
            frames = sample_trajectory_frames(traj, num_samples=5)
            if frames:
                vlm_result = query_vlm(
                    images=frames,
                    prompt=f"""These screenshots show an email client (BlueMail) during a folder creation and email organization task.
The user was asked to create a folder named '{expected_folder}' and move at least {expected_min_emails} emails into it.
Analyze the progression and answer in JSON format:
{{
    "folder_creation_attempted": true/false,
    "folder_name_visible": true/false,
    "emails_being_moved": true/false,
    "right_click_menu_visible": true/false,
    "explanation": "brief description"
}}

Look for:
1. Was there a right-click context menu or folder creation dialog?
2. Was the folder name '{expected_folder}' typed?
3. Were emails selected and moved/dragged?
4. Did the sidebar show the new folder?"""
                )

                vlm_text = vlm_result.get('response', '').lower() if isinstance(vlm_result, dict) else str(vlm_result).lower()
                parsed = vlm_result.get('parsed', {}) if isinstance(vlm_result, dict) else {}

                folder_created = parsed.get('folder_creation_attempted', False) or 'folder' in vlm_text or 'create' in vlm_text
                emails_moved = parsed.get('emails_being_moved', False) or 'move' in vlm_text or 'drag' in vlm_text

                if folder_created and emails_moved:
                    score += 40
                    vlm_folder_verified = True
                    feedback_parts.append("VLM: Folder creation and email organization confirmed")
                elif folder_created:
                    score += 25
                    vlm_folder_verified = True
                    feedback_parts.append("VLM: Folder creation detected")
                elif 'bluemail' in vlm_text or 'email' in vlm_text:
                    score += 10
                    feedback_parts.append("VLM: Email client activity detected")
                else:
                    feedback_parts.append("VLM: Could not confirm folder workflow")
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
The user was asked to create a folder named '{expected_folder}' and move emails into it.
Answer in JSON format:
{{
    "bluemail_visible": true/false,
    "folder_visible_in_sidebar": true/false,
    "folder_name_matches": true/false,
    "emails_in_folder": true/false,
    "explanation": "brief description"
}}

Is BlueMail visible? Is there a folder named '{expected_folder}' in the sidebar? Does it contain emails?"""
                )

                vlm_text = vlm_result.get('response', '').lower() if isinstance(vlm_result, dict) else str(vlm_result).lower()
                parsed = vlm_result.get('parsed', {}) if isinstance(vlm_result, dict) else {}

                bm_visible = parsed.get('bluemail_visible', False) or 'bluemail' in vlm_text or 'blue mail' in vlm_text
                folder_visible = parsed.get('folder_visible_in_sidebar', False) or expected_folder.lower() in vlm_text or 'folder' in vlm_text

                if bm_visible and folder_visible:
                    score += 45
                    vlm_final_verified = True
                    feedback_parts.append(f"VLM: '{expected_folder}' folder with emails confirmed")
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
            "expected_folder": expected_folder,
            "expected_min_emails": expected_min_emails,
            "vlm_folder_verified": vlm_folder_verified,
            "vlm_final_verified": vlm_final_verified,
            "score_breakdown": {
                "programmatic": score - (40 if vlm_folder_verified else 0) - (45 if vlm_final_verified else 0),
                "vlm": (40 if vlm_folder_verified else 0) + (45 if vlm_final_verified else 0)
            }
        }
    }


if __name__ == "__main__":
    """Test verifier with mock data."""

    TASK_INFO = {
        "metadata": {
            "expected_folder_name": "Important",
            "expected_min_emails_moved": 2
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
    data = {"bluemail_running": False, "all_windows": ""}
    r = verify_create_folder([], {"copy_from_env": make_mock_copy(data)}, TASK_INFO)
    print(f"  passed={r['passed']}, score={r['score']}")
    ok = not r['passed']
    print(f"  {'PASS' if ok else 'FAIL'}: should fail")
    tests_passed += int(ok)

    # Test 2: BlueMail running
    print("\n" + "=" * 60)
    print("TEST 2: BlueMail running")
    data = {"bluemail_running": True, "all_windows": "BlueMail - Important"}
    r = verify_create_folder([], {"copy_from_env": make_mock_copy(data)}, TASK_INFO)
    print(f"  passed={r['passed']}, score={r['score']}")
    ok = r['score'] >= 15
    print(f"  {'PASS' if ok else 'FAIL'}: should score >=15")
    tests_passed += int(ok)

    print("\n" + "=" * 60)
    print(f"RESULTS: {tests_passed}/{tests_total} tests passed")
    sys.exit(0 if tests_passed == tests_total else 1)
