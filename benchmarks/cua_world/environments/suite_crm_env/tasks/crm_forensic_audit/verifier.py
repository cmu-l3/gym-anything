#!/usr/bin/env python3
"""Verifier for crm_forensic_audit task.

Scores across 6 criteria:
  C1 (20pts): Re-opened deals moved back to Closed Lost with 0% probability
  C2 (20pts): Inflated opportunity amounts corrected to description values
  C3 (15pts): Fabricated Closed Won deal deleted
  C4 (15pts): Misassigned contacts reassigned to correct accounts
  C5 (15pts): Contamination records preserved (GATE — score capped if violated)
  C6 (15pts): Legitimate records untouched
"""


def _db(exec_capture, sql):
    escaped = sql.replace('"', '\\"').replace('$', '\\$').replace('`', '\\`')
    cmd = f'docker exec suitecrm-db mysql -u suitecrm -psuitecrm_pass suitecrm -N -e "{escaped}"'
    return (exec_capture(cmd) or "").strip()


def _read(exec_capture, path):
    return (exec_capture(f"cat {path} 2>/dev/null") or "").strip()


def verify_crm_forensic_audit(traj, env_info, task_info):
    exec_capture = env_info.get("exec_capture")
    if not exec_capture:
        return {"passed": False, "score": 0, "feedback": "exec_capture unavailable"}

    feedback = []
    subscores = {}
    total = 0.0
    changes_made = False

    # Load saved IDs
    reopen1_id       = _read(exec_capture, "/tmp/cfa_reopen1_id.txt")
    reopen2_id       = _read(exec_capture, "/tmp/cfa_reopen2_id.txt")
    contam_r1_id     = _read(exec_capture, "/tmp/cfa_contam_r1_id.txt")
    inflate1_id      = _read(exec_capture, "/tmp/cfa_inflate1_id.txt")
    inflate2_id      = _read(exec_capture, "/tmp/cfa_inflate2_id.txt")
    fabricated_id    = _read(exec_capture, "/tmp/cfa_fabricated_id.txt")
    legit_cw1_id     = _read(exec_capture, "/tmp/cfa_legit_cw1_id.txt")
    legit_cw2_id     = _read(exec_capture, "/tmp/cfa_legit_cw2_id.txt")
    legit_active1_id = _read(exec_capture, "/tmp/cfa_legit_active1_id.txt")
    legit_active2_id = _read(exec_capture, "/tmp/cfa_legit_active2_id.txt")
    contact_fix1_id  = _read(exec_capture, "/tmp/cfa_contact_fix1_id.txt")
    contact_fix2_id  = _read(exec_capture, "/tmp/cfa_contact_fix2_id.txt")
    contact_fix3_id  = _read(exec_capture, "/tmp/cfa_contact_fix3_id.txt")
    contam_c1_id     = _read(exec_capture, "/tmp/cfa_contam_c1_id.txt")
    contam_c2_id     = _read(exec_capture, "/tmp/cfa_contam_c2_id.txt")
    quantum_id       = _read(exec_capture, "/tmp/cfa_quantum_id.txt")
    evergreen_id     = _read(exec_capture, "/tmp/cfa_evergreen_id.txt")
    pinnacle_id      = _read(exec_capture, "/tmp/cfa_pinnacle_id.txt")
    apple_id         = _read(exec_capture, "/tmp/cfa_apple_id.txt")

    # ---- C1: Re-opened deals reversed (20 pts) ----
    c1 = 0
    for label, rid in [("Radar Upgrade", reopen1_id), ("ML Pipeline", reopen2_id)]:
        if not rid:
            continue
        row = _db(exec_capture,
                  f"SELECT sales_stage, probability FROM opportunities WHERE id='{rid}' AND deleted=0")
        parts = row.split("\t") if row else []
        stage = parts[0].strip() if len(parts) > 0 else ""
        prob_str = parts[1].strip() if len(parts) > 1 else ""
        try:
            prob = float(prob_str)
        except (ValueError, TypeError):
            prob = -1

        if stage == "Closed Lost" and prob == 0:
            c1 += 10
            changes_made = True
            feedback.append(f"  {label}: Closed Lost, prob=0 (correct)")
        elif stage == "Closed Lost":
            c1 += 7
            changes_made = True
            feedback.append(f"  {label}: Closed Lost but prob={prob} (expected 0)")
        elif stage not in ("Prospecting", "Qualification"):
            c1 += 3
            changes_made = True
            feedback.append(f"  {label}: changed to '{stage}' (expected Closed Lost)")
        else:
            feedback.append(f"  {label}: still {stage} (should be Closed Lost)")
    subscores["c1_reopened_deals"] = round(c1, 2)
    total += c1
    feedback.insert(0, f"C1 Re-opened deals reversed ({c1:.1f}/20):")

    # ---- C2: Inflated amounts corrected (20 pts) ----
    c2 = 0
    amount_checks = [
        ("Predictive Maintenance", inflate1_id, 2100000, 4200000),
        ("Cybersecurity Hardening", inflate2_id, 2900000, 5800000),
    ]
    for label, oid, correct_amt, inflated_amt in amount_checks:
        if not oid:
            continue
        raw = _db(exec_capture,
                  f"SELECT amount FROM opportunities WHERE id='{oid}' AND deleted=0")
        try:
            amt = float(raw.replace(",", ""))
        except (ValueError, TypeError, AttributeError):
            amt = -1

        if abs(amt - correct_amt) <= 50000:
            c2 += 10
            changes_made = True
            feedback.append(f"  {label}: ${amt:,.0f} (correct)")
        elif abs(amt - inflated_amt) <= 50000:
            c2 += 0
            feedback.append(f"  {label}: ${amt:,.0f} (still inflated)")
        else:
            c2 += 3
            changes_made = True
            feedback.append(f"  {label}: ${amt:,.0f} (changed but wrong, expected ~${correct_amt:,.0f})")
    subscores["c2_amounts_corrected"] = round(c2, 2)
    total += c2
    feedback.append(f"C2 Amounts corrected ({c2:.1f}/20)")

    # ---- C3: Fabricated deal removed (15 pts) ----
    fab_exists = _db(exec_capture,
                     f"SELECT COUNT(*) FROM opportunities WHERE id='{fabricated_id}' AND deleted=0")
    if fab_exists == "0":
        c3 = 15
        changes_made = True
        feedback.append("C3 Fabricated deal deleted (15/15)")
    else:
        c3 = 0
        feedback.append("C3 Fabricated deal still exists (0/15)")
    subscores["c3_fabricated_removed"] = c3
    total += c3

    # ---- C4: Contacts reassigned (15 pts) ----
    # Note: SuiteCRM links contacts to accounts via accounts_contacts table, not contacts.account_id
    c4 = 0
    contact_checks = [
        ("Nikolai Volkov", contact_fix1_id, quantum_id, "Quantum Dynamics"),
        ("Elena Vasquez", contact_fix2_id, evergreen_id, "Evergreen Health"),
        ("Diana Morales", contact_fix3_id, apple_id, "Apple Inc."),
    ]
    for label, cid, target_acct_id, target_name in contact_checks:
        if not cid:
            continue
        acct = _db(exec_capture,
                   f"SELECT account_id FROM accounts_contacts WHERE contact_id='{cid}' AND deleted=0 LIMIT 1")
        if acct.strip() == target_acct_id:
            c4 += 5
            changes_made = True
            feedback.append(f"  {label} -> {target_name} (correct)")
        elif acct.strip() and acct.strip() != pinnacle_id and acct.strip() != quantum_id and acct.strip() != evergreen_id:
            # Moved somewhere unexpected but away from Turner's accounts
            c4 += 2
            changes_made = True
            feedback.append(f"  {label} -> wrong account (not {target_name})")
        else:
            feedback.append(f"  {label} still at wrong account")
    subscores["c4_contacts_reassigned"] = round(c4, 2)
    total += c4
    feedback.append(f"C4 Contacts reassigned ({c4:.1f}/15)")

    # ---- C5: Contamination preserved (15 pts, GATE) ----
    c5 = 0
    gate_violated = False

    # Rule 1 contamination: "Evergreen - Patient Data Analytics Suite" should still be Prospecting
    contam_r1_stage = _db(exec_capture,
                          f"SELECT sales_stage FROM opportunities WHERE id='{contam_r1_id}' AND deleted=0")
    if contam_r1_stage.strip() == "Prospecting":
        c5 += 3
        feedback.append("  Contamination opp (Patient Data Analytics): still Prospecting (correct)")
    else:
        gate_violated = True
        feedback.append(f"  Contamination opp (Patient Data Analytics): changed to '{contam_r1_stage.strip()}' (WRONG)")

    # Rule 3 contamination: legitimate Closed Won deals should still exist
    for label, cw_id in [("Secure Comms Platform", legit_cw1_id), ("Telehealth Infrastructure", legit_cw2_id)]:
        cnt = _db(exec_capture,
                  f"SELECT COUNT(*) FROM opportunities WHERE id='{cw_id}' AND deleted=0")
        if cnt == "1":
            c5 += 3
            feedback.append(f"  Legitimate CW ({label}): preserved (correct)")
        else:
            gate_violated = True
            feedback.append(f"  Legitimate CW ({label}): DELETED (WRONG)")

    # Rule 4 contamination: personal email contact should stay at Quantum
    contam_c1_acct = _db(exec_capture,
                         f"SELECT account_id FROM accounts_contacts WHERE contact_id='{contam_c1_id}' AND deleted=0 LIMIT 1")
    if contam_c1_acct.strip() == quantum_id:
        c5 += 3
        feedback.append("  Contamination contact (Nakamura): still at Quantum (correct)")
    else:
        gate_violated = True
        feedback.append(f"  Contamination contact (Nakamura): moved (WRONG)")

    # Rule 4 contamination: matching-domain contact should stay at Pinnacle
    contam_c2_acct = _db(exec_capture,
                         f"SELECT account_id FROM accounts_contacts WHERE contact_id='{contam_c2_id}' AND deleted=0 LIMIT 1")
    if contam_c2_acct.strip() == pinnacle_id:
        c5 += 3
        feedback.append("  Contamination contact (Mitchell): still at Pinnacle (correct)")
    else:
        gate_violated = True
        feedback.append(f"  Contamination contact (Mitchell): moved (WRONG)")

    if gate_violated:
        total = min(total, 40)
        feedback.append("C5 GATE VIOLATED: Contamination record(s) altered — SCORE CAPPED AT 40")
    else:
        feedback.append(f"C5 All contamination preserved ({c5}/15)")

    subscores["c5_contamination_gate"] = c5
    total += c5

    # ---- C6: Legitimate active records untouched (15 pts) ----
    c6 = 0
    legit_checks = [
        ("EHR Integration Phase 2", legit_active1_id, "Proposal/Price Quote", 2800000),
        ("Training Simulation Platform", legit_active2_id, "Negotiation/Review", 1900000),
    ]
    for label, oid, exp_stage, exp_amount in legit_checks:
        if not oid:
            continue
        row = _db(exec_capture,
                  f"SELECT sales_stage, amount FROM opportunities WHERE id='{oid}' AND deleted=0")
        parts = row.split("\t") if row else []
        stage = parts[0].strip() if len(parts) > 0 else ""
        try:
            amt = float(parts[1].strip().replace(",", "")) if len(parts) > 1 else -1
        except (ValueError, TypeError):
            amt = -1

        if stage == exp_stage and abs(amt - exp_amount) <= 10000:
            c6 += 7.5
            feedback.append(f"  {label}: unchanged (correct)")
        else:
            feedback.append(f"  {label}: MODIFIED (stage={stage}, amt=${amt:,.0f})")

    subscores["c6_legitimate_untouched"] = round(c6, 2)
    total += c6
    feedback.append(f"C6 Legitimate records intact ({c6:.1f}/15)")

    # ---- Do-nothing check ----
    if not changes_made:
        total = 0
        feedback.insert(0, "DO-NOTHING: No data changes detected — score zeroed")

    score = min(round(total, 2), 100)
    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback),
        "subscores": subscores,
    }
