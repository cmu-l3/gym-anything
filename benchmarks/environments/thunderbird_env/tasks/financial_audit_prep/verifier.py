#!/usr/bin/env python3
"""
Verifier for financial_audit_prep task.

A financial controller must organize a regulatory examination inbox into
compliance folders, add the lead examiner to the address book, and compose
a draft acknowledgment email to the SEC examiner.

Scoring (100 points total):
- Regulatory parent folder structure created: 10 pts
- SEC_Examination subfolder with ≥4 emails: 25 pts
- FINRA_Review subfolder with ≥3 emails: 20 pts
- Jennifer Kowalski (jkowalski@sec.gov) added to address book: 20 pts
- Draft reply composed to jkowalski@sec.gov: 15 pts (+ 10 bonus if has keywords)

Pass threshold: 60 points
Wrong-target guard: if Regulatory.sbd exists but all subfolders have 0 emails → score capped

Features exercised: folder hierarchy, email routing, address book, draft email composition
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/financial_audit_prep_result.json"
PASS_THRESHOLD = 60


def verify_financial_audit_prep(traj, env_info, task_info):
    """Verify financial audit prep task completion."""
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
    # WRONG-TARGET GUARD: folders created but no emails moved
    # ================================================================
    regulatory_exists = result.get('regulatory_sbd_exists', False)
    sec_count = int(result.get('sec_email_count', 0))
    finra_count = int(result.get('finra_email_count', 0))
    total_moved = sec_count + finra_count

    if regulatory_exists and total_moved == 0:
        return {
            "passed": False,
            "score": 5,
            "feedback": "GUARD: Regulatory folder structure created but no emails moved — agent must route emails to subfolders"
        }

    # ================================================================
    # CRITERION 1: Regulatory.sbd directory — 10 pts
    # ================================================================
    if regulatory_exists:
        score += 10
        feedback_parts.append("Regulatory folder structure created (10/10)")
    else:
        feedback_parts.append("Regulatory folder structure NOT created (0/10)")

    # ================================================================
    # CRITERION 2: SEC_Examination subfolder with ≥4 emails — 25 pts
    # ================================================================
    sec_folder = result.get('sec_folder', '')
    if sec_folder and sec_count >= 4:
        score += 25
        feedback_parts.append(f"SEC_Examination subfolder '{sec_folder}' has {sec_count} emails (25/25)")
    elif sec_folder and sec_count >= 2:
        score += 13
        feedback_parts.append(f"SEC_Examination subfolder '{sec_folder}' has {sec_count} emails — expected ≥4 (13/25)")
    elif sec_folder and sec_count >= 1:
        score += 6
        feedback_parts.append(f"SEC_Examination subfolder '{sec_folder}' has {sec_count} email (6/25)")
    elif sec_folder:
        score += 3
        feedback_parts.append(f"SEC_Examination subfolder '{sec_folder}' found but empty (3/25)")
    else:
        feedback_parts.append("SEC_Examination subfolder not found (0/25)")

    # ================================================================
    # CRITERION 3: FINRA_Review subfolder with ≥3 emails — 20 pts
    # ================================================================
    finra_folder = result.get('finra_folder', '')
    if finra_folder and finra_count >= 3:
        score += 20
        feedback_parts.append(f"FINRA_Review subfolder '{finra_folder}' has {finra_count} emails (20/20)")
    elif finra_folder and finra_count >= 2:
        score += 12
        feedback_parts.append(f"FINRA_Review subfolder '{finra_folder}' has {finra_count} emails — expected ≥3 (12/20)")
    elif finra_folder and finra_count >= 1:
        score += 5
        feedback_parts.append(f"FINRA_Review subfolder '{finra_folder}' has {finra_count} email (5/20)")
    elif finra_folder:
        score += 2
        feedback_parts.append(f"FINRA_Review subfolder '{finra_folder}' found but empty (2/20)")
    else:
        feedback_parts.append("FINRA_Review subfolder not found (0/20)")

    # ================================================================
    # CRITERION 4: Jennifer Kowalski in address book — 20 pts
    # ================================================================
    jennifer_in_abook = result.get('jennifer_kowalski_in_abook', False)
    jennifer_email_in_abook = result.get('jennifer_kowalski_email_in_abook', False)
    if jennifer_email_in_abook:
        score += 20
        feedback_parts.append("Jennifer Kowalski (jkowalski@sec.gov) added to address book (20/20)")
    elif jennifer_in_abook:
        score += 12
        feedback_parts.append("Jennifer Kowalski name found but email not confirmed (12/20)")
    else:
        feedback_parts.append("Jennifer Kowalski not found in address book (0/20)")

    # ================================================================
    # CRITERION 5: Draft reply to jkowalski@sec.gov — 15 pts (+10 bonus for keywords)
    # ================================================================
    draft_to_kowalski = result.get('draft_to_kowalski', False)
    draft_has_keywords = result.get('draft_has_keywords', False)
    if draft_to_kowalski and draft_has_keywords:
        score += 25
        feedback_parts.append("Draft reply to jkowalski@sec.gov composed with relevant content (25/25)")
    elif draft_to_kowalski:
        score += 15
        feedback_parts.append("Draft reply to jkowalski@sec.gov found in Drafts folder (15/25)")
    else:
        feedback_parts.append("No draft reply to jkowalski@sec.gov found in Drafts (0/25)")

    # ================================================================
    # SCORE CAP: no emails routed
    # ================================================================
    if total_moved == 0 and score >= PASS_THRESHOLD:
        score = PASS_THRESHOLD - 1
        feedback_parts.append(f"Score capped at {PASS_THRESHOLD - 1}: no emails routed to regulatory folders")

    passed = score >= PASS_THRESHOLD

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts),
        "details": {
            "regulatory_sbd_exists": regulatory_exists,
            "sec_folder": result.get('sec_folder', ''),
            "sec_count": sec_count,
            "finra_folder": result.get('finra_folder', ''),
            "finra_count": finra_count,
            "jennifer_kowalski_in_abook": jennifer_in_abook,
            "draft_to_kowalski": draft_to_kowalski,
            "draft_has_keywords": draft_has_keywords,
            "total_emails_moved": total_moved,
        }
    }


if __name__ == "__main__":
    """Pipeline tests for financial_audit_prep verifier."""
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
    r = verify_financial_audit_prep([], make_env({
        "task_start": 1700000000, "inbox_baseline": 9, "current_inbox_count": 9,
        "regulatory_sbd_exists": False,
        "sec_folder": "", "sec_email_count": 0,
        "finra_folder": "", "finra_email_count": 0,
        "jennifer_kowalski_in_abook": False, "jennifer_kowalski_email_in_abook": False,
        "draft_to_kowalski": False, "draft_has_keywords": False,
    }), TASK_INFO)
    print(f"  score={r['score']}, passed={r['passed']}")
    ok = not r['passed'] and r['score'] == 0
    print(f"  {'PASS' if ok else 'FAIL'}: do-nothing score should be 0")
    tests_passed += int(ok)

    print("\n" + "=" * 60)
    print("TEST 2: Folders created but no emails moved (wrong-target guard)")
    r = verify_financial_audit_prep([], make_env({
        "task_start": 1700000000, "inbox_baseline": 9, "current_inbox_count": 9,
        "regulatory_sbd_exists": True,
        "sec_folder": "SEC_Examination", "sec_email_count": 0,
        "finra_folder": "FINRA_Review", "finra_email_count": 0,
        "jennifer_kowalski_in_abook": False, "jennifer_kowalski_email_in_abook": False,
        "draft_to_kowalski": False, "draft_has_keywords": False,
    }), TASK_INFO)
    print(f"  score={r['score']}, passed={r['passed']}")
    ok = not r['passed'] and r['score'] <= 10
    print(f"  {'PASS' if ok else 'FAIL'}: empty folders guard should score ≤10 and not pass")
    tests_passed += int(ok)

    print("\n" + "=" * 60)
    print("TEST 3: Partial completion (folders + routing but no draft or contact)")
    r = verify_financial_audit_prep([], make_env({
        "task_start": 1700000000, "inbox_baseline": 9, "current_inbox_count": 2,
        "regulatory_sbd_exists": True,
        "sec_folder": "SEC_Examination", "sec_email_count": 4,
        "finra_folder": "FINRA_Review", "finra_email_count": 3,
        "jennifer_kowalski_in_abook": False, "jennifer_kowalski_email_in_abook": False,
        "draft_to_kowalski": False, "draft_has_keywords": False,
    }), TASK_INFO)
    print(f"  score={r['score']}, passed={r['passed']}")
    ok = not r['passed'] and 0 < r['score'] < PASS_THRESHOLD
    print(f"  {'PASS' if ok else 'FAIL'}: partial completion should not pass (score={r['score']})")
    tests_passed += int(ok)

    print("\n" + "=" * 60)
    print("TEST 4: Full completion")
    r = verify_financial_audit_prep([], make_env({
        "task_start": 1700000000, "inbox_baseline": 9, "current_inbox_count": 2,
        "regulatory_sbd_exists": True,
        "sec_folder": "SEC_Examination", "sec_email_count": 4,
        "finra_folder": "FINRA_Review", "finra_email_count": 3,
        "jennifer_kowalski_in_abook": True, "jennifer_kowalski_email_in_abook": True,
        "draft_to_kowalski": True, "draft_has_keywords": True,
    }), TASK_INFO)
    print(f"  score={r['score']}, passed={r['passed']}")
    ok = r['passed'] and r['score'] >= PASS_THRESHOLD
    print(f"  {'PASS' if ok else 'FAIL'}: full completion should pass with score≥{PASS_THRESHOLD}")
    tests_passed += int(ok)

    print("\n" + "=" * 60)
    print(f"RESULTS: {tests_passed}/{total_tests} tests passed")
    sys.exit(0 if tests_passed == total_tests else 1)
