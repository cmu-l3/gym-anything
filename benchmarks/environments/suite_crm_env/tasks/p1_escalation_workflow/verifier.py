#!/usr/bin/env python3
"""Verifier for p1_escalation_workflow task.

Scores across 5 criteria:
  C1 (25pts): Underclassified cases upgraded to P1 (Walmart, Cisco)
  C2 (25pts): Stale P1 cases have '[ESCALATION REVIEW]' in description
  C3 (20pts): All P1 Open_New cases changed to Open_Assigned
  C4 (15pts): Contamination P2 case NOT upgraded (wrong-target gate)
  C5 (15pts): No legitimate case data corrupted
"""


def _db(exec_capture, sql):
    escaped = sql.replace('"', '\\"').replace('$', '\\$').replace('`', '\\`')
    cmd = f'docker exec suitecrm-db mysql -u suitecrm -psuitecrm_pass suitecrm -N -e "{escaped}"'
    return (exec_capture(cmd) or "").strip()


def _read(exec_capture, path):
    return (exec_capture(f"cat {path} 2>/dev/null") or "").strip()


def verify_p1_escalation_workflow(traj, env_info, task_info):
    exec_capture = env_info.get("exec_capture")
    if not exec_capture:
        return {"passed": False, "score": 0, "feedback": "exec_capture unavailable"}

    feedback = []
    subscores = {}
    total = 0.0
    changes_made = False

    # Load saved IDs
    stale_ids = [x.strip() for x in _read(exec_capture, "/tmp/p1e_stale_ids.txt").splitlines() if x.strip()]
    underclass_id = _read(exec_capture, "/tmp/p1e_underclass_id.txt")
    contam_id = _read(exec_capture, "/tmp/p1e_contam_id.txt")
    walmart_id = _read(exec_capture, "/tmp/p1e_walmart_id.txt")

    # ---- C1: Underclassified cases upgraded to P1 (25 pts) ----
    c1 = 0
    upgrade_checks = [("Walmart", walmart_id), ("Cisco", underclass_id)]
    for label, cid in upgrade_checks:
        if not cid:
            continue
        row = _db(exec_capture, f"SELECT priority FROM cases WHERE id='{cid}' AND deleted=0")
        if row.strip() in ("P1", "High"):
            c1 += 12.5
            changes_made = True
            feedback.append(f"  {label}: upgraded to P1")
        else:
            feedback.append(f"  {label}: still {row.strip()} (should be P1)")
    subscores["c1_priority_upgrade"] = round(c1, 2)
    total += c1
    feedback.insert(0, f"C1 Priority upgrades ({c1:.1f}/25):")

    # ---- C2: Stale P1 cases have '[ESCALATION REVIEW]' note (25 pts) ----
    c2 = 0
    escalated = 0
    for sid in stale_ids:
        desc = _db(exec_capture, f"SELECT description FROM cases WHERE id='{sid}' AND deleted=0")
        if "[ESCALATION REVIEW]" in desc.upper() or "[ESCALATION REVIEW]" in desc:
            escalated += 1
            changes_made = True
    if stale_ids:
        c2 = (escalated / len(stale_ids)) * 25
    subscores["c2_escalation_notes"] = round(c2, 2)
    total += c2
    feedback.append(f"C2 Escalation notes added: {escalated}/{len(stale_ids)} ({c2:.1f}/25)")

    # ---- C3: All P1 Open_New cases changed to Open_Assigned (20 pts) ----
    # Query all P1 cases and check none are Open_New
    remaining_open_new = _db(
        exec_capture,
        "SELECT COUNT(*) FROM cases WHERE priority='P1' AND status='Open_New' AND deleted=0"
    )
    try:
        still_new = int(remaining_open_new)
    except ValueError:
        still_new = -1

    # Count total P1 cases
    total_p1 = _db(exec_capture, "SELECT COUNT(*) FROM cases WHERE priority='P1' AND deleted=0")
    try:
        total_p1_count = int(total_p1)
    except ValueError:
        total_p1_count = 0

    if still_new == 0 and total_p1_count > 0:
        c3 = 20
        changes_made = True
        feedback.append(f"C3 All P1 cases assigned (0 still Open_New) (20/20)")
    elif still_new >= 0:
        # Partial credit based on how many were fixed
        all_p1_open_new_initial = [x.strip() for x in _read(exec_capture, "/tmp/p1e_all_p1_open_new.txt").splitlines() if x.strip()]
        initial_count = len(all_p1_open_new_initial)
        if initial_count > 0:
            fixed = max(initial_count - still_new, 0)
            c3 = (fixed / initial_count) * 20
            if fixed > 0:
                changes_made = True
        else:
            c3 = 0
        feedback.append(f"C3 P1 Open_New remaining: {still_new} ({c3:.1f}/20)")
    else:
        c3 = 0
        feedback.append(f"C3 Could not determine Open_New count (0/20)")
    subscores["c3_status_update"] = round(c3, 2)
    total += c3

    # ---- C4: Contamination case NOT upgraded (15 pts, gate) ----
    contam_priority = _db(exec_capture, f"SELECT priority FROM cases WHERE id='{contam_id}' AND deleted=0")
    if contam_priority.strip() in ("P2", "Medium"):
        c4 = 15
        feedback.append("C4 Contamination P2 case correctly not upgraded (15/15)")
    else:
        c4 = 0
        total = min(total, 50)  # score cap
        feedback.append(f"C4 Contamination case wrongly changed to {contam_priority.strip()} - SCORE CAPPED (0/15)")
    subscores["c4_contamination_gate"] = c4
    total += c4

    # ---- C5: No legitimate case data corrupted (15 pts) ----
    # Check that closed cases remain closed and P3 cases remain P3
    legit_checks = [
        ("Custom field request - Security Clearance", "Closed", "P3"),
        ("GDPR data export request", "Closed", "P2"),
        ("Training request - advanced reporting", "Closed", "P3"),
    ]
    legit_ok = 0
    for name, exp_status, exp_priority in legit_checks:
        safe = name.replace("'", "\\'")
        row = _db(exec_capture, f"SELECT status, priority FROM cases WHERE name='{safe}' AND deleted=0")
        parts = row.split("\t") if row else []
        status = parts[0].strip() if len(parts) > 0 else ""
        priority = parts[1].strip() if len(parts) > 1 else ""
        if status == exp_status and priority == exp_priority:
            legit_ok += 1
    c5 = (legit_ok / max(len(legit_checks), 1)) * 15
    subscores["c5_data_integrity"] = round(c5, 2)
    total += c5
    feedback.append(f"C5 Legitimate cases intact: {legit_ok}/{len(legit_checks)} ({c5:.1f}/15)")

    # Do-nothing check
    if not changes_made:
        total = 0
        feedback.insert(0, "DO-NOTHING: No case changes detected")

    score = min(round(total, 2), 100)
    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback),
        "subscores": subscores,
    }
