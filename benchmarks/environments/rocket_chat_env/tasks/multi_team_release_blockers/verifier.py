#!/usr/bin/env python3
"""Verifier for multi_team_release_blockers task.

Occupation: Computer and Information Systems Manager / Engineering Manager
Industry: Software Development

Scenario: Engineering Manager must diagnose three disputed release blockers
across Backend, Security, and QA teams, make go/no-go decisions, assign
ownership and resolution deadlines, and update all stakeholders on the
revised release timeline for v4.0.

Scoring (100 points, pass >= 60):
  C1 (10pts): Created a dedicated coordination/decision channel OR made
               substantive decisions visible in the release channel
  C2 (15pts): All three blocker owners engaged (backend.lead, security.eng,
               qa.lead) via DM or channel with explicit direction
  C3 (15pts): Thread replies on at least 2 of 3 blocker messages showing
               active resolution coordination
  C4 (15pts): Go/no-go decision language present (approve, proceed, ship,
               hold, block, green light, escalate, decision)
  C5 (15pts): Resolution timelines assigned for at least 2 blockers
               (hours, days, by, deadline, ETA, today, tomorrow)
  C6 (10pts): VP/leadership (vp.engineering) notified with status update
  C7 (10pts): Sales/external stakeholders (sales.lead or product.manager)
               updated on revised timeline
  C8 (10pts): Each blocker explicitly acknowledged in admin messages (all 3 of:
               migration/db/schema, security/oauth/csrf, qa/e2e/test)
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/multi_team_release_blockers_result.json"

BLOCKER_OWNERS = ["backend.lead", "security.eng", "qa.lead"]
STAKEHOLDERS = ["vp.engineering", "product.manager", "sales.lead", "devops.lead"]


def _collect_all_admin_text(result):
    texts = []
    cc = result.get("coord_channel", {})
    for m in cc.get("messages", []):
        if m.get("u") != "system":
            texts.append((m.get("msg") or "").lower())
    for m in result.get("release_channel_admin_messages", []):
        texts.append((m.get("msg") or "").lower())
    for msgs in result.get("direct_messages", {}).values():
        for m in msgs:
            texts.append((m.get("msg") or "").lower())
    for thread_msgs in result.get("blocker_threads", {}).values():
        for m in thread_msgs:
            if m.get("u") == "admin":
                texts.append((m.get("msg") or "").lower())
    return texts


def verify_multi_team_release_blockers(traj, env_info, task_info):
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

    cc = result.get("coord_channel", {})
    cc_messages = cc.get("messages", [])
    cc_members = [m.lower() for m in cc.get("members", [])]
    threads = result.get("blocker_threads", {})
    dms = result.get("direct_messages", {})
    rc_admin = result.get("release_channel_admin_messages", [])

    all_texts = _collect_all_admin_text(result)
    combined = " ".join(all_texts)

    # Do-nothing gate
    cc_msg_count = len([m for m in cc_messages if m.get("u") != "system"])
    thread_count = sum(len(v) for v in threads.values())
    dm_count = sum(len(v) for v in dms.values())
    rc_admin_count = len(rc_admin)

    if cc_msg_count == 0 and thread_count == 0 and dm_count == 0 and rc_admin_count == 0:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No coordination activity detected. Agent likely did nothing.",
        }

    # --- C1 (10pts): Coordination/decision channel or substantive release channel activity ---
    c1 = 0
    if cc.get("found"):
        c1 = 10
        feedback.append(f"C1: +10 Coordination channel created: '{cc.get('name', 'unknown')}'")
    elif rc_admin_count >= 3:
        c1 = 7
        feedback.append(f"C1: +7 {rc_admin_count} admin messages in release-v4 channel (no dedicated channel)")
    elif rc_admin_count >= 1 or cc_msg_count >= 1:
        c1 = 4
        feedback.append(f"C1: +4 Partial activity: {rc_admin_count} release msgs, {cc_msg_count} coord msgs")
    else:
        feedback.append("C1: +0 No coordination found")
    score += c1

    # --- C2 (15pts): Blocker owners engaged ---
    c2 = 0
    dm_key_map = {
        "backend.lead": "backend_lead",
        "security.eng": "security_eng",
        "qa.lead": "qa_lead"
    }
    owners_dmd = [o for o, k in dm_key_map.items() if len(dms.get(k, [])) > 0]
    owners_in_channel = [o for o in BLOCKER_OWNERS if o in cc_members]
    owners_mentioned = [o for o in BLOCKER_OWNERS if o in combined]
    all_owners_engaged = set(owners_dmd + owners_in_channel + owners_mentioned)

    if len(all_owners_engaged) >= 3:
        c2 = 15
    elif len(all_owners_engaged) == 2:
        c2 = 10
    elif len(all_owners_engaged) == 1:
        c2 = 5
    feedback.append(
        f"C2: +{c2} Blocker owners engaged ({len(all_owners_engaged)}/3): "
        f"DM'd={owners_dmd}, in_channel={owners_in_channel}"
    )
    score += c2

    # --- C3 (15pts): Thread replies on blocker messages ---
    c3 = 0
    threads_replied = sum(1 for v in threads.values() if len(v) > 0)
    thread_counts = {k: len(v) for k, v in threads.items()}
    if threads_replied >= 3:
        c3 = 15
    elif threads_replied >= 2:
        c3 = 10
    elif threads_replied == 1:
        c3 = 5
    feedback.append(f"C3: +{c3} Thread replies on blocker messages ({threads_replied}/3): {thread_counts}")
    score += c3

    # --- C4 (15pts): Go/no-go decision language ---
    c4 = 0
    decision_kw = [
        "go", "no-go", "nogo", "approve", "approved", "proceed", "ship", "release",
        "hold", "block", "green light", "decision", "sign off", "sign-off",
        "acceptable", "not a blocker", "not blocking", "clear to ship", "unblocked"
    ]
    decision_hits = [kw for kw in decision_kw if kw in combined]
    if len(decision_hits) >= 5:
        c4 = 15
    elif len(decision_hits) >= 3:
        c4 = 10
    elif len(decision_hits) >= 1:
        c4 = 5
    feedback.append(f"C4: +{c4} Decision language ({len(decision_hits)} hits): {decision_hits[:5]}")
    score += c4

    # --- C5 (15pts): Resolution timelines assigned ---
    c5 = 0
    timeline_kw = [
        " hour", " day", " by ", "deadline", "eta", "today", "tomorrow",
        "morning", "eod", "end of", "next 24", "within", "asap", "immediately",
        "march", "2026-03", "this week", "by friday", "by monday"
    ]
    timeline_msg_count = sum(1 for t in all_texts if any(kw in t for kw in timeline_kw))
    timeline_hits = [kw for kw in timeline_kw if kw in combined]
    if timeline_msg_count >= 4 or len(timeline_hits) >= 5:
        c5 = 15
    elif timeline_msg_count >= 2 or len(timeline_hits) >= 3:
        c5 = 10
    elif timeline_msg_count >= 1 or len(timeline_hits) >= 1:
        c5 = 5
    feedback.append(f"C5: +{c5} Resolution timelines ({len(timeline_hits)} timeline kw, {timeline_msg_count} msgs with timeline)")
    score += c5

    # --- C6 (10pts): VP/leadership notified ---
    c6 = 0
    vp_dm_count = len(dms.get("vp_engineering", []))
    vp_in_channel = "vp.engineering" in cc_members
    vp_mentioned = "vp.engineering" in combined or "sandra" in combined
    if vp_dm_count > 0 and (vp_in_channel or vp_mentioned):
        c6 = 10
    elif vp_dm_count > 0:
        c6 = 8
    elif vp_in_channel:
        c6 = 6
    elif vp_mentioned:
        c6 = 3
    feedback.append(
        f"C6: +{c6} VP Engineering notified "
        f"(DMs: {vp_dm_count}, in channel: {vp_in_channel})"
    )
    score += c6

    # --- C7 (10pts): External stakeholders updated on timeline ---
    c7 = 0
    sales_dm_count = len(dms.get("sales_lead", []))
    product_dm_count = len(dms.get("product_manager", []))
    sales_in_channel = "sales.lead" in cc_members
    product_in_channel = "product.manager" in cc_members
    external_notified = (sales_dm_count + product_dm_count > 0) or sales_in_channel or product_in_channel
    if (sales_dm_count > 0 or sales_in_channel) and (product_dm_count > 0 or product_in_channel):
        c7 = 10
    elif sales_dm_count > 0 or sales_in_channel:
        c7 = 7
    elif product_dm_count > 0 or product_in_channel:
        c7 = 5
    elif external_notified:
        c7 = 3
    feedback.append(
        f"C7: +{c7} External stakeholders updated "
        f"(sales DMs: {sales_dm_count}, product DMs: {product_dm_count})"
    )
    score += c7

    # --- C8 (10pts): All 3 blockers explicitly acknowledged ---
    c8 = 0
    migration_kw = ["migration", "migrate", "schema", "db", "database", "047", "batch", "5m row"]
    security_kw = ["oauth", "csrf", "pkce", "semgrep", "static analysis", "token", "security scan"]
    e2e_kw = ["e2e", "end-to-end", "staging", "stripe", "test key", "config drift", "qa", "payment flow"]

    has_migration = any(kw in combined for kw in migration_kw)
    has_security = any(kw in combined for kw in security_kw)
    has_e2e = any(kw in combined for kw in e2e_kw)
    acknowledged = sum([has_migration, has_security, has_e2e])

    if acknowledged >= 3:
        c8 = 10
    elif acknowledged == 2:
        c8 = 6
    elif acknowledged == 1:
        c8 = 3
    feedback.append(
        f"C8: +{c8} Blockers acknowledged ({acknowledged}/3): "
        f"migration={has_migration}, security={has_security}, e2e_tests={has_e2e}"
    )
    score += c8

    passed = score >= 60
    summary = f"Score: {score}/100 (pass >= 60)\n" + "\n".join(feedback)

    return {
        "passed": passed,
        "score": score,
        "feedback": summary,
    }
