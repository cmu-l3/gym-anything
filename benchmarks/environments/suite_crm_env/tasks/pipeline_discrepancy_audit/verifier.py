#!/usr/bin/env python3
"""Verifier for pipeline_discrepancy_audit task.

Scores across 5 criteria:
  C1 (25pts): All 4 duplicate opportunities removed
  C2 (20pts): AT&T opportunity amount corrected to ~$2,100,000
  C3 (20pts): Tesla opportunity amount corrected to ~$3,800,000
  C4 (20pts): Contamination opportunity NOT deleted (wrong-target gate)
  C5 (15pts): All original legitimate opportunities still exist
"""


def _db(exec_capture, sql):
    escaped = sql.replace('"', '\\"').replace('$', '\\$').replace('`', '\\`')
    cmd = f'docker exec suitecrm-db mysql -u suitecrm -psuitecrm_pass suitecrm -N -e "{escaped}"'
    return (exec_capture(cmd) or "").strip()


def _read(exec_capture, path):
    return (exec_capture(f"cat {path} 2>/dev/null") or "").strip()


def verify_pipeline_discrepancy_audit(traj, env_info, task_info):
    exec_capture = env_info.get("exec_capture")
    if not exec_capture:
        return {"passed": False, "score": 0, "feedback": "exec_capture unavailable"}

    feedback = []
    subscores = {}
    total = 0.0

    # Load baseline IDs saved by setup
    dupe_ids = [x.strip() for x in _read(exec_capture, "/tmp/pda_dupe_ids.txt").splitlines() if x.strip()]
    legit_id = _read(exec_capture, "/tmp/pda_legit_id.txt")
    att_opp_id = _read(exec_capture, "/tmp/pda_att_opp_id.txt")
    tesla_opp_id = _read(exec_capture, "/tmp/pda_tesla_opp_id.txt")

    # ---- C1: Duplicate removal (25 pts) ----
    removed = 0
    for did in dupe_ids:
        cnt = _db(exec_capture, f"SELECT COUNT(*) FROM opportunities WHERE id='{did}' AND deleted=0")
        if cnt == "0":
            removed += 1
    c1 = (removed / max(len(dupe_ids), 1)) * 25
    subscores["c1_duplicate_removal"] = round(c1, 2)
    total += c1
    feedback.append(f"C1 Duplicates removed: {removed}/{len(dupe_ids)} ({c1:.1f}/25)")

    # ---- C2: AT&T amount corrected to ~$2,100,000 (20 pts) ----
    att_raw = _db(exec_capture, f"SELECT amount FROM opportunities WHERE id='{att_opp_id}' AND deleted=0")
    try:
        att_amt = float(att_raw.replace(",", ""))
    except (ValueError, AttributeError):
        att_amt = -1
    if abs(att_amt - 2100000) <= 100000:
        c2 = 20
    elif abs(att_amt - 4200000) <= 100000:
        c2 = 0  # still inflated
    else:
        c2 = 5  # changed but wrong
    subscores["c2_att_amount"] = c2
    total += c2
    feedback.append(f"C2 AT&T amount: ${att_amt:,.0f} (expected ~$2.1M) ({c2}/20)")

    # ---- C3: Tesla amount corrected to ~$3,800,000 (20 pts) ----
    tesla_raw = _db(exec_capture, f"SELECT amount FROM opportunities WHERE id='{tesla_opp_id}' AND deleted=0")
    try:
        tesla_amt = float(tesla_raw.replace(",", ""))
    except (ValueError, AttributeError):
        tesla_amt = -1
    if abs(tesla_amt - 3800000) <= 100000:
        c3 = 20
    elif abs(tesla_amt - 5700000) <= 100000:
        c3 = 0
    else:
        c3 = 5
    subscores["c3_tesla_amount"] = c3
    total += c3
    feedback.append(f"C3 Tesla amount: ${tesla_amt:,.0f} (expected ~$3.8M) ({c3}/20)")

    # ---- C4: Contamination opportunity preserved (20 pts, gate) ----
    legit_cnt = _db(exec_capture, f"SELECT COUNT(*) FROM opportunities WHERE id='{legit_id}' AND deleted=0")
    if legit_cnt == "1":
        c4 = 20
        feedback.append("C4 Contamination opp preserved (20/20)")
    else:
        c4 = 0
        total = min(total, 40)  # score cap
        feedback.append("C4 Contamination opp wrongly deleted - SCORE CAPPED (0/20)")
    subscores["c4_contamination_gate"] = c4
    total += c4

    # ---- C5: Original legitimate opps still exist (15 pts) ----
    originals = [
        "Apple - Enterprise Data Platform License",
        "Microsoft - Cloud Migration Services",
        "Walmart - POS Integration Suite",
        "Boeing - Supply Chain Analytics Platform",
        "JPMorgan - Fraud Detection AI Module",
        "Cisco - Network Monitoring Expansion",
        "Goldman Sachs - Compliance Dashboard",
        "NVIDIA - GPU Cluster Management Platform",
        "AT&T - Customer Experience Analytics",
        "Tesla - Manufacturing Execution System",
        "Johnson & Johnson - Clinical Trial Mgmt",
        "ExxonMobil - IoT Sensor Analytics",
        "Meta - Content Moderation Tooling",
        "Amazon - Warehouse Robotics Interface",
    ]
    surviving = 0
    for name in originals:
        safe = name.replace("'", "\\'")
        cnt = _db(exec_capture, f"SELECT COUNT(*) FROM opportunities WHERE name='{safe}' AND deleted=0")
        if cnt != "0":
            surviving += 1
    c5 = (surviving / len(originals)) * 15
    subscores["c5_originals_preserved"] = round(c5, 2)
    total += c5
    feedback.append(f"C5 Originals preserved: {surviving}/{len(originals)} ({c5:.1f}/15)")

    # ---- Do-nothing check ----
    if removed == 0 and abs(att_amt - 4200000) <= 100000 and abs(tesla_amt - 5700000) <= 100000:
        total = 0
        feedback.insert(0, "DO-NOTHING: No pipeline changes detected")

    score = min(round(total, 2), 100)
    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback),
        "subscores": subscores,
    }
