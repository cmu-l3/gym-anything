#!/usr/bin/env python3
"""
Verifier for hr_onboarding_pipeline task.

An HR Manager must organize a new employee onboarding inbox into subfolders,
add the IT Director to the address book, and compose a draft coordination
email to the IT Director confirming new hire start details.

Scoring (100 points total):
- Onboarding_Q1 parent folder structure created: 10 pts
- Documents_Pending subfolder with ≥3 emails: 20 pts
- IT_Requests subfolder with ≥4 emails: 25 pts
- Marcus Thompson (m.thompson@techventure-it.com) added to address book: 20 pts
- Draft reply to Marcus Thompson with start-date keywords: up to 25 pts

Pass threshold: 60 points
Wrong-target guard: if Onboarding_Q1.sbd exists but all subfolders have 0 emails → score capped
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/hr_onboarding_pipeline_result.json"
PASS_THRESHOLD = 60


def verify_hr_onboarding_pipeline(traj, env_info, task_info):
    """Verify HR onboarding pipeline task completion."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_from_env(RESULT_PATH, tmp.name)
            with open(tmp.name, 'r', encoding='utf-8') as f:
                result = json.load(f)
        finally:
            try:
                os.unlink(tmp.name)
            except Exception:
                pass
    except FileNotFoundError:
        return {"passed": False, "score": 0,
                "feedback": "Result file not found — agent may not have completed the task"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}

    score = 0
    feedback_parts = []

    # ================================================================
    # WRONG-TARGET GUARD
    # ================================================================
    onboarding_exists = result.get('onboarding_sbd_exists', False)
    docs_count = int(result.get('docs_email_count', 0))
    it_count = int(result.get('it_email_count', 0))
    total_moved = docs_count + it_count

    if onboarding_exists and total_moved == 0:
        return {
            "passed": False,
            "score": 5,
            "feedback": "GUARD: Onboarding folder structure created but no emails moved — agent must route emails to subfolders"
        }

    # ================================================================
    # CRITERION 1: Onboarding_Q1.sbd directory — 10 pts
    # ================================================================
    if onboarding_exists:
        score += 10
        feedback_parts.append("Onboarding_Q1 folder structure created (10/10)")
    else:
        feedback_parts.append("Onboarding_Q1 folder structure NOT created (0/10)")

    # ================================================================
    # CRITERION 2: Documents_Pending subfolder with ≥3 emails — 20 pts
    # ================================================================
    docs_folder = result.get('docs_folder', '')
    if docs_folder and docs_count >= 3:
        score += 20
        feedback_parts.append(f"Documents_Pending subfolder '{docs_folder}' has {docs_count} emails (20/20)")
    elif docs_folder and docs_count >= 2:
        score += 13
        feedback_parts.append(f"Documents_Pending subfolder '{docs_folder}' has {docs_count} emails — expected ≥3 (13/20)")
    elif docs_folder and docs_count >= 1:
        score += 6
        feedback_parts.append(f"Documents_Pending subfolder '{docs_folder}' has {docs_count} email (6/20)")
    elif docs_folder:
        score += 3
        feedback_parts.append(f"Documents_Pending subfolder '{docs_folder}' found but empty (3/20)")
    else:
        feedback_parts.append("Documents_Pending subfolder not found (0/20)")

    # ================================================================
    # CRITERION 3: IT_Requests subfolder with ≥4 emails — 25 pts
    # ================================================================
    it_folder = result.get('it_folder', '')
    if it_folder and it_count >= 4:
        score += 25
        feedback_parts.append(f"IT_Requests subfolder '{it_folder}' has {it_count} emails (25/25)")
    elif it_folder and it_count >= 2:
        score += 13
        feedback_parts.append(f"IT_Requests subfolder '{it_folder}' has {it_count} emails — expected ≥4 (13/25)")
    elif it_folder and it_count >= 1:
        score += 6
        feedback_parts.append(f"IT_Requests subfolder '{it_folder}' has {it_count} email (6/25)")
    elif it_folder:
        score += 3
        feedback_parts.append(f"IT_Requests subfolder '{it_folder}' found but empty (3/25)")
    else:
        feedback_parts.append("IT_Requests subfolder not found (0/25)")

    # ================================================================
    # CRITERION 4: Marcus Thompson in address book — 20 pts
    # ================================================================
    marcus_in_abook = result.get('marcus_thompson_in_abook', False)
    marcus_email_in_abook = result.get('marcus_thompson_email_in_abook', False)
    if marcus_email_in_abook:
        score += 20
        feedback_parts.append("Marcus Thompson (m.thompson@techventure-it.com) added to address book (20/20)")
    elif marcus_in_abook:
        score += 12
        feedback_parts.append("Marcus Thompson name found but email not confirmed (12/20)")
    else:
        feedback_parts.append("Marcus Thompson not found in address book (0/20)")

    # ================================================================
    # CRITERION 5: Draft reply to Marcus Thompson — up to 25 pts
    # ================================================================
    draft_to_marcus = result.get('draft_to_marcus', False)
    draft_has_keywords = result.get('draft_has_keywords', False)
    if draft_to_marcus and draft_has_keywords:
        score += 25
        feedback_parts.append("Draft reply to m.thompson@techventure-it.com with start-date content found (25/25)")
    elif draft_to_marcus:
        score += 15
        feedback_parts.append("Draft to Marcus Thompson found but missing new-hire keywords (15/25)")
    else:
        feedback_parts.append("No draft reply to m.thompson@techventure-it.com found in Drafts (0/25)")

    # ================================================================
    # SCORE CAP
    # ================================================================
    if total_moved == 0 and score >= PASS_THRESHOLD:
        score = PASS_THRESHOLD - 1
        feedback_parts.append(f"Score capped at {PASS_THRESHOLD - 1}: no emails routed to onboarding subfolders")

    passed = score >= PASS_THRESHOLD

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts),
        "details": {
            "onboarding_sbd_exists": onboarding_exists,
            "docs_folder": result.get('docs_folder', ''),
            "docs_count": docs_count,
            "it_folder": result.get('it_folder', ''),
            "it_count": it_count,
            "marcus_thompson_in_abook": marcus_in_abook,
            "draft_to_marcus": draft_to_marcus,
            "draft_has_keywords": draft_has_keywords,
            "total_emails_moved": total_moved,
        }
    }


if __name__ == "__main__":
    """Pipeline tests for hr_onboarding_pipeline verifier."""
    import sys

    TASK_INFO = {"metadata": {}}

    def make_env(result_dict):
        import json, tempfile, shutil
        tf = tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False)
        json.dump(result_dict, tf)
        tf.close()
        def copy_fn(src, dst):
            shutil.copy(tf.name, dst)
        return {"copy_from_env": copy_fn}

    tests_passed = 0
    total_tests = 4

    print("=" * 60)
    print("TEST 1: Do-nothing baseline")
    r = verify_hr_onboarding_pipeline([], make_env({
        "task_start": 1700000000, "inbox_baseline": 9, "current_inbox_count": 9,
        "onboarding_sbd_exists": False,
        "docs_folder": "", "docs_email_count": 0,
        "it_folder": "", "it_email_count": 0,
        "draft_to_marcus": False, "draft_has_keywords": False,
        "marcus_thompson_in_abook": False, "marcus_thompson_email_in_abook": False,
    }), TASK_INFO)
    print(f"  score={r['score']}, passed={r['passed']}")
    ok = not r['passed'] and r['score'] == 0
    print(f"  {'PASS' if ok else 'FAIL'}: do-nothing score should be 0")
    tests_passed += int(ok)

    print("\n" + "=" * 60)
    print("TEST 2: Folders created but no emails moved")
    r = verify_hr_onboarding_pipeline([], make_env({
        "task_start": 1700000000, "inbox_baseline": 9, "current_inbox_count": 9,
        "onboarding_sbd_exists": True,
        "docs_folder": "Documents_Pending", "docs_email_count": 0,
        "it_folder": "IT_Requests", "it_email_count": 0,
        "draft_to_marcus": False, "draft_has_keywords": False,
        "marcus_thompson_in_abook": False, "marcus_thompson_email_in_abook": False,
    }), TASK_INFO)
    print(f"  score={r['score']}, passed={r['passed']}")
    ok = not r['passed'] and r['score'] <= 10
    print(f"  {'PASS' if ok else 'FAIL'}: empty folders guard should score ≤10 and not pass")
    tests_passed += int(ok)

    print("\n" + "=" * 60)
    print("TEST 3: Partial completion (IT done, no docs, no contact, no draft)")
    r = verify_hr_onboarding_pipeline([], make_env({
        "task_start": 1700000000, "inbox_baseline": 9, "current_inbox_count": 5,
        "onboarding_sbd_exists": True,
        "docs_folder": "", "docs_email_count": 0,
        "it_folder": "IT_Requests", "it_email_count": 4,
        "draft_to_marcus": False, "draft_has_keywords": False,
        "marcus_thompson_in_abook": False, "marcus_thompson_email_in_abook": False,
    }), TASK_INFO)
    print(f"  score={r['score']}, passed={r['passed']}")
    ok = not r['passed'] and 0 < r['score'] < PASS_THRESHOLD
    print(f"  {'PASS' if ok else 'FAIL'}: partial completion should not pass (score={r['score']})")
    tests_passed += int(ok)

    print("\n" + "=" * 60)
    print("TEST 4: Full completion")
    r = verify_hr_onboarding_pipeline([], make_env({
        "task_start": 1700000000, "inbox_baseline": 9, "current_inbox_count": 2,
        "onboarding_sbd_exists": True,
        "docs_folder": "Documents_Pending", "docs_email_count": 3,
        "it_folder": "IT_Requests", "it_email_count": 4,
        "draft_to_marcus": True, "draft_has_keywords": True,
        "marcus_thompson_in_abook": True, "marcus_thompson_email_in_abook": True,
    }), TASK_INFO)
    print(f"  score={r['score']}, passed={r['passed']}")
    ok = r['passed'] and r['score'] >= PASS_THRESHOLD
    print(f"  {'PASS' if ok else 'FAIL'}: full completion should pass with score≥{PASS_THRESHOLD}")
    tests_passed += int(ok)

    print("\n" + "=" * 60)
    print(f"RESULTS: {tests_passed}/{total_tests} tests passed")
    sys.exit(0 if tests_passed == total_tests else 1)
