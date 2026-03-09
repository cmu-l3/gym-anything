#!/usr/bin/env python3
"""Verifier for account_dedup_consolidation task.

Scores across 5 criteria:
  C1 (20pts): Boeing duplicate accounts deleted
  C2 (20pts): GE duplicate accounts deleted
  C3 (20pts): Contacts properly reassigned to canonical accounts
  C4 (20pts): Opportunities and cases reassigned to canonical accounts
  C5 (20pts): Contamination account preserved + original accounts intact (gate)
"""


def _db(exec_capture, sql):
    escaped = sql.replace('"', '\\"').replace('$', '\\$').replace('`', '\\`')
    cmd = f'docker exec suitecrm-db mysql -u suitecrm -psuitecrm_pass suitecrm -N -e "{escaped}"'
    return (exec_capture(cmd) or "").strip()


def _read(exec_capture, path):
    return (exec_capture(f"cat {path} 2>/dev/null") or "").strip()


def verify_account_dedup_consolidation(traj, env_info, task_info):
    exec_capture = env_info.get("exec_capture")
    if not exec_capture:
        return {"passed": False, "score": 0, "feedback": "exec_capture unavailable"}

    feedback = []
    subscores = {}
    total = 0.0
    changes_made = False

    # Load baseline IDs
    boeing_canon = _read(exec_capture, "/tmp/adc_boeing_canonical_id.txt")
    ge_canon = _read(exec_capture, "/tmp/adc_ge_canonical_id.txt")
    dup_acct_ids = [x.strip() for x in _read(exec_capture, "/tmp/adc_dup_acct_ids.txt").splitlines() if x.strip()]
    dup_contact_ids = [x.strip() for x in _read(exec_capture, "/tmp/adc_dup_contact_ids.txt").splitlines() if x.strip()]
    dup_opp_ids = [x.strip() for x in _read(exec_capture, "/tmp/adc_dup_opp_ids.txt").splitlines() if x.strip()]
    dup_case_ids = [x.strip() for x in _read(exec_capture, "/tmp/adc_dup_case_ids.txt").splitlines() if x.strip()]
    contam_acct_id = _read(exec_capture, "/tmp/adc_contam_acct_id.txt")
    contam_contact_id = _read(exec_capture, "/tmp/adc_contam_contact_id.txt")

    # Map which dup accounts are Boeing vs GE (first 2 Boeing, next 2 GE)
    boeing_dup_ids = dup_acct_ids[:2] if len(dup_acct_ids) >= 2 else dup_acct_ids
    ge_dup_ids = dup_acct_ids[2:4] if len(dup_acct_ids) >= 4 else dup_acct_ids[2:]

    # ---- C1: Boeing duplicates deleted (20 pts) ----
    boeing_deleted = 0
    for did in boeing_dup_ids:
        cnt = _db(exec_capture, f"SELECT COUNT(*) FROM accounts WHERE id='{did}' AND deleted=0")
        if cnt == "0":
            boeing_deleted += 1
            changes_made = True
    c1 = (boeing_deleted / max(len(boeing_dup_ids), 1)) * 20
    subscores["c1_boeing_dedup"] = round(c1, 2)
    total += c1
    feedback.append(f"C1 Boeing dups deleted: {boeing_deleted}/{len(boeing_dup_ids)} ({c1:.1f}/20)")

    # ---- C2: GE duplicates deleted (20 pts) ----
    ge_deleted = 0
    for did in ge_dup_ids:
        cnt = _db(exec_capture, f"SELECT COUNT(*) FROM accounts WHERE id='{did}' AND deleted=0")
        if cnt == "0":
            ge_deleted += 1
            changes_made = True
    c2 = (ge_deleted / max(len(ge_dup_ids), 1)) * 20
    subscores["c2_ge_dedup"] = round(c2, 2)
    total += c2
    feedback.append(f"C2 GE dups deleted: {ge_deleted}/{len(ge_dup_ids)} ({c2:.1f}/20)")

    # ---- C3: Contacts reassigned to canonical accounts (20 pts) ----
    # 3 dup contacts: first 2 should be under Boeing canonical, 3rd under GE canonical
    contacts_ok = 0
    for i, cid in enumerate(dup_contact_ids):
        row = _db(exec_capture, f"SELECT account_id FROM contacts WHERE id='{cid}' AND deleted=0")
        acct = row.strip()
        if i < 2:  # Boeing contacts
            if acct == boeing_canon:
                contacts_ok += 1
                changes_made = True
        else:  # GE contact
            if acct == ge_canon:
                contacts_ok += 1
                changes_made = True
    c3 = (contacts_ok / max(len(dup_contact_ids), 1)) * 20
    subscores["c3_contacts_reassigned"] = round(c3, 2)
    total += c3
    feedback.append(f"C3 Contacts reassigned: {contacts_ok}/{len(dup_contact_ids)} ({c3:.1f}/20)")

    # ---- C4: Opportunities and cases reassigned (20 pts) ----
    records_ok = 0
    total_records = len(dup_opp_ids) + len(dup_case_ids)
    # First opp should be Boeing, second opp should be GE
    for i, oid in enumerate(dup_opp_ids):
        row = _db(exec_capture, f"SELECT account_id FROM opportunities WHERE id='{oid}' AND deleted=0")
        acct = row.strip()
        expected = boeing_canon if i == 0 else ge_canon
        if acct == expected:
            records_ok += 1
            changes_made = True
    # Case should be GE
    for cid in dup_case_ids:
        row = _db(exec_capture, f"SELECT account_id FROM cases WHERE id='{cid}' AND deleted=0")
        acct = row.strip()
        if acct == ge_canon:
            records_ok += 1
            changes_made = True
    c4 = (records_ok / max(total_records, 1)) * 20
    subscores["c4_records_reassigned"] = round(c4, 2)
    total += c4
    feedback.append(f"C4 Opps/cases reassigned: {records_ok}/{total_records} ({c4:.1f}/20)")

    # ---- C5: Contamination preserved + originals intact (20 pts, gate) ----
    c5 = 0
    # Check contamination account still exists
    contam_ok = _db(exec_capture, f"SELECT COUNT(*) FROM accounts WHERE id='{contam_acct_id}' AND deleted=0") == "1"
    # Check contamination contact still linked correctly
    contam_contact_ok = _db(exec_capture, f"SELECT account_id FROM contacts WHERE id='{contam_contact_id}' AND deleted=0").strip() == contam_acct_id
    # Check canonical accounts still exist
    boeing_ok = _db(exec_capture, f"SELECT COUNT(*) FROM accounts WHERE id='{boeing_canon}' AND deleted=0") == "1"
    ge_ok = _db(exec_capture, f"SELECT COUNT(*) FROM accounts WHERE id='{ge_canon}' AND deleted=0") == "1"
    # Check Johnson & Johnson not deleted (different from Johnson Controls)
    jnj_ok = _db(exec_capture, "SELECT COUNT(*) FROM accounts WHERE name='Johnson & Johnson' AND deleted=0") != "0"

    checks = [contam_ok, contam_contact_ok, boeing_ok, ge_ok, jnj_ok]
    c5 = (sum(checks) / len(checks)) * 20
    if not contam_ok:
        total = min(total, 50)  # gate
        feedback.append(f"C5 GATE: Johnson Controls wrongly deleted - SCORE CAPPED")
    subscores["c5_safety_gate"] = round(c5, 2)
    total += c5
    feedback.append(f"C5 Safety checks: {sum(checks)}/{len(checks)} ({c5:.1f}/20)")

    # Do-nothing check
    if not changes_made:
        total = 0
        feedback.insert(0, "DO-NOTHING: No account changes detected")

    score = min(round(total, 2), 100)
    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback),
        "subscores": subscores,
    }
