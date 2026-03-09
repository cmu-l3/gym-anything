#!/usr/bin/env python3
"""Verifier for cross_module_integrity_audit task.

Scores across 5 criteria:
  C1 (20pts): Apple Inc. type corrected to 'Customer' (has Closed Won deal)
  C2 (20pts): Meta and ExxonMobil types corrected to NOT 'Customer'
  C3 (20pts): Orphan contacts reassigned to correct accounts
  C4 (20pts): Misattributed contact (James Chen) returned to Apple
  C5 (20pts): Adobe 'Partner' and Salesforce 'Competitor' types NOT changed (gate)
"""

import re


def _is_uuid(s):
    """Check if string looks like a valid SuiteCRM UUID (36-char hex-and-hyphens)."""
    return bool(re.match(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
        s, re.IGNORECASE))


def _db(exec_capture, sql):
    escaped = sql.replace('"', '\\"').replace('$', '\\$').replace('`', '\\`')
    cmd = f'docker exec suitecrm-db mysql -u suitecrm -psuitecrm_pass suitecrm -N -e "{escaped}"'
    return (exec_capture(cmd) or "").strip()


def _read(exec_capture, path):
    return (exec_capture(f"cat {path} 2>/dev/null") or "").strip()


def verify_cross_module_integrity_audit(traj, env_info, task_info):
    exec_capture = env_info.get("exec_capture")
    if not exec_capture:
        return {"passed": False, "score": 0, "feedback": "exec_capture unavailable"}

    feedback = []
    subscores = {}
    total = 0.0
    changes_made = False

    # Load saved IDs in a single SSH call to reduce roundtrips
    id_names = ["apple", "meta", "exxon", "adobe", "salesforce",
                "orphan1", "orphan2", "misattr", "msft", "alphabet", "amazon"]
    batch_cmd = "; ".join(f'echo "{n}:$(cat /tmp/cmi_{n}_id.txt 2>/dev/null)"' for n in id_names)
    batch_out = (exec_capture(batch_cmd) or "").strip()
    ids = {}
    for line in batch_out.splitlines():
        if ":" in line:
            key, val = line.split(":", 1)
            ids[key.strip()] = val.strip()
    apple_id = ids.get("apple", "")
    meta_id = ids.get("meta", "")
    exxon_id = ids.get("exxon", "")
    adobe_id = ids.get("adobe", "")
    salesforce_id = ids.get("salesforce", "")
    orphan1_id = ids.get("orphan1", "")
    orphan2_id = ids.get("orphan2", "")
    misattr_id = ids.get("misattr", "")
    msft_id = ids.get("msft", "")
    alphabet_id = ids.get("alphabet", "")
    amazon_id = ids.get("amazon", "")

    # Verify setup completed - all critical IDs must be present
    required_ids = [apple_id, meta_id, exxon_id, adobe_id, salesforce_id, orphan1_id, orphan2_id, misattr_id, msft_id]
    if not all(required_ids):
        missing = [n for n, v in [("apple", apple_id), ("meta", meta_id), ("exxon", exxon_id),
                                   ("adobe", adobe_id), ("salesforce", salesforce_id),
                                   ("orphan1", orphan1_id), ("orphan2", orphan2_id),
                                   ("misattr", misattr_id), ("msft", msft_id)] if not v]
        return {"passed": False, "score": 0,
                "feedback": f"Setup incomplete - missing IDs: {', '.join(missing)}"}

    # ---- Batch query: account types (C1, C2, C5) ----
    type_sql = (
        f"SELECT id, account_type FROM accounts "
        f"WHERE id IN ('{apple_id}','{meta_id}','{exxon_id}','{adobe_id}','{salesforce_id}') "
        f"AND deleted=0"
    )
    type_rows = _db(exec_capture, type_sql)
    acct_types = {}
    for row in type_rows.splitlines():
        parts = row.split("\t")
        if len(parts) == 2:
            acct_types[parts[0].strip()] = parts[1].strip()

    apple_type = acct_types.get(apple_id, "")
    meta_type = acct_types.get(meta_id, "")
    exxon_type = acct_types.get(exxon_id, "")
    adobe_type = acct_types.get(adobe_id, "")
    sf_type = acct_types.get(salesforce_id, "")

    # ---- Batch query: contact account_ids (C3, C4) ----
    contact_sql = (
        f"SELECT id, account_id FROM contacts "
        f"WHERE id IN ('{orphan1_id}','{orphan2_id}','{misattr_id}') "
        f"AND deleted=0"
    )
    contact_rows = _db(exec_capture, contact_sql)
    contact_accts = {}
    for row in contact_rows.splitlines():
        parts = row.split("\t")
        if len(parts) == 2:
            contact_accts[parts[0].strip()] = parts[1].strip()

    o1_acct = contact_accts.get(orphan1_id, "")
    o2_acct = contact_accts.get(orphan2_id, "")
    chen_acct = contact_accts.get(misattr_id, "")

    # ---- C1: Apple type corrected to Customer (20 pts) ----
    if apple_type == "Customer":
        c1 = 20
        changes_made = True
        feedback.append("C1 Apple type corrected to Customer (20/20)")
    elif apple_type != "Prospect":
        c1 = 5  # changed but not to Customer
        changes_made = True
        feedback.append(f"C1 Apple type changed to '{apple_type}' (expected Customer) (5/20)")
    else:
        c1 = 0
        feedback.append("C1 Apple type still Prospect (should be Customer) (0/20)")
    subscores["c1_apple_type"] = c1
    total += c1

    # ---- C2: Meta and ExxonMobil NOT Customer (20 pts) ----
    c2 = 0
    if meta_type != "Customer":
        c2 += 10
        changes_made = True
        feedback.append(f"  Meta type: '{meta_type}' (not Customer)")
    else:
        feedback.append(f"  Meta type still Customer (wrong)")

    if exxon_type != "Customer":
        c2 += 10
        changes_made = True
        feedback.append(f"  ExxonMobil type: '{exxon_type}' (not Customer)")
    else:
        feedback.append(f"  ExxonMobil type still Customer (wrong)")

    subscores["c2_type_corrections"] = c2
    total += c2
    feedback.insert(len(feedback) - 2, f"C2 Non-customer corrections ({c2}/20):")

    # ---- C3: Orphan contacts reassigned (20 pts) ----
    c3 = 0
    # Orphan 1 (Victor Huang, email @abc.xyz -> should be Alphabet Inc.)
    if o1_acct == alphabet_id:
        c3 += 10
        changes_made = True
        feedback.append("  Victor Huang -> Alphabet Inc.")
    elif o1_acct and o1_acct != "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee" and _is_uuid(o1_acct):
        c3 += 3  # reassigned but to wrong account
        changes_made = True
        feedback.append(f"  Victor Huang -> reassigned (not to Alphabet)")
    else:
        # Also accept if the contact was deleted (orphan cleanup)
        deleted_check = _db(exec_capture, f"SELECT COUNT(*) FROM contacts WHERE id='{orphan1_id}' AND deleted=0")
        if deleted_check == "0":
            c3 += 5  # deleted is acceptable but not ideal
            changes_made = True
            feedback.append("  Victor Huang -> deleted (acceptable)")
        else:
            feedback.append("  Victor Huang still orphaned")

    # Orphan 2 (Laura Fischer, email @amazon.com -> should be Amazon.com Inc.)
    if o2_acct == amazon_id:
        c3 += 10
        changes_made = True
        feedback.append("  Laura Fischer -> Amazon.com Inc.")
    elif o2_acct and _is_uuid(o2_acct):
        # Check if the contact's current account still exists
        acct_exists = _db(exec_capture, f"SELECT COUNT(*) FROM accounts WHERE id='{o2_acct}' AND deleted=0")
        if acct_exists == "0":
            # Still orphaned
            deleted_check = _db(exec_capture, f"SELECT COUNT(*) FROM contacts WHERE id='{orphan2_id}' AND deleted=0")
            if deleted_check == "0":
                c3 += 5
                changes_made = True
                feedback.append("  Laura Fischer -> deleted (acceptable)")
            else:
                feedback.append("  Laura Fischer still orphaned (account deleted)")
        else:
            c3 += 3
            changes_made = True
            feedback.append(f"  Laura Fischer -> reassigned (not to Amazon)")
    else:
        feedback.append("  Laura Fischer still orphaned")

    subscores["c3_orphan_contacts"] = c3
    total += c3
    feedback.insert(len(feedback) - 2, f"C3 Orphan contacts ({c3}/20):")

    # ---- C4: James Chen returned to Apple (20 pts) ----
    if chen_acct == apple_id:
        c4 = 20
        changes_made = True
        feedback.append("C4 James Chen reassigned to Apple Inc. (20/20)")
    elif chen_acct != msft_id and _is_uuid(chen_acct):
        c4 = 5  # moved somewhere but not Apple
        changes_made = True
        feedback.append(f"C4 James Chen moved but not to Apple (5/20)")
    else:
        c4 = 0
        feedback.append("C4 James Chen still at Microsoft (0/20)")
    subscores["c4_misattributed"] = c4
    total += c4

    # ---- C5: Adobe and Salesforce types preserved (20 pts, gate) ----
    c5 = 0
    if adobe_type == "Partner":
        c5 += 10
    else:
        feedback.append(f"  Adobe type changed from Partner to '{adobe_type}' (wrong)")
    if sf_type == "Competitor":
        c5 += 10
    else:
        feedback.append(f"  Salesforce type changed from Competitor to '{sf_type}' (wrong)")

    if c5 < 20:
        total = min(total, 50)  # score cap
        feedback.append(f"C5 GATE: Protected types altered - SCORE CAPPED ({c5}/20)")
    else:
        feedback.append(f"C5 Protected types preserved ({c5}/20)")
    subscores["c5_safety_gate"] = c5
    total += c5

    # Do-nothing check
    if not changes_made:
        total = 0
        feedback.insert(0, "DO-NOTHING: No data changes detected")

    score = min(round(total, 2), 100)
    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback),
        "subscores": subscores,
    }
