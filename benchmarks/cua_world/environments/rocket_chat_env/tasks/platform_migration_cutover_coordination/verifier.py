#!/usr/bin/env python3
"""Verifier for platform_migration_cutover_coordination task.

Occupation: Computer and Information Systems Manager / Migration Lead
Industry: Cloud Infrastructure / DevOps

Scenario: Migration Lead must coordinate a live platform cutover from on-prem
to cloud across 5 teams by reading their readiness updates, creating a war room,
posting a consolidated runbook and go/no-go tracker, triaging monitoring alerts,
escalating to the conditional team lead, briefing the VP, and announcing cutover.

Scoring (100 points, pass >= 60):
  C1  (8pts): War room channel exists and is PRIVATE
  C2  (5pts): War room topic contains project name and cutover window
  C3 (10pts): 7 required members invited to war room
  C4 (15pts): Runbook posted with correct staged migration order
  C5  (5pts): Runbook message is pinned
  C6 (10pts): Go/no-go tracker posted with CONDITIONAL for networking
  C7  (7pts): Thread reply on LB 502 alert
  C8  (8pts): Thread reply on backup failure alert with triage
  C9  (8pts): DM to network.lead about TLS/cert/ETA
  C10 (7pts): DM to vp.engineering with executive status summary
  C11 (7pts): DM to at least one other responder (db.lead or sre.oncall)
  C12 (5pts): Announcement in #engineering-announcements about cutover
  C13 (5pts): Runbook includes rollback triggers
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/platform_migration_cutover_coordination_result.json"


SEEDED_MSG_PREFIXES = [
    "[vp.engineering]:", "[product.owner]:",  # engineering-announcements seeds
    "[sre.oncall]: [ALERT]",                 # ops-alerts seeds
]


def _is_seeded(msg_text):
    """Check if a message was seeded during setup (not agent-authored)."""
    return any(msg_text.startswith(pfx) for pfx in SEEDED_MSG_PREFIXES)


def _collect_all_admin_text(result):
    """Gather all admin-authored text for keyword analysis, excluding seeded messages."""
    texts = []
    wr = result.get("war_room", {})
    for m in wr.get("messages", []):
        if m.get("u") != "system":
            texts.append((m.get("msg") or "").lower())
    for m in wr.get("pinned_messages", []):
        texts.append((m.get("msg") or "").lower())
    for thread_msgs in result.get("alert_threads", {}).values():
        for m in thread_msgs:
            if m.get("u") == "admin":
                texts.append((m.get("msg") or "").lower())
    for dm_msgs in result.get("direct_messages", {}).values():
        for m in dm_msgs:
            texts.append((m.get("msg") or "").lower())
    for m in result.get("engineering_announcements", {}).get("admin_messages", []):
        raw = m.get("msg") or ""
        if not _is_seeded(raw):
            texts.append(raw.lower())
    for m in result.get("ops_alerts", {}).get("admin_messages", []):
        raw = m.get("msg") or ""
        if not _is_seeded(raw):
            texts.append(raw.lower())
    return texts


def verify_platform_migration_cutover_coordination(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env(RESULT_PATH, tmp.name)
        with open(tmp.name, "r") as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    if result.get("error"):
        return {"passed": False, "score": 0, "feedback": f"Export error: {result['error']}"}

    score = 0
    feedback = []

    wr = result.get("war_room", {})
    wr_messages = wr.get("messages", [])
    wr_members = [m.lower() for m in wr.get("members", [])]
    wr_pinned = wr.get("pinned_messages", [])
    alert_threads = result.get("alert_threads", {})
    dms = result.get("direct_messages", {})
    ann_msgs = result.get("engineering_announcements", {}).get("admin_messages", [])

    all_texts = _collect_all_admin_text(result)
    combined = " ".join(all_texts)

    # Do-nothing gate
    wr_msg_count = len([m for m in wr_messages if m.get("u") != "system"])
    thread_count = sum(len(v) for v in alert_threads.values())
    dm_count = sum(len(v) for v in dms.values())
    ann_count = len(ann_msgs)

    if wr_msg_count == 0 and thread_count == 0 and dm_count == 0 and ann_count == 0:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No coordination activity detected. Agent likely did nothing.",
        }

    # --- C1 (8pts): War room exists and is PRIVATE ---
    c1 = 0
    if wr.get("exists"):
        if wr.get("type") == "private":
            c1 = 8
            feedback.append("C1: +8 War room channel exists and is PRIVATE")
        else:
            c1 = 4
            feedback.append("C1: +4 War room channel exists but is PUBLIC (should be private)")
    else:
        feedback.append("C1: +0 War room channel not found")
    score += c1

    # --- C2 (5pts): War room topic contains project name + cutover window ---
    c2 = 0
    topic = (wr.get("topic") or "").lower()
    has_atlas = "atlas" in topic
    has_cutover = "cutover" in topic
    has_date = "2026-03-18" in topic or "01:00" in topic
    if has_atlas and has_cutover and has_date:
        c2 = 5
    elif has_atlas and (has_cutover or has_date):
        c2 = 3
    elif has_atlas or has_cutover:
        c2 = 1
    feedback.append(f"C2: +{c2} Topic check (atlas={has_atlas}, cutover={has_cutover}, date={has_date})")
    score += c2

    # --- C3 (10pts): 7 required members invited ---
    c3 = 0
    required_members = ["db.lead", "network.lead", "backend.lead", "frontend.lead", "qa.lead", "sre.oncall", "cloud.architect"]
    present = [m for m in required_members if m in wr_members]
    c3 = min(10, len(present) * 10 // 7)
    feedback.append(f"C3: +{c3} Members invited ({len(present)}/7): {present}")
    score += c3

    # --- C4 (15pts): Runbook with correct staged order ---
    c4 = 0
    runbook_kw_sets = {
        "gateway_restart": ["gateway", "tls 1.3", "tls", "restart"],
        "database": ["database", "db", "mongo", "migration", "replica"],
        "pps_config": ["pps", "payment processing", "config", "connection string"],
        "backend": ["backend", "microservice", "cloud routing", "feature flag"],
        "frontend": ["frontend", "cdn", "banner", "maintenance", "dns switch"],
    }
    wr_admin_texts = [
        (m.get("msg") or "").lower()
        for m in wr_messages
        if m.get("u") == "admin"
    ]
    all_wr_admin = " ".join(wr_admin_texts)

    stages_found = 0
    for stage, kws in runbook_kw_sets.items():
        if any(kw in all_wr_admin for kw in kws):
            stages_found += 1

    if stages_found >= 4:
        c4 = 15
    elif stages_found >= 3:
        c4 = 10
    elif stages_found >= 2:
        c4 = 6
    elif stages_found >= 1:
        c4 = 3
    feedback.append(f"C4: +{c4} Runbook stages found ({stages_found}/5)")
    score += c4

    # --- C5 (5pts): Runbook pinned ---
    c5 = 0
    if len(wr_pinned) > 0:
        c5 = 5
        feedback.append(f"C5: +5 Pinned message(s) found ({len(wr_pinned)})")
    else:
        # Check if any message has pinned=true in history
        pinned_in_history = [m for m in wr_messages if m.get("pinned")]
        if pinned_in_history:
            c5 = 5
            feedback.append(f"C5: +5 Pinned message found in history ({len(pinned_in_history)})")
        else:
            feedback.append("C5: +0 No pinned messages in war room")
    score += c5

    # --- C6 (10pts): Go/no-go tracker with CONDITIONAL ---
    c6 = 0
    has_conditional = "conditional" in all_wr_admin
    has_network_ref = any(kw in all_wr_admin for kw in ["network", "tls", "gateway", "dns"])
    has_go = "go" in all_wr_admin
    team_statuses = sum(1 for kw in ["database", "backend", "frontend", "qa", "network"]
                        if kw in all_wr_admin)

    if has_conditional and has_network_ref and team_statuses >= 3:
        c6 = 10
    elif has_conditional and team_statuses >= 2:
        c6 = 7
    elif has_conditional or team_statuses >= 3:
        c6 = 4
    elif team_statuses >= 1:
        c6 = 2
    feedback.append(
        f"C6: +{c6} Go/no-go tracker (conditional={has_conditional}, "
        f"network_ref={has_network_ref}, team_statuses={team_statuses})"
    )
    score += c6

    # --- C7 (7pts): Thread reply on LB 502 alert ---
    c7 = 0
    alert1_replies = alert_threads.get("lb_502_alert", [])
    admin_alert1 = [m for m in alert1_replies if m.get("u") == "admin"]
    if len(admin_alert1) > 0:
        c7 = 7
        feedback.append(f"C7: +7 Thread reply on LB 502 alert ({len(admin_alert1)} replies)")
    else:
        feedback.append("C7: +0 No thread reply on LB 502 alert")
    score += c7

    # --- C8 (8pts): Thread reply on backup failure alert ---
    c8 = 0
    alert2_replies = alert_threads.get("backup_failure_alert", [])
    admin_alert2 = [m for m in alert2_replies if m.get("u") == "admin"]
    if len(admin_alert2) > 0:
        reply_text = " ".join((m.get("msg") or "").lower() for m in admin_alert2)
        has_triage = any(kw in reply_text for kw in [
            "backup", "disk", "rollback", "resolve", "fix", "critical",
            "quota", "san", "prerequisite", "before cutover"
        ])
        if has_triage:
            c8 = 8
            feedback.append(f"C8: +8 Thread reply on backup alert with triage content")
        else:
            c8 = 5
            feedback.append(f"C8: +5 Thread reply on backup alert but weak triage content")
    else:
        feedback.append("C8: +0 No thread reply on backup failure alert")
    score += c8

    # --- C9 (8pts): DM to network.lead about TLS/cert/ETA ---
    c9 = 0
    net_dm = dms.get("network_lead", [])
    if len(net_dm) > 0:
        dm_text = " ".join((m.get("msg") or "").lower() for m in net_dm)
        has_cert_ref = any(kw in dm_text for kw in ["tls", "cert", "gateway", "conditional", "eta", "status", "1.3"])
        if has_cert_ref:
            c9 = 8
            feedback.append("C9: +8 DM to network.lead with relevant TLS/cert/ETA content")
        else:
            c9 = 5
            feedback.append("C9: +5 DM to network.lead but without specific TLS/cert reference")
    else:
        feedback.append("C9: +0 No DM to network.lead")
    score += c9

    # --- C10 (7pts): DM to vp.engineering with executive summary ---
    c10 = 0
    vp_dm = dms.get("vp_engineering", [])
    if len(vp_dm) > 0:
        dm_text = " ".join((m.get("msg") or "").lower() for m in vp_dm)
        has_status = any(kw in dm_text for kw in [
            "atlas", "cutover", "hold", "conditional", "go", "status",
            "migration", "ready", "blocker", "summary"
        ])
        if has_status:
            c10 = 7
            feedback.append("C10: +7 DM to vp.engineering with executive status content")
        else:
            c10 = 4
            feedback.append("C10: +4 DM to vp.engineering but weak status content")
    else:
        feedback.append("C10: +0 No DM to vp.engineering")
    score += c10

    # --- C11 (7pts): DM to at least one other responder ---
    c11 = 0
    db_dm = dms.get("db_lead", [])
    sre_dm = dms.get("sre_oncall", [])
    other_dm_count = (1 if len(db_dm) > 0 else 0) + (1 if len(sre_dm) > 0 else 0)
    if other_dm_count >= 2:
        c11 = 7
        feedback.append("C11: +7 DM to both db.lead and sre.oncall")
    elif other_dm_count == 1:
        c11 = 4
        feedback.append("C11: +4 DM to one of db.lead/sre.oncall")
    else:
        feedback.append("C11: +0 No DM to db.lead or sre.oncall")
    score += c11

    # --- C12 (5pts): Announcement in #engineering-announcements ---
    c12 = 0
    # Skip seeded messages (vp.engineering timeline update and product.owner comms plan)
    seeded_prefixes = ["[vp.engineering]:", "[product.owner]:"]
    agent_ann_msgs = [
        m for m in ann_msgs
        if not any((m.get("msg") or "").startswith(pfx) for pfx in seeded_prefixes)
    ]
    if len(agent_ann_msgs) > 0:
        ann_text = " ".join((m.get("msg") or "").lower() for m in agent_ann_msgs)
        has_cutover_ref = any(kw in ann_text for kw in ["atlas", "cutover", "migration", "war-room", "war room", "maintenance"])
        if has_cutover_ref:
            c12 = 5
            feedback.append("C12: +5 Announcement posted with cutover reference")
        else:
            c12 = 3
            feedback.append("C12: +3 Announcement posted but without cutover reference")
    else:
        feedback.append("C12: +0 No announcement in #engineering-announcements")
    score += c12

    # --- C13 (5pts): Runbook includes rollback triggers ---
    c13 = 0
    rollback_kw = [
        "rollback", "roll back", "error rate", "latency", "p99",
        "failure", "revert", "abort", "threshold", "trigger"
    ]
    rollback_hits = [kw for kw in rollback_kw if kw in all_wr_admin]
    if len(rollback_hits) >= 3:
        c13 = 5
    elif len(rollback_hits) >= 1:
        c13 = 3
    feedback.append(f"C13: +{c13} Rollback triggers in runbook ({len(rollback_hits)} hits: {rollback_hits[:5]})")
    score += c13

    passed = score >= 60
    summary = f"Score: {score}/100 (pass >= 60)\n" + "\n".join(feedback)

    return {
        "passed": passed,
        "score": score,
        "feedback": summary,
    }
