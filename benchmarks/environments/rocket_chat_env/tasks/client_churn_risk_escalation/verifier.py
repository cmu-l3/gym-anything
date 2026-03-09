#!/usr/bin/env python3
"""Verifier for client_churn_risk_escalation task.

Occupation: Sales Manager / Senior Account Manager
Industry: Technology / B2B SaaS

Scenario: Account Manager must save a $1.2M ARR enterprise account (Meridian
Financial Group) that is actively threatening to churn 47 days before renewal.
Must coordinate internal escalation, draft retention plan, engage executives,
address open P1 tickets, and secure exec-to-exec outreach.

Scoring (100 points, pass >= 60):
  C1 (10pts): Internal escalation channel created for Meridian coordination
  C2 (15pts): All four core stakeholders engaged (cs.manager, vp.sales, cto.internal,
               exec.sponsor) in channel OR via DM
  C3 (15pts): Thread replies on the customer success channel messages showing
               acknowledgment of the situation
  C4 (15pts): Retention plan content present — addresses at least 2 of: ticket SLA,
               roadmap commitment, credit/discount, exec call
  C5 (10pts): Executive sponsor (exec.sponsor/CEO) contacted via DM or in channel
               with urgent framing
  C6 (15pts): Product/engineering notified about roadmap commitment requirements
               (cto.internal or product.lead engaged)
  C7 (10pts): Urgency and business impact communicated (ARR, renewal, deadline, churn
               risk, Q2, board keywords)
  C8 (10pts): Support lead notified about P1 ticket resolution priority
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/client_churn_risk_escalation_result.json"

STAKEHOLDERS = ["cs.manager", "vp.sales", "cto.internal", "product.lead", "exec.sponsor", "support.lead"]


def _collect_all_admin_text(result):
    texts = []
    ec = result.get("escalation_channel", {})
    for m in ec.get("messages", []):
        if m.get("u") != "system":
            texts.append((m.get("msg") or "").lower())
    for m in result.get("cs_channel_admin_messages", []):
        texts.append((m.get("msg") or "").lower())
    for msgs in result.get("direct_messages", {}).values():
        for m in msgs:
            texts.append((m.get("msg") or "").lower())
    for thread_msgs in result.get("cs_channel_threads", {}).values():
        for m in thread_msgs:
            if m.get("u") == "admin":
                texts.append((m.get("msg") or "").lower())
    return texts


def verify_client_churn_risk_escalation(traj, env_info, task_info):
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

    ec = result.get("escalation_channel", {})
    ec_messages = ec.get("messages", [])
    ec_members = [m.lower() for m in ec.get("members", [])]
    threads = result.get("cs_channel_threads", {})
    dms = result.get("direct_messages", {})
    cs_admin = result.get("cs_channel_admin_messages", [])

    all_texts = _collect_all_admin_text(result)
    combined = " ".join(all_texts)

    # Do-nothing gate
    ec_msg_count = len([m for m in ec_messages if m.get("u") != "system"])
    thread_count = sum(len(v) for v in threads.values())
    dm_count = sum(len(v) for v in dms.values())

    if ec_msg_count == 0 and thread_count == 0 and dm_count == 0 and len(cs_admin) == 0:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No escalation activity detected. Agent likely did nothing.",
        }

    # --- C1 (10pts): Escalation channel created ---
    c1 = 0
    if ec.get("found"):
        c1 = 10
        feedback.append(f"C1: +10 Escalation channel created: '{ec.get('name', 'unknown')}'")
    elif len(cs_admin) >= 2:
        c1 = 5
        feedback.append(f"C1: +5 {len(cs_admin)} admin msgs in CS channel (no dedicated escalation channel)")
    else:
        feedback.append("C1: +0 No escalation channel found")
    score += c1

    # --- C2 (15pts): Core stakeholders engaged ---
    c2 = 0
    stakeholders_in_channel = [s for s in STAKEHOLDERS if s in ec_members]
    stakeholders_dmd = []
    dm_key_map = {
        "cs.manager": "cs_manager", "vp.sales": "vp_sales",
        "cto.internal": "cto_internal", "product.lead": "product_lead",
        "exec.sponsor": "exec_sponsor", "support.lead": "support_lead"
    }
    for s, dm_key in dm_key_map.items():
        if len(dms.get(dm_key, [])) > 0:
            stakeholders_dmd.append(s)
    core_four = ["cs.manager", "vp.sales", "cto.internal", "exec.sponsor"]
    core_engaged = set(stakeholders_in_channel + stakeholders_dmd)
    core_four_engaged = [s for s in core_four if s in core_engaged]
    if len(core_four_engaged) >= 4:
        c2 = 15
    elif len(core_four_engaged) >= 3:
        c2 = 10
    elif len(core_four_engaged) >= 2:
        c2 = 6
    elif len(core_four_engaged) >= 1:
        c2 = 3
    feedback.append(
        f"C2: +{c2} Core stakeholders engaged ({len(core_four_engaged)}/4): "
        f"channel={stakeholders_in_channel}, DM'd={stakeholders_dmd}"
    )
    score += c2

    # --- C3 (15pts): Thread replies on CS channel messages ---
    c3 = 0
    threads_replied = sum(1 for v in threads.values() if len(v) > 0)
    if threads_replied >= 2:
        c3 = 15
    elif threads_replied == 1:
        c3 = 8
    thread_counts = {k: len(v) for k, v in threads.items()}
    feedback.append(f"C3: +{c3} Thread replies on CS messages ({threads_replied}/2): {thread_counts}")
    score += c3

    # --- C4 (15pts): Retention plan content ---
    c4 = 0
    ticket_kw = ["p1-4821", "p1-4898", "sev-1", "sev1", "ticket", "support", "bug fix", "48 hour", "48h", "resolve"]
    roadmap_kw = ["roadmap", "commitment", "q2", "feature", "delay", "cto", "letter", "signed", "confirm"]
    credit_kw = ["credit", "discount", "comp", "free month", "service credit", "month", "concession"]
    exec_call_kw = ["exec", "ceo", "robert", "marcus", "call", "meeting", "march 14", "board", "exec-to-exec"]

    has_ticket = any(kw in combined for kw in ticket_kw)
    has_roadmap = any(kw in combined for kw in roadmap_kw)
    has_credit = any(kw in combined for kw in credit_kw)
    has_exec_call = any(kw in combined for kw in exec_call_kw)
    retention_elements = sum([has_ticket, has_roadmap, has_credit, has_exec_call])

    if retention_elements >= 4:
        c4 = 15
    elif retention_elements >= 3:
        c4 = 12
    elif retention_elements >= 2:
        c4 = 8
    elif retention_elements >= 1:
        c4 = 4
    feedback.append(
        f"C4: +{c4} Retention plan elements ({retention_elements}/4): "
        f"tickets={has_ticket}, roadmap={has_roadmap}, credit={has_credit}, exec_call={has_exec_call}"
    )
    score += c4

    # --- C5 (10pts): Executive sponsor contacted ---
    c5 = 0
    exec_dm_count = len(dms.get("exec_sponsor", []))
    exec_in_channel = "exec.sponsor" in ec_members
    exec_mentioned = "exec.sponsor" in combined or "robert" in combined or "ceo" in combined
    if exec_dm_count > 0 and (exec_in_channel or exec_mentioned):
        c5 = 10
    elif exec_dm_count > 0:
        c5 = 8
    elif exec_in_channel:
        c5 = 6
    elif exec_mentioned:
        c5 = 3
    feedback.append(
        f"C5: +{c5} Executive sponsor (exec.sponsor/CEO) engaged "
        f"(DMs: {exec_dm_count}, in channel: {exec_in_channel})"
    )
    score += c5

    # --- C6 (15pts): Product/engineering engaged for roadmap commitments ---
    c6 = 0
    cto_dm_count = len(dms.get("cto_internal", []))
    product_dm_count = len(dms.get("product_lead", []))
    cto_in_channel = "cto.internal" in ec_members
    product_in_channel = "product.lead" in ec_members
    eng_engaged = (cto_dm_count + product_dm_count > 0) or cto_in_channel or product_in_channel
    if (cto_dm_count > 0 or cto_in_channel) and (product_dm_count > 0 or product_in_channel):
        c6 = 15
    elif cto_dm_count > 0 or cto_in_channel:
        c6 = 10
    elif product_dm_count > 0 or product_in_channel:
        c6 = 8
    elif eng_engaged:
        c6 = 4
    feedback.append(
        f"C6: +{c6} Eng/Product engaged (CTO DMs: {cto_dm_count}, in channel: {cto_in_channel}; "
        f"Product DMs: {product_dm_count}, in channel: {product_in_channel})"
    )
    score += c6

    # --- C7 (10pts): Business impact/urgency communicated ---
    c7 = 0
    urgency_kw = ["1.2m", "1200000", "arr", "renewal", "47 day", "churn", "q2", "board",
                  "diana walsh", "meridian", "series c", "revenue", "miss", "risk"]
    urgency_hits = [kw for kw in urgency_kw if kw in combined]
    if len(urgency_hits) >= 5:
        c7 = 10
    elif len(urgency_hits) >= 3:
        c7 = 6
    elif len(urgency_hits) >= 1:
        c7 = 3
    feedback.append(f"C7: +{c7} Business impact keywords ({len(urgency_hits)}): {urgency_hits[:5]}")
    score += c7

    # --- C8 (10pts): Support lead notified for P1 ticket resolution ---
    c8 = 0
    support_dm_count = len(dms.get("support_lead", []))
    support_in_channel = "support.lead" in ec_members
    support_tickets_mentioned = any(kw in combined for kw in ["p1-4821", "p1-4898", "sev-1", "bulk export", "sso"])
    if support_dm_count > 0 and support_tickets_mentioned:
        c8 = 10
    elif support_dm_count > 0:
        c8 = 6
    elif support_in_channel and support_tickets_mentioned:
        c8 = 6
    elif support_in_channel or support_tickets_mentioned:
        c8 = 3
    feedback.append(
        f"C8: +{c8} Support lead notified "
        f"(DMs: {support_dm_count}, in channel: {support_in_channel}, tickets mentioned: {support_tickets_mentioned})"
    )
    score += c8

    passed = score >= 60
    summary = f"Score: {score}/100 (pass >= 60)\n" + "\n".join(feedback)

    return {
        "passed": passed,
        "score": score,
        "feedback": summary,
    }
