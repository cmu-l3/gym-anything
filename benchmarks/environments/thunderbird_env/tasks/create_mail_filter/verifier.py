#!/usr/bin/env python3
"""
Verifier for create_mail_filter task.

HYBRID MULTI-SIGNAL VERIFICATION:
1. Filter created in msgFilterRules.dat (20 points)
2. Filter condition matches expected value (15 points)
3. Filter action is 'Move to folder' (15 points)
4. Target folder is 'Urgent' (10 points)
5. Thunderbird was running (10 points)
6. VLM: Trajectory shows filter dialog workflow (15 points)
7. VLM: Final state shows Thunderbird with filter/folder (10 points)

Pass threshold: score >= 50 AND filter_created AND urgent folder targeted
"""

import json
import tempfile
import os
import sys
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_create_mail_filter(traj, env_info, task_info):
    """Verify that a message filter was created correctly.

    Uses MULTIPLE INDEPENDENT SIGNALS including VLM visual verification
    to prevent gaming.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values from task metadata
    metadata = task_info.get('metadata', {})
    expected_condition_value = metadata.get('expected_condition_value', 'urgent')
    expected_target_folder = metadata.get('expected_target_folder', 'Urgent')

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
    # CRITERION 1: Filter was created (20 points)
    # ================================================================
    filter_created = result.get('filter_created', False)
    if filter_created:
        score += 20
        feedback_parts.append(f"Filter created: '{result.get('filter_name', 'unknown')}'")
    else:
        feedback_parts.append("No new filter found in msgFilterRules.dat")

    # ================================================================
    # CRITERION 2: Filter condition matches (15 points)
    # ================================================================
    condition = result.get('filter_condition', '').lower().strip()
    # Parse Thunderbird filter condition format: "AND (field,operator,value)" or "field,operator,value"
    cond_inner = condition
    if '(' in cond_inner and ')' in cond_inner:
        cond_inner = cond_inner[cond_inner.index('(') + 1:cond_inner.rindex(')')]
    cond_parts = [p.strip() for p in cond_inner.split(',')]
    cond_field = cond_parts[0] if len(cond_parts) >= 1 else ''
    cond_value = cond_parts[-1] if len(cond_parts) >= 3 else ''

    if cond_field == 'subject' and cond_value == expected_condition_value.lower():
        score += 15
        feedback_parts.append(f"Correct filter condition: subject contains '{expected_condition_value}'")
    elif cond_value == expected_condition_value.lower():
        score += 8
        feedback_parts.append(f"Filter contains '{expected_condition_value}' but field is '{cond_field}', not 'subject'")
    elif condition:
        feedback_parts.append(f"Filter condition doesn't match expected: {condition}")
    else:
        feedback_parts.append("No filter condition found")

    # ================================================================
    # CRITERION 3: Filter action is 'Move to folder' (15 points)
    # ================================================================
    action = result.get('filter_action', '').lower().strip()
    target = result.get('filter_target', '').lower()
    if action == 'move to folder':
        score += 15
        feedback_parts.append("Filter action is 'Move to folder'")
    elif action:
        score += 5
        feedback_parts.append(f"Filter action found but not Move: {action}")
    else:
        feedback_parts.append("No filter action found")

    # ================================================================
    # CRITERION 4: Target folder is 'Urgent' (10 points)
    # ================================================================
    if expected_target_folder.lower() in target:
        score += 10
        feedback_parts.append(f"Filter targets '{expected_target_folder}' folder")
    elif result.get('urgent_folder_exists'):
        score += 5
        feedback_parts.append(f"Urgent folder exists but filter target unclear: {target}")
    else:
        feedback_parts.append(f"Filter target doesn't match Urgent folder: {target}")

    # ================================================================
    # CRITERION 5: Thunderbird was running (10 points)
    # ================================================================
    if result.get('thunderbird_running'):
        score += 10
        feedback_parts.append("Thunderbird running")
    else:
        feedback_parts.append("Thunderbird not running at export time")

    # ================================================================
    # CRITERION 6: VLM - Trajectory shows filter dialog workflow (15 points)
    # Verify the agent went through filter creation steps
    # ================================================================
    query_vlm = env_info.get('query_vlm')
    sample_trajectory_frames = env_info.get('sample_trajectory_frames')

    if query_vlm and traj and sample_trajectory_frames:
        try:
            frames = sample_trajectory_frames(traj, num_samples=5)
            if frames:
                vlm_result = query_vlm(
                    images=frames,
                    prompt="""These screenshots show Mozilla Thunderbird email client during a mail filter creation task.
Analyze the progression and answer in JSON format:
{
    "filter_dialog_visible": true/false,
    "filter_creation_steps": true/false,
    "condition_setup_visible": true/false,
    "action_setup_visible": true/false,
    "explanation": "brief description"
}

Look for:
1. Did a filter dialog or filter rules window appear at any point?
2. Were filter creation steps visible (new filter button, naming the filter)?
3. Was a condition being set up (e.g., subject contains a keyword)?
4. Was an action being configured (e.g., move to folder)?"""
                )

                vlm_text = vlm_result.get('response', '').lower() if isinstance(vlm_result, dict) else str(vlm_result).lower()
                parsed = vlm_result.get('parsed', {}) if isinstance(vlm_result, dict) else {}

                dialog_visible = parsed.get('filter_dialog_visible', False) or 'filter' in vlm_text or 'dialog' in vlm_text
                creation_steps = parsed.get('filter_creation_steps', False) or 'new filter' in vlm_text or 'create' in vlm_text
                condition_setup = parsed.get('condition_setup_visible', False) or 'condition' in vlm_text or 'subject' in vlm_text
                action_setup = parsed.get('action_setup_visible', False) or 'action' in vlm_text or 'move' in vlm_text

                if dialog_visible and (creation_steps or condition_setup or action_setup):
                    score += 15
                    vlm_trajectory_verified = True
                    feedback_parts.append("VLM: Filter creation workflow confirmed")
                elif dialog_visible:
                    score += 10
                    vlm_trajectory_verified = True
                    feedback_parts.append("VLM: Filter dialog detected")
                elif 'thunderbird' in vlm_text or 'email' in vlm_text:
                    score += 5
                    feedback_parts.append("VLM: Email client activity detected")
                else:
                    feedback_parts.append("VLM: Could not confirm filter creation workflow")
        except Exception as e:
            logger.warning(f"VLM trajectory check failed: {e}")
            feedback_parts.append(f"VLM trajectory check skipped: {str(e)[:50]}")
    else:
        feedback_parts.append("VLM: Trajectory verification not available")

    # ================================================================
    # CRITERION 7: VLM - Final state verification (10 points)
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
    "filter_dialog_or_rules_visible": true/false,
    "urgent_folder_visible": true/false,
    "folder_panel_visible": true/false,
    "explanation": "brief description"
}

Is Thunderbird visible? Is there a filter dialog or message rules window showing?
Is the folder panel visible with an 'Urgent' folder?"""
                )

                vlm_text = vlm_result.get('response', '').lower() if isinstance(vlm_result, dict) else str(vlm_result).lower()
                parsed = vlm_result.get('parsed', {}) if isinstance(vlm_result, dict) else {}

                tb_visible = parsed.get('thunderbird_visible', False) or 'thunderbird' in vlm_text
                filter_visible = parsed.get('filter_dialog_or_rules_visible', False) or 'filter' in vlm_text
                urgent_visible = parsed.get('urgent_folder_visible', False) or 'urgent' in vlm_text
                folder_panel = parsed.get('folder_panel_visible', False) or 'folder' in vlm_text

                if tb_visible and (filter_visible or urgent_visible):
                    score += 10
                    vlm_final_verified = True
                    feedback_parts.append("VLM: Thunderbird with filter/folder activity confirmed")
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
    # Key criteria: filter must have been created and urgent folder targeted
    # VLM provides complementary verification but is not strictly required
    key_criteria_met = filter_created and (
        result.get('urgent_folder_exists', False) and
        expected_target_folder.lower() in result.get('filter_target', '').lower()
    )
    passed = score >= 50 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "filter_created": result.get('filter_created'),
            "filter_name": result.get('filter_name'),
            "filter_condition": result.get('filter_condition'),
            "filter_action": result.get('filter_action'),
            "filter_target": result.get('filter_target'),
            "urgent_folder_exists": result.get('urgent_folder_exists'),
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
            "expected_filter_name": "Urgent Filter",
            "expected_condition_field": "subject",
            "expected_condition_value": "urgent",
            "expected_action": "Move to folder",
            "expected_target_folder": "Urgent"
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
        "filter_created": False, "initial_filter_count": 0, "current_filter_count": 0,
        "filter_name": "", "filter_condition": "", "filter_action": "", "filter_target": "",
        "urgent_folder_exists": False, "thunderbird_running": True,
    }
    r = verify_create_mail_filter([], {"copy_from_env": make_mock_copy(data)}, TASK_INFO)
    print(f"  passed={r['passed']}, score={r['score']}")
    print(f"  feedback: {r['feedback']}")
    ok = not r['passed'] and r['score'] <= 20
    print(f"  {'PASS' if ok else 'FAIL'}: do-nothing should fail with score<=20")
    tests_passed += int(ok)

    # Test 2: Partial work (folder created but no filter)
    print("\n" + "=" * 60)
    print("TEST 2: Partial work (Urgent folder created but no filter)")
    data = {
        "filter_created": False, "initial_filter_count": 0, "current_filter_count": 0,
        "filter_name": "", "filter_condition": "", "filter_action": "", "filter_target": "",
        "urgent_folder_exists": True, "thunderbird_running": True,
    }
    r = verify_create_mail_filter([], {"copy_from_env": make_mock_copy(data)}, TASK_INFO)
    print(f"  passed={r['passed']}, score={r['score']}")
    print(f"  feedback: {r['feedback']}")
    ok = not r['passed'] and r['score'] < 50
    print(f"  {'PASS' if ok else 'FAIL'}: partial work should fail with score<50")
    tests_passed += int(ok)

    # Test 3: Correct completion
    print("\n" + "=" * 60)
    print("TEST 3: Correct completion (filter + folder created correctly)")
    data = {
        "filter_created": True, "initial_filter_count": 0, "current_filter_count": 1,
        "filter_name": "Urgent Filter",
        "filter_condition": "subject,contains,urgent",
        "filter_action": "Move to folder",
        "filter_target": "mailbox://nobody@Local Folders/Urgent",
        "urgent_folder_exists": True, "thunderbird_running": True,
    }
    r = verify_create_mail_filter([], {"copy_from_env": make_mock_copy(data)}, TASK_INFO)
    print(f"  passed={r['passed']}, score={r['score']}")
    print(f"  feedback: {r['feedback']}")
    ok = r['passed'] and r['score'] >= 60
    print(f"  {'PASS' if ok else 'FAIL'}: correct completion should pass with score>=60")
    tests_passed += int(ok)

    # Test 4: Wrong parameters (filter for wrong keyword)
    print("\n" + "=" * 60)
    print("TEST 4: Wrong parameters (filter for 'spam' instead of 'urgent')")
    data = {
        "filter_created": True, "initial_filter_count": 0, "current_filter_count": 1,
        "filter_name": "Spam Filter",
        "filter_condition": "subject,contains,spam",
        "filter_action": "Move to folder",
        "filter_target": "mailbox://nobody@Local Folders/Spam",
        "urgent_folder_exists": False, "thunderbird_running": True,
    }
    r = verify_create_mail_filter([], {"copy_from_env": make_mock_copy(data)}, TASK_INFO)
    print(f"  passed={r['passed']}, score={r['score']}")
    print(f"  feedback: {r['feedback']}")
    ok = not r['passed']
    print(f"  {'PASS' if ok else 'FAIL'}: wrong parameters should fail")
    tests_passed += int(ok)

    print("\n" + "=" * 60)
    print(f"RESULTS: {tests_passed}/{tests_total} tests passed")
    sys.exit(0 if tests_passed == tests_total else 1)
