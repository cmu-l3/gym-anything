#!/usr/bin/env python3
"""Verifier for incident_response_coordination task.

Scoring breakdown (100 points, pass >= 70):
  C1 (12pts): Private channel inc-20260306-db-outage exists
  C2 (12pts): Channel topic contains P1, database/connection pool, timestamp
  C3 (15pts): Required members invited (ops.lead, backend.dev, dba.admin) - 5pts each
  C4 (15pts): Incident summary with Impact/Status/Next Steps sections
  C5 (10pts): At least one pinned message in incident channel
  C6 (12pts): Thread reply on DB alert in #production-alerts
  C7 (12pts): DM to qa.engineer about test plan
  C8 (12pts): Status update message in incident channel
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/incident_response_coordination_result.json"


def verify_incident_response_coordination(traj, env_info, task_info):
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

    inc = result.get("incident_channel", {})

    # --- Do-nothing gate ---
    if not inc.get("exists", False):
        messages = inc.get("messages", [])
        dm_msgs = result.get("qa_engineer_dm", {}).get("messages", [])
        thread_msgs = result.get("production_alerts", {}).get("thread_replies", [])
        if len(messages) == 0 and len(dm_msgs) == 0 and len(thread_msgs) == 0:
            return {
                "passed": False,
                "score": 0,
                "feedback": "No incident channel created and no actions taken. Agent likely did nothing.",
            }

    # --- C1 (12pts): Private channel exists ---
    if inc.get("exists"):
        if inc.get("type") == "private":
            score += 12
            feedback.append("C1: +12 Private incident channel exists")
        else:
            score += 6
            feedback.append("C1: +6 Incident channel exists but is public (expected private)")
    else:
        feedback.append("C1: +0 Incident channel inc-20260306-db-outage not found")

    # --- C2 (12pts): Channel topic ---
    topic = (inc.get("topic") or "").lower()
    c2 = 0
    if "p1" in topic:
        c2 += 4
    if "database" in topic or "connection pool" in topic or "db" in topic:
        c2 += 4
    if "2026-03-06" in topic or "14:30" in topic:
        c2 += 4
    score += c2
    feedback.append(f"C2: +{c2} Topic check (found: {inc.get('topic', 'none')[:100]})")

    # --- C3 (15pts): Members invited - 5pts each ---
    members = [m.lower() for m in inc.get("members", [])]
    c3 = 0
    required_members = ["ops.lead", "backend.dev", "dba.admin"]
    found_members = []
    for req in required_members:
        if req in members:
            c3 += 5
            found_members.append(req)
    score += c3
    feedback.append(f"C3: +{c3} Members ({len(found_members)}/3: {found_members})")

    # --- C4 (15pts): Incident summary with required sections ---
    messages = inc.get("messages", [])
    c4 = 0
    best_summary_score = 0
    for msg in messages:
        text = (msg.get("msg") or "").lower()
        has_impact = "impact" in text
        has_status = "status" in text or "current status" in text
        has_next = "next step" in text or "next steps" in text or "action" in text
        section_count = sum([has_impact, has_status, has_next])
        if section_count == 3:
            best_summary_score = 15
            break
        elif section_count > 0:
            best_summary_score = max(best_summary_score, section_count * 5)
    c4 = best_summary_score
    score += c4
    feedback.append(f"C4: +{c4} Incident summary message")

    # --- C5 (10pts): Pinned message ---
    pinned = inc.get("pinned_messages", [])
    c5 = 0
    if len(pinned) > 0:
        c5 = 10
    else:
        any_pinned = any(m.get("pinned") for m in messages)
        if any_pinned:
            c5 = 10
    score += c5
    feedback.append(f"C5: +{c5} Pinned messages ({len(pinned)} found)")

    # --- C6 (12pts): Thread reply on DB alert ---
    thread_replies = result.get("production_alerts", {}).get("thread_replies", [])
    c6 = 0
    if len(thread_replies) > 0:
        c6 = 8
        for reply in thread_replies:
            text = (reply.get("msg") or "").lower()
            if "inc-" in text or "incident" in text or "channel" in text:
                c6 = 12
                break
    score += c6
    feedback.append(f"C6: +{c6} Thread reply on DB alert ({len(thread_replies)} replies)")

    # --- C7 (12pts): DM to qa.engineer ---
    dm_messages = result.get("qa_engineer_dm", {}).get("messages", [])
    c7 = 0
    if len(dm_messages) > 0:
        c7 = 6
        for msg in dm_messages:
            text = (msg.get("msg") or "").lower()
            if any(kw in text for kw in ["test", "regression", "plan", "qa", "verify"]):
                c7 = 12
                break
    score += c7
    feedback.append(f"C7: +{c7} DM to qa.engineer ({len(dm_messages)} messages)")

    # --- C8 (12pts): Status update in incident channel ---
    c8 = 0
    for msg in messages:
        text = (msg.get("msg") or "").lower()
        if any(kw in text for kw in ["investigating", "update", "status update", "actively"]):
            # Ensure it's not the same as the summary message (different content)
            has_impact = "impact" in text
            has_next = "next step" in text or "next steps" in text
            if has_impact and has_next:
                continue  # This is likely the summary, not a separate update
            c8 = 12
            break
    score += c8
    feedback.append(f"C8: +{c8} Status update in incident channel")

    passed = score >= 70
    summary = f"Score: {score}/100 (pass >= 70)\n" + "\n".join(feedback)

    return {
        "passed": passed,
        "score": score,
        "feedback": summary,
    }
