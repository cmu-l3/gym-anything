#!/usr/bin/env python3
"""
Verifier for procurement_vendor_setup task.

A procurement director must organize a vendor correspondence inbox, route
RFQ and contract emails to appropriate subfolders, add a key vendor contact
to the address book, and create a routing filter for future vendor emails.

Scoring (100 points total):
- Vendors parent folder structure created: 10 pts
- Active_RFQs subfolder with ≥4 emails: 25 pts
- Contract_Review subfolder with ≥3 emails: 20 pts
- Sandra Chen (s.chen@globalsupplyco.com) added to address book: 20 pts
- @globalsupplyco.com filter created: 15 pts
- Bonus: inbox reduced by ≥7 (all task emails moved): 10 pts

Pass threshold: 60 points
Wrong-target guard: if Vendors.sbd exists but all subfolders have 0 emails → score capped
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/procurement_vendor_setup_result.json"
PASS_THRESHOLD = 60


def verify_procurement_vendor_setup(traj, env_info, task_info):
    """Verify procurement vendor setup task completion."""
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
    vendors_exists = result.get('vendors_sbd_exists', False)
    rfq_count = int(result.get('rfq_email_count', 0))
    contract_count = int(result.get('contract_email_count', 0))
    total_moved = rfq_count + contract_count

    if vendors_exists and total_moved == 0:
        return {
            "passed": False,
            "score": 5,
            "feedback": "GUARD: Vendors folder structure created but no emails moved — agent must route emails to subfolders"
        }

    # ================================================================
    # CRITERION 1: Vendors.sbd directory — 10 pts
    # ================================================================
    if vendors_exists:
        score += 10
        feedback_parts.append("Vendors folder structure created (10/10)")
    else:
        feedback_parts.append("Vendors folder structure NOT created (0/10)")

    # ================================================================
    # CRITERION 2: Active_RFQs subfolder with ≥4 emails — 25 pts
    # ================================================================
    rfq_folder = result.get('rfq_folder', '')
    if rfq_folder and rfq_count >= 4:
        score += 25
        feedback_parts.append(f"Active_RFQs subfolder '{rfq_folder}' has {rfq_count} emails (25/25)")
    elif rfq_folder and rfq_count >= 2:
        score += 13
        feedback_parts.append(f"Active_RFQs subfolder '{rfq_folder}' has {rfq_count} emails — expected ≥4 (13/25)")
    elif rfq_folder and rfq_count >= 1:
        score += 6
        feedback_parts.append(f"Active_RFQs subfolder '{rfq_folder}' has {rfq_count} email (6/25)")
    elif rfq_folder:
        score += 3
        feedback_parts.append(f"Active_RFQs subfolder '{rfq_folder}' found but empty (3/25)")
    else:
        feedback_parts.append("Active_RFQs subfolder not found (0/25)")

    # ================================================================
    # CRITERION 3: Contract_Review subfolder with ≥3 emails — 20 pts
    # ================================================================
    contract_folder = result.get('contract_folder', '')
    if contract_folder and contract_count >= 3:
        score += 20
        feedback_parts.append(f"Contract_Review subfolder '{contract_folder}' has {contract_count} emails (20/20)")
    elif contract_folder and contract_count >= 2:
        score += 12
        feedback_parts.append(f"Contract_Review subfolder '{contract_folder}' has {contract_count} emails — expected ≥3 (12/20)")
    elif contract_folder and contract_count >= 1:
        score += 5
        feedback_parts.append(f"Contract_Review subfolder '{contract_folder}' has {contract_count} email (5/20)")
    elif contract_folder:
        score += 2
        feedback_parts.append(f"Contract_Review subfolder '{contract_folder}' found but empty (2/20)")
    else:
        feedback_parts.append("Contract_Review subfolder not found (0/20)")

    # ================================================================
    # CRITERION 4: Sandra Chen in address book — 20 pts
    # ================================================================
    sandra_in_abook = result.get('sandra_chen_in_abook', False)
    sandra_email_in_abook = result.get('sandra_chen_email_in_abook', False)
    if sandra_email_in_abook:
        score += 20
        feedback_parts.append("Sandra Chen (s.chen@globalsupplyco.com) added to address book (20/20)")
    elif sandra_in_abook:
        score += 12
        feedback_parts.append("Sandra Chen name found but email not confirmed (12/20)")
    else:
        feedback_parts.append("Sandra Chen not found in address book (0/20)")

    # ================================================================
    # CRITERION 5: @globalsupplyco.com filter created — 15 pts
    # ================================================================
    gsc_filter = result.get('gsc_filter_exists', False)
    if gsc_filter:
        score += 15
        feedback_parts.append("@globalsupplyco.com routing filter created (15/15)")
    else:
        feedback_parts.append("No @globalsupplyco.com routing filter found (0/15)")

    # ================================================================
    # SCORE CAP
    # ================================================================
    if total_moved == 0 and score >= PASS_THRESHOLD:
        score = PASS_THRESHOLD - 1
        feedback_parts.append(f"Score capped at {PASS_THRESHOLD - 1}: no emails routed to vendor subfolders")

    passed = score >= PASS_THRESHOLD

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts),
        "details": {
            "vendors_sbd_exists": vendors_exists,
            "rfq_folder": result.get('rfq_folder', ''),
            "rfq_count": rfq_count,
            "contract_folder": result.get('contract_folder', ''),
            "contract_count": contract_count,
            "sandra_chen_in_abook": sandra_in_abook,
            "gsc_filter_exists": gsc_filter,
            "total_emails_moved": total_moved,
        }
    }


if __name__ == "__main__":
    """Pipeline tests for procurement_vendor_setup verifier."""
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
    r = verify_procurement_vendor_setup([], make_env({
        "task_start": 1700000000, "inbox_baseline": 9, "current_inbox_count": 9,
        "vendors_sbd_exists": False,
        "rfq_folder": "", "rfq_email_count": 0,
        "contract_folder": "", "contract_email_count": 0,
        "gsc_filter_exists": False,
        "sandra_chen_in_abook": False, "sandra_chen_email_in_abook": False,
    }), TASK_INFO)
    print(f"  score={r['score']}, passed={r['passed']}")
    ok = not r['passed'] and r['score'] == 0
    print(f"  {'PASS' if ok else 'FAIL'}: do-nothing score should be 0")
    tests_passed += int(ok)

    print("\n" + "=" * 60)
    print("TEST 2: Folders created but no emails moved")
    r = verify_procurement_vendor_setup([], make_env({
        "task_start": 1700000000, "inbox_baseline": 9, "current_inbox_count": 9,
        "vendors_sbd_exists": True,
        "rfq_folder": "Active_RFQs", "rfq_email_count": 0,
        "contract_folder": "Contract_Review", "contract_email_count": 0,
        "gsc_filter_exists": False,
        "sandra_chen_in_abook": False, "sandra_chen_email_in_abook": False,
    }), TASK_INFO)
    print(f"  score={r['score']}, passed={r['passed']}")
    ok = not r['passed'] and r['score'] <= 10
    print(f"  {'PASS' if ok else 'FAIL'}: empty folders guard should score ≤10 and not pass")
    tests_passed += int(ok)

    print("\n" + "=" * 60)
    print("TEST 3: Partial completion (RFQs done, no contracts, no contact, no filter)")
    r = verify_procurement_vendor_setup([], make_env({
        "task_start": 1700000000, "inbox_baseline": 9, "current_inbox_count": 5,
        "vendors_sbd_exists": True,
        "rfq_folder": "Active_RFQs", "rfq_email_count": 4,
        "contract_folder": "", "contract_email_count": 0,
        "gsc_filter_exists": False,
        "sandra_chen_in_abook": False, "sandra_chen_email_in_abook": False,
    }), TASK_INFO)
    print(f"  score={r['score']}, passed={r['passed']}")
    ok = not r['passed'] and 0 < r['score'] < PASS_THRESHOLD
    print(f"  {'PASS' if ok else 'FAIL'}: partial completion should not pass (score={r['score']})")
    tests_passed += int(ok)

    print("\n" + "=" * 60)
    print("TEST 4: Full completion")
    r = verify_procurement_vendor_setup([], make_env({
        "task_start": 1700000000, "inbox_baseline": 9, "current_inbox_count": 2,
        "vendors_sbd_exists": True,
        "rfq_folder": "Active_RFQs", "rfq_email_count": 4,
        "contract_folder": "Contract_Review", "contract_email_count": 3,
        "gsc_filter_exists": True,
        "sandra_chen_in_abook": True, "sandra_chen_email_in_abook": True,
    }), TASK_INFO)
    print(f"  score={r['score']}, passed={r['passed']}")
    ok = r['passed'] and r['score'] >= PASS_THRESHOLD
    print(f"  {'PASS' if ok else 'FAIL'}: full completion should pass with score≥{PASS_THRESHOLD}")
    tests_passed += int(ok)

    print("\n" + "=" * 60)
    print(f"RESULTS: {tests_passed}/{total_tests} tests passed")
    sys.exit(0 if tests_passed == total_tests else 1)
