#!/usr/bin/env python3
"""
Verifier for compose_send_email task.

HYBRID MULTI-SIGNAL VERIFICATION:
1. New draft was saved in Drafts folder (20 points)
2. Draft has correct recipient (15 points)
3. Draft has correct subject (15 points)
4. Draft body contains expected keywords (15 points)
5. Thunderbird was running during the task (10 points)
6. VLM: Trajectory shows compose workflow (15 points)
7. VLM: Final state shows completed email or Thunderbird (10 points)

Pass threshold: 60% AND draft_added is True
"""

import json
import tempfile
import os
import sys
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_compose_send_email(traj, env_info, task_info):
    """Verify that the user composed and saved an email draft.

    Uses MULTIPLE INDEPENDENT SIGNALS including VLM visual verification
    to prevent gaming.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values from task metadata
    metadata = task_info.get('metadata', {})
    expected_recipient = metadata.get('expected_recipient', 'colleague@example.com')
    expected_subject = metadata.get('expected_subject', 'Q4 Budget Review Meeting')
    expected_keywords = metadata.get('expected_body_keywords', ['budget', 'meeting', 'Q4'])

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
    # CRITERION 1: New draft was saved (20 points)
    # ================================================================
    draft_added = result.get('draft_added', False)
    if draft_added:
        score += 20
        feedback_parts.append("Draft saved successfully")
    else:
        # Check outbox as fallback (user might have tried to send)
        if result.get('outbox_count', 0) > 0 or result.get('sent_count', 0) > 0:
            score += 10
            feedback_parts.append("Email found in Sent/Outbox instead of Drafts (partial credit)")
        else:
            feedback_parts.append("No new draft found in Drafts folder")

    # ================================================================
    # CRITERION 2: Correct recipient (15 points)
    # ================================================================
    actual_recipient = result.get('draft_recipient', '').lower().strip()
    if expected_recipient.lower() in actual_recipient:
        score += 15
        feedback_parts.append(f"Correct recipient: {actual_recipient}")
    elif actual_recipient:
        score += 5
        feedback_parts.append(f"Recipient found but doesn't match: {actual_recipient}")
    else:
        feedback_parts.append("No recipient found in draft")

    # ================================================================
    # CRITERION 3: Correct subject (15 points)
    # ================================================================
    actual_subject = result.get('draft_subject', '').lower().strip()
    expected_subject_lower = expected_subject.lower()
    if actual_subject and expected_subject_lower in actual_subject:
        score += 15
        feedback_parts.append(f"Correct subject: {result.get('draft_subject', '')}")
    elif actual_subject:
        expected_words = expected_subject_lower.split()
        words_matched = sum(1 for word in expected_words if word in actual_subject)
        if words_matched >= max(2, len(expected_words) // 2):
            score += 8
            feedback_parts.append(f"Subject partially matches: {result.get('draft_subject', '')}")
        else:
            feedback_parts.append(f"Subject doesn't match: got '{result.get('draft_subject', '')}'")
    else:
        feedback_parts.append(f"Subject doesn't match: got '{result.get('draft_subject', '')}'")

    # ================================================================
    # CRITERION 4: Body contains expected keywords (15 points)
    # ================================================================
    body_snippet = result.get('draft_body_snippet', '').lower()
    keywords_found = sum(1 for kw in expected_keywords if kw.lower() in body_snippet)
    if keywords_found == len(expected_keywords):
        score += 15
        feedback_parts.append(f"All {len(expected_keywords)} keywords found in body")
    elif keywords_found > 0:
        score += int(15 * keywords_found / len(expected_keywords))
        feedback_parts.append(f"{keywords_found}/{len(expected_keywords)} keywords found in body")
    else:
        if body_snippet:
            feedback_parts.append("Body found but missing expected keywords")
        else:
            feedback_parts.append("No body content found in draft")

    # ================================================================
    # CRITERION 5: Thunderbird was running (10 points)
    # ================================================================
    if result.get('thunderbird_running'):
        score += 10
        feedback_parts.append("Thunderbird running")
    else:
        feedback_parts.append("Thunderbird not running at export time")

    # ================================================================
    # CRITERION 6: VLM - Trajectory shows compose workflow (15 points)
    # Verify the agent went through compose window steps
    # ================================================================
    query_vlm = env_info.get('query_vlm')
    sample_trajectory_frames = env_info.get('sample_trajectory_frames')

    if query_vlm and traj and sample_trajectory_frames:
        try:
            frames = sample_trajectory_frames(traj, num_samples=5)
            if frames:
                vlm_result = query_vlm(
                    images=frames,
                    prompt="""These screenshots show an email client (Mozilla Thunderbird) during a compose email task.
Analyze the progression and answer in JSON format:
{
    "compose_window_visible": true/false,
    "email_fields_filled": true/false,
    "workflow_progressed": true/false,
    "explanation": "brief description"
}

Look for:
1. Did a compose/write window appear at any point?
2. Were email fields (To, Subject, Body) being filled in?
3. Did the workflow progress from main window to compose to saving?"""
                )

                vlm_text = vlm_result.get('response', '').lower() if isinstance(vlm_result, dict) else str(vlm_result).lower()
                parsed = vlm_result.get('parsed', {}) if isinstance(vlm_result, dict) else {}

                compose_visible = parsed.get('compose_window_visible', False) or 'compose' in vlm_text or 'write' in vlm_text
                fields_filled = parsed.get('email_fields_filled', False) or 'fill' in vlm_text or 'type' in vlm_text
                workflow_ok = parsed.get('workflow_progressed', False) or 'progress' in vlm_text

                if compose_visible and fields_filled:
                    score += 15
                    vlm_compose_verified = True
                    feedback_parts.append("VLM: Compose workflow confirmed")
                elif compose_visible:
                    score += 10
                    vlm_compose_verified = True
                    feedback_parts.append("VLM: Compose window detected")
                elif 'thunderbird' in vlm_text or 'email' in vlm_text:
                    score += 5
                    feedback_parts.append("VLM: Email client activity detected")
                else:
                    feedback_parts.append("VLM: Could not confirm compose workflow")
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
    "main_window_or_compose": "main" or "compose" or "other",
    "email_activity_evident": true/false,
    "explanation": "brief description"
}

Is Thunderbird visible? Is there evidence of email composition or draft saving activity?"""
                )

                vlm_text = vlm_result.get('response', '').lower() if isinstance(vlm_result, dict) else str(vlm_result).lower()
                parsed = vlm_result.get('parsed', {}) if isinstance(vlm_result, dict) else {}

                tb_visible = parsed.get('thunderbird_visible', False) or 'thunderbird' in vlm_text
                email_activity = parsed.get('email_activity_evident', False) or 'email' in vlm_text or 'compose' in vlm_text

                if tb_visible and email_activity:
                    score += 10
                    vlm_final_verified = True
                    feedback_parts.append("VLM: Thunderbird with email activity confirmed")
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
    # Key criterion: draft must have been added
    # VLM provides complementary verification but is not strictly required
    passed = score >= 60 and draft_added

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "draft_added": result.get('draft_added'),
            "recipient": result.get('draft_recipient'),
            "subject": result.get('draft_subject'),
            "body_snippet": result.get('draft_body_snippet', '')[:100],
            "vlm_compose_verified": vlm_compose_verified,
            "vlm_final_verified": vlm_final_verified,
            "score_breakdown": {
                "programmatic": score - (15 if vlm_compose_verified else 0) - (10 if vlm_final_verified else 0),
                "vlm": (15 if vlm_compose_verified else 0) + (10 if vlm_final_verified else 0)
            }
        }
    }


if __name__ == "__main__":
    """Test verifier with mock data for all failure modes."""

    TASK_INFO = {
        "metadata": {
            "expected_recipient": "colleague@example.com",
            "expected_subject": "Q4 Budget Review Meeting",
            "expected_body_keywords": ["budget", "meeting", "Q4"]
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
        "draft_added": False, "initial_drafts_count": 0, "current_drafts_count": 0,
        "draft_recipient": "", "draft_subject": "", "draft_body_snippet": "",
        "sent_count": 0, "outbox_count": 0, "compose_window_opened": False,
        "thunderbird_running": True,
    }
    r = verify_compose_send_email([], {"copy_from_env": make_mock_copy(data)}, TASK_INFO)
    print(f"  passed={r['passed']}, score={r['score']}")
    print(f"  feedback: {r['feedback']}")
    ok = not r['passed'] and r['score'] <= 25
    print(f"  {'PASS' if ok else 'FAIL'}: do-nothing should fail with score<=25")
    tests_passed += int(ok)

    # Test 2: Partial work (draft saved, wrong content)
    print("\n" + "=" * 60)
    print("TEST 2: Partial work (draft saved, wrong recipient/subject)")
    data = {
        "draft_added": True, "initial_drafts_count": 0, "current_drafts_count": 1,
        "draft_recipient": "someone@wrong.com", "draft_subject": "Hello World",
        "draft_body_snippet": "Just testing the email client.",
        "sent_count": 0, "outbox_count": 0, "compose_window_opened": False,
        "thunderbird_running": True,
    }
    r = verify_compose_send_email([], {"copy_from_env": make_mock_copy(data)}, TASK_INFO)
    print(f"  passed={r['passed']}, score={r['score']}")
    print(f"  feedback: {r['feedback']}")
    ok = not r['passed'] and r['score'] < 60
    print(f"  {'PASS' if ok else 'FAIL'}: partial work should fail with score<60")
    tests_passed += int(ok)

    # Test 3: Correct completion
    print("\n" + "=" * 60)
    print("TEST 3: Correct completion (all criteria met)")
    data = {
        "draft_added": True, "initial_drafts_count": 0, "current_drafts_count": 1,
        "draft_recipient": "colleague@example.com",
        "draft_subject": "Q4 Budget Review Meeting",
        "draft_body_snippet": "I'd like to schedule a meeting to discuss our Q4 budget allocations.",
        "sent_count": 0, "outbox_count": 0, "compose_window_opened": False,
        "thunderbird_running": True,
    }
    r = verify_compose_send_email([], {"copy_from_env": make_mock_copy(data)}, TASK_INFO)
    print(f"  passed={r['passed']}, score={r['score']}")
    print(f"  feedback: {r['feedback']}")
    ok = r['passed'] and r['score'] >= 60
    print(f"  {'PASS' if ok else 'FAIL'}: correct completion should pass with score>=60")
    tests_passed += int(ok)

    # Test 4: Wrong parameters
    print("\n" + "=" * 60)
    print("TEST 4: Wrong parameters (draft saved, completely wrong values)")
    data = {
        "draft_added": True, "initial_drafts_count": 0, "current_drafts_count": 1,
        "draft_recipient": "boss@company.com", "draft_subject": "Lunch Plans Friday",
        "draft_body_snippet": "Want to grab lunch on Friday?",
        "sent_count": 0, "outbox_count": 0, "compose_window_opened": False,
        "thunderbird_running": True,
    }
    r = verify_compose_send_email([], {"copy_from_env": make_mock_copy(data)}, TASK_INFO)
    print(f"  passed={r['passed']}, score={r['score']}")
    print(f"  feedback: {r['feedback']}")
    ok = not r['passed']
    print(f"  {'PASS' if ok else 'FAIL'}: wrong parameters should fail")
    tests_passed += int(ok)

    print("\n" + "=" * 60)
    print(f"RESULTS: {tests_passed}/{tests_total} tests passed")
    sys.exit(0 if tests_passed == tests_total else 1)
