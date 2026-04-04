#!/usr/bin/env python3
"""
Verifier for legal_case_triage task.

A paralegal must organize a mixed law firm inbox into case folders,
add opposing counsel to the address book, and create a court notice filter.

Scoring (100 points total):
- Cases parent folder structure created: 10 pts
- Harrison_Mercer subfolder with ≥4 emails: 20 pts
- DataVault_IP subfolder with ≥3 emails: 20 pts
- Chen_Estate subfolder with ≥2 emails: 15 pts
- Marcus Webb (opposing counsel) added to address book: 20 pts
- Court clerk filter OR Court_Notices folder created: 15 pts

Pass threshold: 60 points
Wrong-target guard: if Cases.sbd exists but all subfolders have 0 emails → score capped
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/legal_case_triage_result.json"
PASS_THRESHOLD = 60


def verify_legal_case_triage(traj, env_info, task_info):
    """Verify legal case triage task completion."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Load result JSON from VM
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
    # WRONG-TARGET GUARD: if Cases.sbd was created but all folders are
    # empty (0 emails each), the agent made folders but never moved emails.
    # Cap score at PASS_THRESHOLD - 1 to prevent cheating.
    # ================================================================
    cases_exists = result.get('cases_sbd_exists', False)
    harrison_count = int(result.get('harrison_email_count', 0))
    datavault_count = int(result.get('datavault_email_count', 0))
    chen_count = int(result.get('chen_email_count', 0))
    total_moved = harrison_count + datavault_count + chen_count

    if cases_exists and total_moved == 0:
        return {
            "passed": False,
            "score": 5,
            "feedback": "GUARD: Cases folder structure created but no emails moved — agent must route emails to case subfolders"
        }

    # ================================================================
    # CRITERION 1: Cases.sbd directory (nested folder structure) — 10 pts
    # ================================================================
    if cases_exists:
        score += 10
        feedback_parts.append("Cases folder structure created (10/10)")
    else:
        feedback_parts.append("Cases folder structure NOT created (0/10)")

    # ================================================================
    # CRITERION 2: Harrison_Mercer subfolder with ≥4 emails — 20 pts
    # ================================================================
    harrison_folder = result.get('harrison_folder', '')
    if harrison_folder and harrison_count >= 4:
        score += 20
        feedback_parts.append(f"Harrison_Mercer subfolder '{harrison_folder}' has {harrison_count} emails (20/20)")
    elif harrison_folder and harrison_count >= 2:
        score += 10
        feedback_parts.append(f"Harrison_Mercer subfolder '{harrison_folder}' has only {harrison_count} emails — expected ≥4 (10/20)")
    elif harrison_folder:
        score += 5
        feedback_parts.append(f"Harrison_Mercer subfolder '{harrison_folder}' found but has {harrison_count} emails (5/20)")
    else:
        feedback_parts.append("Harrison_Mercer subfolder not found (0/20)")

    # ================================================================
    # CRITERION 3: DataVault_IP subfolder with ≥3 emails — 20 pts
    # ================================================================
    datavault_folder = result.get('datavault_folder', '')
    if datavault_folder and datavault_count >= 3:
        score += 20
        feedback_parts.append(f"DataVault_IP subfolder '{datavault_folder}' has {datavault_count} emails (20/20)")
    elif datavault_folder and datavault_count >= 2:
        score += 12
        feedback_parts.append(f"DataVault_IP subfolder '{datavault_folder}' has {datavault_count} emails — expected ≥3 (12/20)")
    elif datavault_folder:
        score += 5
        feedback_parts.append(f"DataVault_IP subfolder '{datavault_folder}' found but has {datavault_count} emails (5/20)")
    else:
        feedback_parts.append("DataVault_IP subfolder not found (0/20)")

    # ================================================================
    # CRITERION 4: Chen_Estate subfolder with ≥2 emails — 15 pts
    # ================================================================
    chen_folder = result.get('chen_folder', '')
    if chen_folder and chen_count >= 2:
        score += 15
        feedback_parts.append(f"Chen_Estate subfolder '{chen_folder}' has {chen_count} emails (15/15)")
    elif chen_folder and chen_count >= 1:
        score += 8
        feedback_parts.append(f"Chen_Estate subfolder '{chen_folder}' has {chen_count} email — expected ≥2 (8/15)")
    elif chen_folder:
        score += 3
        feedback_parts.append(f"Chen_Estate subfolder '{chen_folder}' found but empty (3/15)")
    else:
        feedback_parts.append("Chen_Estate subfolder not found (0/15)")

    # ================================================================
    # CRITERION 5: Marcus Webb (opposing counsel) in address book — 20 pts
    # ================================================================
    marcus_in_abook = result.get('marcus_webb_in_abook', False)
    marcus_email_in_abook = result.get('marcus_webb_email_in_abook', False)
    if marcus_email_in_abook:
        score += 20
        feedback_parts.append("Marcus Webb (mwebb@hartleypatent.com) added to address book (20/20)")
    elif marcus_in_abook:
        score += 12
        feedback_parts.append("Marcus Webb name found in address book but email not confirmed (12/20)")
    else:
        feedback_parts.append("Marcus Webb not found in address book (0/20)")

    # ================================================================
    # CRITERION 6: Court clerk filter OR Court_Notices folder — 15 pts
    # ================================================================
    court_filter = result.get('court_filter_exists', False)
    court_notices = result.get('court_notices_exists', False)
    if court_filter and court_notices:
        score += 15
        feedback_parts.append(f"Court filter created AND Court_Notices folder exists (15/15)")
    elif court_filter:
        score += 12
        feedback_parts.append(f"Court filter created (Court_Notices folder not found separately) (12/15)")
    elif court_notices:
        score += 8
        feedback_parts.append("Court_Notices folder created but no filter rule found (8/15)")
    else:
        feedback_parts.append("No court filter or Court_Notices folder found (0/15)")

    # ================================================================
    # SCORE CAP: If no emails were moved to any case folder,
    # cap score below pass threshold (partial folder creation without routing)
    # ================================================================
    if total_moved == 0 and score >= PASS_THRESHOLD:
        score = PASS_THRESHOLD - 1
        feedback_parts.append(f"Score capped at {PASS_THRESHOLD - 1}: no emails routed to case folders")

    passed = score >= PASS_THRESHOLD

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts),
        "details": {
            "cases_sbd_exists": cases_exists,
            "harrison_folder": result.get('harrison_folder', ''),
            "harrison_count": harrison_count,
            "datavault_folder": result.get('datavault_folder', ''),
            "datavault_count": datavault_count,
            "chen_folder": result.get('chen_folder', ''),
            "chen_count": chen_count,
            "marcus_webb_in_abook": marcus_in_abook,
            "court_filter_exists": court_filter,
            "court_notices_exists": court_notices,
            "total_emails_moved": total_moved,
        }
    }


if __name__ == "__main__":
    """Pipeline tests for legal_case_triage verifier."""
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

    # Test 1: Do-nothing (export ran, agent did nothing)
    print("=" * 60)
    print("TEST 1: Do-nothing baseline")
    r = verify_legal_case_triage([], make_env({
        "task_start": 1700000000,
        "inbox_baseline": 12,
        "current_inbox_count": 12,
        "cases_sbd_exists": False,
        "harrison_folder": "", "harrison_email_count": 0,
        "datavault_folder": "", "datavault_email_count": 0,
        "chen_folder": "", "chen_email_count": 0,
        "court_notices_exists": False, "court_filter_exists": False,
        "court_filter_name": "",
        "marcus_webb_in_abook": False, "marcus_webb_email_in_abook": False,
    }), TASK_INFO)
    print(f"  score={r['score']}, passed={r['passed']}")
    ok = not r['passed'] and r['score'] == 0
    print(f"  {'PASS' if ok else 'FAIL'}: do-nothing score should be 0")
    tests_passed += int(ok)

    # Test 2: Wrong target (created folders but moved 0 emails)
    print("\n" + "=" * 60)
    print("TEST 2: Folders created but no emails moved")
    r = verify_legal_case_triage([], make_env({
        "task_start": 1700000000, "inbox_baseline": 12, "current_inbox_count": 12,
        "cases_sbd_exists": True,
        "harrison_folder": "Harrison_Mercer", "harrison_email_count": 0,
        "datavault_folder": "DataVault_IP", "datavault_email_count": 0,
        "chen_folder": "Chen_Estate", "chen_email_count": 0,
        "court_notices_exists": False, "court_filter_exists": False, "court_filter_name": "",
        "marcus_webb_in_abook": False, "marcus_webb_email_in_abook": False,
    }), TASK_INFO)
    print(f"  score={r['score']}, passed={r['passed']}")
    ok = not r['passed'] and r['score'] <= 10
    print(f"  {'PASS' if ok else 'FAIL'}: empty folders guard should score ≤10 and not pass")
    tests_passed += int(ok)

    # Test 3: Partial completion (only Harrison done, nothing else)
    print("\n" + "=" * 60)
    print("TEST 3: Partial completion (Harrison only)")
    r = verify_legal_case_triage([], make_env({
        "task_start": 1700000000, "inbox_baseline": 12, "current_inbox_count": 7,
        "cases_sbd_exists": True,
        "harrison_folder": "Harrison_Mercer", "harrison_email_count": 5,
        "datavault_folder": "", "datavault_email_count": 0,
        "chen_folder": "", "chen_email_count": 0,
        "court_notices_exists": False, "court_filter_exists": False, "court_filter_name": "",
        "marcus_webb_in_abook": False, "marcus_webb_email_in_abook": False,
    }), TASK_INFO)
    print(f"  score={r['score']}, passed={r['passed']}")
    ok = not r['passed'] and 0 < r['score'] < PASS_THRESHOLD
    print(f"  {'PASS' if ok else 'FAIL'}: partial completion should not pass (score={r['score']})")
    tests_passed += int(ok)

    # Test 4: Full completion
    print("\n" + "=" * 60)
    print("TEST 4: Full completion")
    r = verify_legal_case_triage([], make_env({
        "task_start": 1700000000, "inbox_baseline": 12, "current_inbox_count": 0,
        "cases_sbd_exists": True,
        "harrison_folder": "Harrison_Mercer", "harrison_email_count": 5,
        "datavault_folder": "DataVault_IP", "datavault_email_count": 4,
        "chen_folder": "Chen_Estate", "chen_email_count": 3,
        "court_notices_exists": True, "court_filter_exists": True, "court_filter_name": "Court Notices",
        "marcus_webb_in_abook": True, "marcus_webb_email_in_abook": True,
    }), TASK_INFO)
    print(f"  score={r['score']}, passed={r['passed']}")
    ok = r['passed'] and r['score'] >= PASS_THRESHOLD
    print(f"  {'PASS' if ok else 'FAIL'}: full completion should pass with score≥{PASS_THRESHOLD}")
    tests_passed += int(ok)

    print("\n" + "=" * 60)
    print(f"RESULTS: {tests_passed}/{total_tests} tests passed")
    sys.exit(0 if tests_passed == total_tests else 1)
