#!/usr/bin/env python3
"""Verifier for stale_pipeline_cleanup task.

Scores across 5 criteria:
  C1 (25pts): Stale deals moved to Closed Lost (ExxonMobil, J&J)
  C2 (25pts): Probability corrected for NVIDIA, AT&T, Goldman Sachs
  C3 (20pts): Future Closed Won date fixed (Apple ML opp)
  C4 (15pts): GE Aviation probability corrected (100 -> 25 for Needs Analysis)
  C5 (15pts): Legitimate opps unchanged (gate)
"""

# Standard stage->probability mapping for SuiteCRM
STAGE_PROB = {
    "Prospecting": 10,
    "Qualification": 20,
    "Needs Analysis": 25,
    "Value Proposition": 30,
    "Id. Decision Makers": 40,
    "Perception Analysis": 50,
    "Proposal/Price Quote": 65,
    "Negotiation/Review": 80,
    "Closed Won": 100,
    "Closed Lost": 0,
}


def _db(exec_capture, sql):
    escaped = sql.replace('"', '\\"').replace('$', '\\$').replace('`', '\\`')
    cmd = f'docker exec suitecrm-db mysql -u suitecrm -psuitecrm_pass suitecrm -N -e "{escaped}"'
    return (exec_capture(cmd) or "").strip()


def _read(exec_capture, path):
    return (exec_capture(f"cat {path} 2>/dev/null") or "").strip()


def verify_stale_pipeline_cleanup(traj, env_info, task_info):
    exec_capture = env_info.get("exec_capture")
    if not exec_capture:
        return {"passed": False, "score": 0, "feedback": "exec_capture unavailable"}

    feedback = []
    subscores = {}
    total = 0.0
    changes_made = False

    # Load saved IDs
    exxon_id = _read(exec_capture, "/tmp/spc_exxon_id.txt")
    jnj_id = _read(exec_capture, "/tmp/spc_jnj_id.txt")
    nvidia_id = _read(exec_capture, "/tmp/spc_nvidia_id.txt")
    att_id = _read(exec_capture, "/tmp/spc_att_id.txt")
    gs_id = _read(exec_capture, "/tmp/spc_gs_id.txt")
    future_won_id = _read(exec_capture, "/tmp/spc_future_won_id.txt")
    wrong_prob_id = _read(exec_capture, "/tmp/spc_wrong_prob_id.txt")

    # ---- C1: Stale deals moved to Closed Lost (25 pts) ----
    c1 = 0
    for label, oid in [("ExxonMobil", exxon_id), ("J&J", jnj_id)]:
        row = _db(exec_capture, f"SELECT sales_stage, probability FROM opportunities WHERE id='{oid}' AND deleted=0")
        parts = row.split("\t") if row else []
        stage = parts[0].strip() if len(parts) > 0 else ""
        prob = parts[1].strip() if len(parts) > 1 else ""
        if stage == "Closed Lost":
            c1 += 12.5
            changes_made = True
            feedback.append(f"  {label}: moved to Closed Lost")
        else:
            feedback.append(f"  {label}: still in '{stage}' (should be Closed Lost)")
    subscores["c1_stale_deals"] = round(c1, 2)
    total += c1
    feedback.insert(len(feedback) - 2, f"C1 Stale deals to Closed Lost ({c1:.1f}/25):")

    # ---- C2: Probability corrected for 3 opps (25 pts) ----
    c2 = 0
    prob_checks = [
        ("NVIDIA", nvidia_id, "Proposal/Price Quote", 65),
        ("AT&T", att_id, "Value Proposition", 30),
        ("Goldman Sachs", gs_id, "Negotiation/Review", 80),
    ]
    for label, oid, expected_stage, expected_prob in prob_checks:
        row = _db(exec_capture, f"SELECT sales_stage, probability FROM opportunities WHERE id='{oid}' AND deleted=0")
        parts = row.split("\t") if row else []
        prob_val = int(float(parts[1].strip())) if len(parts) > 1 and parts[1].strip() else -1
        stage_val = parts[0].strip() if len(parts) > 0 else ""
        # Accept if probability matches the current stage (agent may have changed stage too)
        correct_prob = STAGE_PROB.get(stage_val, -999)
        if prob_val == expected_prob or prob_val == correct_prob:
            c2 += 25 / 3
            changes_made = True
        else:
            feedback.append(f"  {label}: prob={prob_val} (expected {expected_prob} for {expected_stage})")
    subscores["c2_probability_fix"] = round(c2, 2)
    total += c2
    feedback.append(f"C2 Probability corrections ({c2:.1f}/25)")

    # ---- C3: Future Closed Won date fixed (20 pts) ----
    row = _db(exec_capture, f"SELECT sales_stage, date_closed FROM opportunities WHERE id='{future_won_id}' AND deleted=0")
    parts = row.split("\t") if row else []
    stage = parts[0].strip() if len(parts) > 0 else ""
    close_date = parts[1].strip() if len(parts) > 1 else ""
    c3 = 0
    if stage == "Closed Won" and close_date and close_date < "2026-03-07":
        c3 = 20
        changes_made = True
        feedback.append(f"C3 Future Closed Won fixed: date={close_date} (20/20)")
    elif stage != "Closed Won":
        # Agent changed stage away from Closed Won - partial credit
        c3 = 10
        changes_made = True
        feedback.append(f"C3 Future Closed Won: stage changed to '{stage}' (10/20)")
    else:
        feedback.append(f"C3 Future Closed Won still has future date: {close_date} (0/20)")
    subscores["c3_future_won"] = c3
    total += c3

    # ---- C4: GE Aviation probability corrected (15 pts) ----
    row = _db(exec_capture, f"SELECT sales_stage, probability FROM opportunities WHERE id='{wrong_prob_id}' AND deleted=0")
    parts = row.split("\t") if row else []
    prob_val = int(float(parts[1].strip())) if len(parts) > 1 and parts[1].strip() else -1
    stage_val = parts[0].strip() if len(parts) > 0 else ""
    c4 = 0
    correct_for_stage = STAGE_PROB.get(stage_val, -999)
    if prob_val == 25 or prob_val == correct_for_stage:
        c4 = 15
        changes_made = True
        feedback.append(f"C4 GE Aviation prob corrected: {prob_val} for {stage_val} (15/15)")
    elif prob_val != 100:
        c4 = 5  # changed but not to correct value
        changes_made = True
        feedback.append(f"C4 GE Aviation prob changed to {prob_val} (expected 25) (5/15)")
    else:
        feedback.append(f"C4 GE Aviation prob still 100 for Needs Analysis (0/15)")
    subscores["c4_ge_probability"] = c4
    total += c4

    # ---- C5: Legitimate opps unchanged (15 pts, gate) ----
    # Check that Closed Won/Lost records weren't erroneously changed
    legit_closed = [
        ("Apple - Enterprise Data Platform License", "Closed Won"),
        ("Microsoft - Cloud Migration Services", "Closed Won"),
        ("Walmart - POS Integration Suite", "Closed Won"),
        ("Boeing - Supply Chain Analytics Platform", "Closed Won"),
        ("Meta - Content Moderation Tooling", "Closed Lost"),
        ("Amazon - Warehouse Robotics Interface", "Closed Lost"),
    ]
    legit_ok = 0
    for name, expected_stage in legit_closed:
        safe = name.replace("'", "\\'")
        row = _db(exec_capture, f"SELECT sales_stage FROM opportunities WHERE name='{safe}' AND deleted=0")
        if row.strip() == expected_stage:
            legit_ok += 1
    c5 = (legit_ok / len(legit_closed)) * 15
    if c5 < 15:
        total = min(total, 50)  # gate
        feedback.append(f"C5 Legitimate opps: {legit_ok}/{len(legit_closed)} unchanged - SCORE CAPPED ({c5:.1f}/15)")
    else:
        feedback.append(f"C5 Legitimate opps preserved ({c5:.1f}/15)")
    subscores["c5_legitimate_gate"] = round(c5, 2)
    total += c5

    # Do-nothing check
    if not changes_made:
        total = 0
        feedback.insert(0, "DO-NOTHING: No pipeline changes detected")

    score = min(round(total, 2), 100)
    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback),
        "subscores": subscores,
    }
