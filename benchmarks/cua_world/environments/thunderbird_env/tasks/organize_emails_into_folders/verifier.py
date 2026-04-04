#!/usr/bin/env python3
"""
Verifier for organize_emails_into_folders task.

HYBRID MULTI-SIGNAL VERIFICATION:
1. "Important" folder was created (20 points)
2. Folder has emails (at least min_emails_to_move) (20 points)
3. Emails moved from Inbox (15 points)
4. Thunderbird was running (10 points)
5. VLM: Trajectory shows folder creation workflow (15 points)
6. VLM: Final state shows Thunderbird with Important folder (10 points)

Pass threshold: score >= 50 AND folder_created AND folder_count >= min_emails
"""

import json
import tempfile
import os
import sys
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_organize_emails_into_folders(traj, env_info, task_info):
    """Verify that emails were organized into a new folder.

    Uses MULTIPLE INDEPENDENT SIGNALS including VLM visual verification
    to prevent gaming.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values from task metadata
    metadata = task_info.get('metadata', {})
    expected_folder = metadata.get('expected_folder_name', 'Important')
    min_emails = metadata.get('min_emails_to_move', 3)

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
    vlm_trajectory_verified = False
    vlm_final_verified = False

    # ================================================================
    # CRITERION 1: Folder was created (20 points)
    # ================================================================
    folder_created = result.get('folder_created', False)
    if folder_created:
        score += 20
        feedback_parts.append(f"'{expected_folder}' folder created")
    else:
        # Check if any new folder was created (exact match in comma-separated list)
        current_folders = result.get('current_folders', '')
        folder_list = [f.strip().lower() for f in current_folders.split(',')]
        if expected_folder.lower() in folder_list:
            score += 20
            folder_created = True
            feedback_parts.append(f"'{expected_folder}' folder found in folder list")
        else:
            feedback_parts.append(f"'{expected_folder}' folder not created")

    # ================================================================
    # CRITERION 2: Folder has emails (20 points)
    # ================================================================
    folder_count = result.get('folder_email_count', 0)
    if folder_count >= min_emails:
        score += 20
        feedback_parts.append(f"Folder contains {folder_count} emails (required: {min_emails})")
    elif folder_count > 0:
        score += int(20 * folder_count / min_emails)
        feedback_parts.append(f"Folder has {folder_count}/{min_emails} required emails")
    else:
        feedback_parts.append(f"Folder is empty (needs {min_emails} emails)")

    # ================================================================
    # CRITERION 3: Emails moved from Inbox (15 points)
    # ================================================================
    emails_moved = result.get('emails_moved_from_inbox', 0)
    if emails_moved >= min_emails:
        score += 15
        feedback_parts.append(f"{emails_moved} emails moved from Inbox")
    elif emails_moved > 0:
        score += int(15 * emails_moved / min_emails)
        feedback_parts.append(f"Only {emails_moved}/{min_emails} emails moved from Inbox")
    else:
        # Maybe they were copied instead of moved
        if folder_count >= min_emails:
            score += 8
            feedback_parts.append("Emails appear copied (not moved) from Inbox")
        else:
            feedback_parts.append("No emails moved from Inbox")

    # ================================================================
    # CRITERION 4: Thunderbird was running (10 points)
    # ================================================================
    if result.get('thunderbird_running'):
        score += 10
        feedback_parts.append("Thunderbird running")
    else:
        feedback_parts.append("Thunderbird not running at export time")

    # ================================================================
    # CRITERION 5: VLM - Trajectory shows folder creation workflow (15 points)
    # Verify the agent went through folder creation and email moving steps
    # ================================================================
    query_vlm = env_info.get('query_vlm')
    sample_trajectory_frames = env_info.get('sample_trajectory_frames')

    if query_vlm and traj and sample_trajectory_frames:
        try:
            frames = sample_trajectory_frames(traj, num_samples=5)
            if frames:
                vlm_result = query_vlm(
                    images=frames,
                    prompt="""These screenshots show Mozilla Thunderbird email client during an email organization task.
Analyze the progression and answer in JSON format:
{
    "folder_panel_visible": true/false,
    "email_selection_visible": true/false,
    "move_or_drag_operation": true/false,
    "new_folder_creation": true/false,
    "explanation": "brief description"
}

Look for:
1. Is the folder panel visible in any screenshots?
2. Are emails being selected in the inbox?
3. Are there drag-and-drop or right-click move operations visible?
4. Is a new folder being created (new folder dialog, context menu)?"""
                )

                vlm_text = vlm_result.get('response', '').lower() if isinstance(vlm_result, dict) else str(vlm_result).lower()
                parsed = vlm_result.get('parsed', {}) if isinstance(vlm_result, dict) else {}

                folder_panel = parsed.get('folder_panel_visible', False) or 'folder' in vlm_text or 'panel' in vlm_text
                email_selection = parsed.get('email_selection_visible', False) or 'select' in vlm_text or 'email' in vlm_text
                move_operation = parsed.get('move_or_drag_operation', False) or 'move' in vlm_text or 'drag' in vlm_text
                folder_creation = parsed.get('new_folder_creation', False) or 'new folder' in vlm_text or 'create' in vlm_text

                if folder_panel and (email_selection or move_operation or folder_creation):
                    score += 15
                    vlm_trajectory_verified = True
                    feedback_parts.append("VLM: Folder organization workflow confirmed")
                elif folder_panel or email_selection:
                    score += 10
                    vlm_trajectory_verified = True
                    feedback_parts.append("VLM: Email client folder activity detected")
                elif 'thunderbird' in vlm_text or 'email' in vlm_text:
                    score += 5
                    feedback_parts.append("VLM: Email client activity detected")
                else:
                    feedback_parts.append("VLM: Could not confirm folder organization workflow")
        except Exception as e:
            logger.warning(f"VLM trajectory check failed: {e}")
            feedback_parts.append(f"VLM trajectory check skipped: {str(e)[:50]}")
    else:
        feedback_parts.append("VLM: Trajectory verification not available")

    # ================================================================
    # CRITERION 6: VLM - Final state verification (10 points)
    # ================================================================
    get_final_screenshot = env_info.get('get_final_screenshot')

    if query_vlm and traj and get_final_screenshot:
        try:
            final_screenshot = get_final_screenshot(traj)
            if final_screenshot:
                vlm_result = query_vlm(
                    image=final_screenshot,
                    prompt="""Analyze this screenshot of Mozilla Thunderbird email client.
Answer in JSON format:
{
    "thunderbird_visible": true/false,
    "folder_panel_visible": true/false,
    "important_folder_visible": true/false,
    "emails_visible_in_list": true/false,
    "explanation": "brief description"
}

Is Thunderbird visible? Is the folder panel showing with an 'Important' folder?
Are there emails visible in the message list?"""
                )

                vlm_text = vlm_result.get('response', '').lower() if isinstance(vlm_result, dict) else str(vlm_result).lower()
                parsed = vlm_result.get('parsed', {}) if isinstance(vlm_result, dict) else {}

                tb_visible = parsed.get('thunderbird_visible', False) or 'thunderbird' in vlm_text
                important_visible = parsed.get('important_folder_visible', False) or 'important' in vlm_text
                folder_panel = parsed.get('folder_panel_visible', False) or 'folder' in vlm_text
                emails_visible = parsed.get('emails_visible_in_list', False) or 'email' in vlm_text

                if tb_visible and important_visible:
                    score += 10
                    vlm_final_verified = True
                    feedback_parts.append("VLM: Thunderbird with Important folder confirmed")
                elif tb_visible and folder_panel:
                    score += 7
                    vlm_final_verified = True
                    feedback_parts.append("VLM: Thunderbird with folder panel visible")
                elif tb_visible:
                    score += 5
                    feedback_parts.append("VLM: Thunderbird visible")
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
    # Key criteria: folder must have been created and contain emails
    # VLM provides complementary verification but is not strictly required
    passed = score >= 50 and folder_created and folder_count >= min_emails

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "folder_created": folder_created,
            "folder_email_count": folder_count,
            "emails_moved": emails_moved,
            "initial_inbox": result.get('initial_inbox_count'),
            "current_inbox": result.get('current_inbox_count'),
            "vlm_trajectory_verified": vlm_trajectory_verified,
            "vlm_final_verified": vlm_final_verified,
            "score_breakdown": {
                "programmatic": score - (15 if vlm_trajectory_verified else 0) - (10 if vlm_final_verified else 0),
                "vlm": (15 if vlm_trajectory_verified else 0) + (10 if vlm_final_verified else 0)
            }
        }
    }


if __name__ == "__main__":
    """Test verifier with mock data for all failure modes."""

    TASK_INFO = {
        "metadata": {
            "expected_folder_name": "Important",
            "min_emails_to_move": 3
        }
    }

    def make_mock_copy(data):
        def mock_copy(src, dst):
            with open(dst, 'w') as f:
                json.dump(data, f)
        return mock_copy

    tests_passed = 0
    tests_total = 4

    # Test 1: Do nothing
    print("=" * 60)
    print("TEST 1: Do nothing (no agent action)")
    data = {
        "folder_created": False, "folder_email_count": 0, "folder_path": "",
        "initial_inbox_count": 50, "current_inbox_count": 50,
        "emails_moved_from_inbox": 0,
        "current_folders": "Drafts,Inbox,Junk,Sent,Templates,Trash,Unsent Messages",
        "thunderbird_running": True,
    }
    r = verify_organize_emails_into_folders([], {"copy_from_env": make_mock_copy(data)}, TASK_INFO)
    print(f"  passed={r['passed']}, score={r['score']}")
    print(f"  feedback: {r['feedback']}")
    ok = not r['passed'] and r['score'] <= 20
    print(f"  {'PASS' if ok else 'FAIL'}: do-nothing should fail with score<=20")
    tests_passed += int(ok)

    # Test 2: Partial work (folder created but no emails moved)
    print("\n" + "=" * 60)
    print("TEST 2: Partial work (folder created but empty)")
    data = {
        "folder_created": True, "folder_email_count": 0, "folder_path": "Important",
        "initial_inbox_count": 50, "current_inbox_count": 50,
        "emails_moved_from_inbox": 0,
        "current_folders": "Drafts,Important,Inbox,Junk,Sent,Templates,Trash,Unsent Messages",
        "thunderbird_running": True,
    }
    r = verify_organize_emails_into_folders([], {"copy_from_env": make_mock_copy(data)}, TASK_INFO)
    print(f"  passed={r['passed']}, score={r['score']}")
    print(f"  feedback: {r['feedback']}")
    ok = not r['passed'] and r['score'] < 50
    print(f"  {'PASS' if ok else 'FAIL'}: partial work should fail with score<50")
    tests_passed += int(ok)

    # Test 3: Correct completion
    print("\n" + "=" * 60)
    print("TEST 3: Correct completion (folder created, 5 emails moved)")
    data = {
        "folder_created": True, "folder_email_count": 5, "folder_path": "Important",
        "initial_inbox_count": 50, "current_inbox_count": 45,
        "emails_moved_from_inbox": 5,
        "current_folders": "Drafts,Important,Inbox,Junk,Sent,Templates,Trash,Unsent Messages",
        "thunderbird_running": True,
    }
    r = verify_organize_emails_into_folders([], {"copy_from_env": make_mock_copy(data)}, TASK_INFO)
    print(f"  passed={r['passed']}, score={r['score']}")
    print(f"  feedback: {r['feedback']}")
    ok = r['passed'] and r['score'] >= 55
    print(f"  {'PASS' if ok else 'FAIL'}: correct completion should pass with score>=55")
    tests_passed += int(ok)

    # Test 4: Wrong parameters (wrong folder name)
    print("\n" + "=" * 60)
    print("TEST 4: Wrong parameters (folder named 'Misc' instead of 'Important')")
    data = {
        "folder_created": False, "folder_email_count": 0, "folder_path": "",
        "initial_inbox_count": 50, "current_inbox_count": 45,
        "emails_moved_from_inbox": 5,
        "current_folders": "Drafts,Inbox,Junk,Misc,Sent,Templates,Trash,Unsent Messages",
        "thunderbird_running": True,
    }
    r = verify_organize_emails_into_folders([], {"copy_from_env": make_mock_copy(data)}, TASK_INFO)
    print(f"  passed={r['passed']}, score={r['score']}")
    print(f"  feedback: {r['feedback']}")
    ok = not r['passed']
    print(f"  {'PASS' if ok else 'FAIL'}: wrong folder name should fail")
    tests_passed += int(ok)

    print("\n" + "=" * 60)
    print(f"RESULTS: {tests_passed}/{tests_total} tests passed")
    sys.exit(0 if tests_passed == tests_total else 1)
