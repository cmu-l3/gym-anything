#!/usr/bin/env python3
"""Verifier for devops_postmortem_action_items task.

Occupation: Software Developer / Senior SRE
Industry: Technology / SaaS

Scenario: SRE must discover three untracked postmortems in team channels,
catalogue the action items with owners and deadlines, notify responsible
engineers, and establish a leadership-visible tracking mechanism.

Scoring (100 points, pass >= 60):
  C1 (10pts): A tracking mechanism created — new private channel OR substantive
               cataloguing messages posted in engineering-postmortems by admin
  C2 (15pts): Action items across multiple postmortems are referenced with
               owners assigned (must mention at least 3 of the named engineers)
  C3 (15pts): Deadlines or due dates specified for action items
               (keywords: deadline, due, by, eod, eow, sprint, date, week, day)
  C4 (15pts): Direct messages sent to at least 3 of the 4 primary action owners
               (sre.lead, backend.dev, platform.eng, frontend.dev) notifying them
  C5 (10pts): Thread replies on at least 2 of the 3 postmortem messages,
               confirming engagement with each incident's action items
  C6 (15pts): Leadership (ops.lead) notified — either DM or tracking channel invite
               or message mentioning leadership visibility
  C7 (10pts): At least one critical item (db failover or alert storm) explicitly
               flagged as high-priority or escalated
  C8 (10pts): Tracking channel members include relevant engineers
               OR at least 4 distinct owners mentioned in cataloguing messages
"""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/devops_postmortem_action_items_result.json"

PRIMARY_OWNERS = ["sre.lead", "backend.dev", "platform.eng", "frontend.dev"]
ALL_OWNERS = ["sre.lead", "backend.dev", "platform.eng", "frontend.dev",
              "ops.lead", "devops.eng", "dba.eng"]


def _all_admin_text(result):
    """Collect all text written by admin for scanning."""
    texts = []
    tc_msgs = result.get("tracking_channel", {}).get("messages", [])
    for m in tc_msgs:
        if m.get("u") != "system":
            texts.append((m.get("msg") or "").lower())
    for m in result.get("pm_channel_admin_messages", []):
        texts.append((m.get("msg") or "").lower())
    for dm_key in result.get("direct_messages", {}).values():
        for m in dm_key:
            texts.append((m.get("msg") or "").lower())
    for thread_msgs in result.get("postmortem_threads", {}).values():
        for m in thread_msgs:
            if m.get("u") == "admin":
                texts.append((m.get("msg") or "").lower())
    return texts


def verify_devops_postmortem_action_items(traj, env_info, task_info):
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

    tc = result.get("tracking_channel", {})
    tc_messages = tc.get("messages", [])
    tc_members = [m.lower() for m in tc.get("members", [])]
    pm_threads = result.get("postmortem_threads", {})
    dms = result.get("direct_messages", {})
    pm_admin_msgs = result.get("pm_channel_admin_messages", [])
    new_group_count = result.get("new_group_count", 0)

    all_texts = _all_admin_text(result)
    combined = " ".join(all_texts)

    # Do-nothing gate
    tc_msg_count = len([m for m in tc_messages if m.get("u") != "system"])
    thread_count = sum(len(v) for v in pm_threads.values())
    dm_count = sum(len(v) for v in dms.values())
    pm_admin_count = len(pm_admin_msgs)

    if tc_msg_count == 0 and thread_count == 0 and dm_count == 0 and pm_admin_count == 0:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No tracking channel, no thread replies, no DMs, no cataloguing messages. Agent likely did nothing.",
        }

    # --- C1 (10pts): Tracking mechanism established ---
    c1 = 0
    if tc.get("found"):
        c1 = 10
        feedback.append(f"C1: +10 Tracking channel created: '{tc.get('name', 'unknown')}'")
    elif pm_admin_count >= 2:
        c1 = 7
        feedback.append(f"C1: +7 Admin posted {pm_admin_count} cataloguing messages in engineering-postmortems (no dedicated channel)")
    elif pm_admin_count == 1 or tc_msg_count >= 1:
        c1 = 4
        feedback.append(f"C1: +4 Partial tracking: {pm_admin_count} PM admin msgs, {tc_msg_count} tracking channel msgs")
    else:
        feedback.append("C1: +0 No tracking mechanism found")
    score += c1

    # --- C2 (15pts): Owners referenced in cataloguing content ---
    c2 = 0
    owners_mentioned = [o for o in ALL_OWNERS if o.replace(".", r"\.") and o in combined]
    owners_mentioned = [o for o in ALL_OWNERS if o in combined]
    if len(owners_mentioned) >= 5:
        c2 = 15
    elif len(owners_mentioned) >= 3:
        c2 = 10
    elif len(owners_mentioned) >= 2:
        c2 = 6
    elif len(owners_mentioned) >= 1:
        c2 = 3
    feedback.append(f"C2: +{c2} Owners referenced in cataloguing ({len(owners_mentioned)}/7): {owners_mentioned}")
    score += c2

    # --- C3 (15pts): Deadlines specified ---
    c3 = 0
    deadline_kw = ["deadline", "due", " by ", "eod", "eow", "sprint", "this week", "next week",
                   "monday", "tuesday", "wednesday", "thursday", "friday",
                   "march", "april", "2026-", "asap", "urgent", "immediately"]
    deadline_hits = sum(1 for t in all_texts for kw in deadline_kw if kw in t)
    deadline_msgs = [t for t in all_texts if any(kw in t for kw in deadline_kw)]
    if deadline_hits >= 6 or len(deadline_msgs) >= 3:
        c3 = 15
    elif deadline_hits >= 3 or len(deadline_msgs) >= 2:
        c3 = 10
    elif deadline_hits >= 1 or len(deadline_msgs) >= 1:
        c3 = 6
    feedback.append(f"C3: +{c3} Deadline language detected ({deadline_hits} hits across {len(all_texts)} messages)")
    score += c3

    # --- C4 (15pts): DMs to primary action owners ---
    c4 = 0
    dm_sent_to = []
    if len(dms.get("sre_lead", [])) > 0:
        c4 += 4
        dm_sent_to.append("sre.lead")
    if len(dms.get("backend_dev", [])) > 0:
        c4 += 4
        dm_sent_to.append("backend.dev")
    if len(dms.get("platform_eng", [])) > 0:
        c4 += 4
        dm_sent_to.append("platform.eng")
    if len(dms.get("frontend_dev", [])) > 0:
        c4 += 3
        dm_sent_to.append("frontend.dev")
    c4 = min(c4, 15)
    feedback.append(f"C4: +{c4} DMs sent to primary owners: {dm_sent_to}")
    score += c4

    # --- C5 (10pts): Thread replies on postmortem messages (engagement with each incident) ---
    c5 = 0
    threads_replied = 0
    for key in ["incident_047", "incident_061", "incident_079"]:
        if len(pm_threads.get(key, [])) > 0:
            c5 += 3
            threads_replied += 1
    c5 = min(c5, 10) if threads_replied >= 2 else (c5 if threads_replied >= 1 else 0)
    if threads_replied >= 3:
        c5 = 10
    elif threads_replied >= 2:
        c5 = 7
    elif threads_replied == 1:
        c5 = 3
    thread_counts = {k: len(v) for k, v in pm_threads.items()}
    feedback.append(f"C5: +{c5} Thread replies on {threads_replied}/3 postmortem messages: {thread_counts}")
    score += c5

    # --- C6 (15pts): Leadership (ops.lead) notified ---
    c6 = 0
    ops_dm_count = len(dms.get("ops_lead", []))
    ops_in_tc = "ops.lead" in tc_members
    ops_mentioned_in_msgs = "ops.lead" in combined
    if ops_dm_count > 0 and ops_in_tc:
        c6 = 15
    elif ops_dm_count > 0:
        c6 = 10
    elif ops_in_tc:
        c6 = 8
    elif ops_mentioned_in_msgs:
        c6 = 4
    feedback.append(
        f"C6: +{c6} Leadership (ops.lead) notified "
        f"(DM: {ops_dm_count} msgs, in tracking channel: {ops_in_tc}, mentioned: {ops_mentioned_in_msgs})"
    )
    score += c6

    # --- C7 (10pts): Critical items flagged (db failover or alert storm) ---
    c7 = 0
    critical_kw = [
        "db-prod", "failover", "replication", "postgresql", "inc-2024-047",
        "alert storm", "847", "memory leak", "on-call burnout", "inc-2024-079",
        "critical", "p1", "priority 1", "high priority", "highest priority"
    ]
    critical_hits = [kw for kw in critical_kw if kw in combined]
    if len(critical_hits) >= 4:
        c7 = 10
    elif len(critical_hits) >= 2:
        c7 = 6
    elif len(critical_hits) >= 1:
        c7 = 3
    feedback.append(f"C7: +{c7} Critical items flagged ({len(critical_hits)} keywords matched: {critical_hits[:4]})")
    score += c7

    # --- C8 (10pts): Sufficient coverage — 4+ distinct owners in content or members in channel ---
    c8 = 0
    owners_in_channel = [o for o in ALL_OWNERS if o in tc_members]
    distinct_owners_mentioned = len(set(owners_mentioned))
    if len(owners_in_channel) >= 4 or distinct_owners_mentioned >= 5:
        c8 = 10
    elif len(owners_in_channel) >= 2 or distinct_owners_mentioned >= 3:
        c8 = 6
    elif len(owners_in_channel) >= 1 or distinct_owners_mentioned >= 2:
        c8 = 3
    feedback.append(
        f"C8: +{c8} Coverage: {len(owners_in_channel)} owners in tracking channel, "
        f"{distinct_owners_mentioned} distinct owners mentioned in messages"
    )
    score += c8

    passed = score >= 60
    summary = f"Score: {score}/100 (pass >= 60)\n" + "\n".join(feedback)

    return {
        "passed": passed,
        "score": score,
        "feedback": summary,
    }
