#!/usr/bin/env python3
"""
Verifier for medical_referral_triage task.

A practice manager must organize a medical referral inbox, route urgent and
routine referrals to appropriate subfolders, add a key referring physician to
the address book, and tag the urgent referral emails as Important.

Scoring (100 points total):
- Referrals parent folder structure created: 10 pts
- Urgent_Referrals subfolder with ≥3 emails: 25 pts
- Routine_Referrals subfolder with ≥3 emails: 20 pts
- Dr. Patricia Nguyen (p.nguyen@bayviewcardiology.com) in address book: 20 pts
- ≥1 urgent referral email tagged (Important or any tag): 15 pts (25 if ≥3 tagged)

Pass threshold: 60 points
Wrong-target guard: if Referrals.sbd exists but all subfolders have 0 emails → score capped

Features exercised: folder hierarchy, email routing, address book, email tagging
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/medical_referral_triage_result.json"
PASS_THRESHOLD = 60


def verify_medical_referral_triage(traj, env_info, task_info):
    """Verify medical referral triage task completion."""
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
    referrals_exists = result.get('referrals_sbd_exists', False)
    urgent_count = int(result.get('urgent_email_count', 0))
    routine_count = int(result.get('routine_email_count', 0))
    total_moved = urgent_count + routine_count

    if referrals_exists and total_moved == 0:
        return {
            "passed": False,
            "score": 5,
            "feedback": "GUARD: Referrals folder structure created but no emails moved — agent must route referrals to subfolders"
        }

    # ================================================================
    # CRITERION 1: Referrals.sbd directory — 10 pts
    # ================================================================
    if referrals_exists:
        score += 10
        feedback_parts.append("Referrals folder structure created (10/10)")
    else:
        feedback_parts.append("Referrals folder structure NOT created (0/10)")

    # ================================================================
    # CRITERION 2: Urgent_Referrals subfolder with ≥3 emails — 25 pts
    # ================================================================
    urgent_folder = result.get('urgent_folder', '')
    if urgent_folder and urgent_count >= 3:
        score += 25
        feedback_parts.append(f"Urgent_Referrals subfolder '{urgent_folder}' has {urgent_count} emails (25/25)")
    elif urgent_folder and urgent_count >= 2:
        score += 15
        feedback_parts.append(f"Urgent_Referrals subfolder '{urgent_folder}' has {urgent_count} emails — expected ≥3 (15/25)")
    elif urgent_folder and urgent_count >= 1:
        score += 7
        feedback_parts.append(f"Urgent_Referrals subfolder '{urgent_folder}' has {urgent_count} email (7/25)")
    elif urgent_folder:
        score += 3
        feedback_parts.append(f"Urgent_Referrals subfolder '{urgent_folder}' found but empty (3/25)")
    else:
        feedback_parts.append("Urgent_Referrals subfolder not found (0/25)")

    # ================================================================
    # CRITERION 3: Routine_Referrals subfolder with ≥3 emails — 20 pts
    # ================================================================
    routine_folder = result.get('routine_folder', '')
    if routine_folder and routine_count >= 3:
        score += 20
        feedback_parts.append(f"Routine_Referrals subfolder '{routine_folder}' has {routine_count} emails (20/20)")
    elif routine_folder and routine_count >= 2:
        score += 12
        feedback_parts.append(f"Routine_Referrals subfolder '{routine_folder}' has {routine_count} emails — expected ≥3 (12/20)")
    elif routine_folder and routine_count >= 1:
        score += 5
        feedback_parts.append(f"Routine_Referrals subfolder '{routine_folder}' has {routine_count} email (5/20)")
    elif routine_folder:
        score += 2
        feedback_parts.append(f"Routine_Referrals subfolder '{routine_folder}' found but empty (2/20)")
    else:
        feedback_parts.append("Routine_Referrals subfolder not found (0/20)")

    # ================================================================
    # CRITERION 4: Dr. Patricia Nguyen in address book — 20 pts
    # ================================================================
    nguyen_in_abook = result.get('nguyen_in_abook', False)
    nguyen_email_in_abook = result.get('nguyen_email_in_abook', False)
    if nguyen_email_in_abook:
        score += 20
        feedback_parts.append("Dr. Patricia Nguyen (p.nguyen@bayviewcardiology.com) added to address book (20/20)")
    elif nguyen_in_abook:
        score += 12
        feedback_parts.append("Dr. Nguyen name found but email not confirmed (12/20)")
    else:
        feedback_parts.append("Dr. Patricia Nguyen not found in address book (0/20)")

    # ================================================================
    # CRITERION 5: Urgent referral emails tagged — up to 25 pts
    # ================================================================
    tagged_count = int(result.get('tagged_urgent_count', 0))
    if tagged_count >= 3:
        score += 25
        feedback_parts.append(f"All 3 urgent referral emails tagged as Important (25/25)")
    elif tagged_count >= 2:
        score += 18
        feedback_parts.append(f"{tagged_count} urgent emails tagged — expected 3 (18/25)")
    elif tagged_count >= 1:
        score += 10
        feedback_parts.append(f"{tagged_count} urgent email tagged — expected 3 (10/25)")
    else:
        feedback_parts.append("No urgent referral emails found tagged (0/25)")

    # ================================================================
    # SCORE CAP
    # ================================================================
    if total_moved == 0 and score >= PASS_THRESHOLD:
        score = PASS_THRESHOLD - 1
        feedback_parts.append(f"Score capped at {PASS_THRESHOLD - 1}: no referrals routed to subfolders")

    passed = score >= PASS_THRESHOLD

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts),
        "details": {
            "referrals_sbd_exists": referrals_exists,
            "urgent_folder": result.get('urgent_folder', ''),
            "urgent_count": urgent_count,
            "routine_folder": result.get('routine_folder', ''),
            "routine_count": routine_count,
            "nguyen_in_abook": nguyen_in_abook,
            "tagged_urgent_count": tagged_count,
            "total_emails_moved": total_moved,
        }
    }


if __name__ == "__main__":
    """Pipeline tests for medical_referral_triage verifier."""
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
    r = verify_medical_referral_triage([], make_env({
        "task_start": 1700000000, "inbox_baseline": 9, "current_inbox_count": 9,
        "referrals_sbd_exists": False,
        "urgent_folder": "", "urgent_email_count": 0,
        "routine_folder": "", "routine_email_count": 0,
        "tagged_urgent_count": 0,
        "nguyen_in_abook": False, "nguyen_email_in_abook": False,
    }), TASK_INFO)
    print(f"  score={r['score']}, passed={r['passed']}")
    ok = not r['passed'] and r['score'] == 0
    print(f"  {'PASS' if ok else 'FAIL'}: do-nothing score should be 0")
    tests_passed += int(ok)

    print("\n" + "=" * 60)
    print("TEST 2: Folders created but no emails moved")
    r = verify_medical_referral_triage([], make_env({
        "task_start": 1700000000, "inbox_baseline": 9, "current_inbox_count": 9,
        "referrals_sbd_exists": True,
        "urgent_folder": "Urgent_Referrals", "urgent_email_count": 0,
        "routine_folder": "Routine_Referrals", "routine_email_count": 0,
        "tagged_urgent_count": 0,
        "nguyen_in_abook": False, "nguyen_email_in_abook": False,
    }), TASK_INFO)
    print(f"  score={r['score']}, passed={r['passed']}")
    ok = not r['passed'] and r['score'] <= 10
    print(f"  {'PASS' if ok else 'FAIL'}: empty folders guard should score ≤10 and not pass")
    tests_passed += int(ok)

    print("\n" + "=" * 60)
    print("TEST 3: Partial completion (routing done, no contact, no tags)")
    r = verify_medical_referral_triage([], make_env({
        "task_start": 1700000000, "inbox_baseline": 9, "current_inbox_count": 2,
        "referrals_sbd_exists": True,
        "urgent_folder": "Urgent_Referrals", "urgent_email_count": 3,
        "routine_folder": "Routine_Referrals", "routine_email_count": 4,
        "tagged_urgent_count": 0,
        "nguyen_in_abook": False, "nguyen_email_in_abook": False,
    }), TASK_INFO)
    print(f"  score={r['score']}, passed={r['passed']}")
    ok = not r['passed'] and 0 < r['score'] < PASS_THRESHOLD
    print(f"  {'PASS' if ok else 'FAIL'}: partial completion should not pass (score={r['score']})")
    tests_passed += int(ok)

    print("\n" + "=" * 60)
    print("TEST 4: Full completion")
    r = verify_medical_referral_triage([], make_env({
        "task_start": 1700000000, "inbox_baseline": 9, "current_inbox_count": 2,
        "referrals_sbd_exists": True,
        "urgent_folder": "Urgent_Referrals", "urgent_email_count": 3,
        "routine_folder": "Routine_Referrals", "routine_email_count": 4,
        "tagged_urgent_count": 3,
        "nguyen_in_abook": True, "nguyen_email_in_abook": True,
    }), TASK_INFO)
    print(f"  score={r['score']}, passed={r['passed']}")
    ok = r['passed'] and r['score'] >= PASS_THRESHOLD
    print(f"  {'PASS' if ok else 'FAIL'}: full completion should pass with score≥{PASS_THRESHOLD}")
    tests_passed += int(ok)

    print("\n" + "=" * 60)
    print(f"RESULTS: {tests_passed}/{total_tests} tests passed")
    sys.exit(0 if tests_passed == total_tests else 1)
