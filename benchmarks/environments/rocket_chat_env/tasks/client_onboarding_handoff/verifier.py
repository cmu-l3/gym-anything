#!/usr/bin/env python3
"""Verifier for client_onboarding_handoff task.

Scoring breakdown (100 points, pass >= 70):
  C1  (10pts): Private channel proj-meridian-internal exists
  C2  (8pts):  Internal channel topic contains "Meridian" and "$2.4M" or "EHR" or "Discovery"
  C3  (12pts): Internal delivery team members invited (solutions.architect, delivery.lead, ux.designer, data.engineer) - 3pts each
  C4  (15pts): Kickoff message with HL7/FHIR + risk factor (legacy lab or Cerner) + timeline reference
  C5  (5pts):  Kickoff message pinned
  C6  (8pts):  Public channel proj-meridian-client exists
  C7  (10pts): Client channel members invited (solutions.architect, delivery.lead, account.manager, client.sponsor) - partial credit
  C8  (8pts):  Welcome message in client channel mentioning project/team/kickoff
  C9  (10pts): Thread reply on briefing message in #sales-handoffs confirming handoff
  C10 (14pts): DM to solutions.architect about technical assessment / HL7 FHIR / legacy lab API
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/client_onboarding_handoff_result.json"


def verify_client_onboarding_handoff(traj, env_info, task_info):
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

    int_ch = result.get("internal_channel", {})
    cli_ch = result.get("client_channel", {})

    # --- Do-nothing gate ---
    if not int_ch.get("exists", False) and not cli_ch.get("exists", False):
        int_msgs = int_ch.get("messages", [])
        dm_msgs = result.get("solutions_architect_dm", {}).get("messages", [])
        thread_msgs = result.get("sales_handoffs", {}).get("thread_replies", [])
        if len(int_msgs) == 0 and len(dm_msgs) == 0 and len(thread_msgs) == 0:
            return {
                "passed": False,
                "score": 0,
                "feedback": "No project channels created and no actions taken. Agent likely did nothing.",
            }

    # --- C1 (10pts): Private channel proj-meridian-internal exists ---
    if int_ch.get("exists"):
        if int_ch.get("type") == "private":
            score += 10
            feedback.append("C1: +10 Private internal channel exists")
        else:
            score += 5
            feedback.append("C1: +5 Internal channel exists but is public (expected private)")
    else:
        feedback.append("C1: +0 Channel proj-meridian-internal not found")

    # --- C2 (8pts): Internal channel topic ---
    topic = (int_ch.get("topic") or "").lower()
    c2 = 0
    has_meridian = "meridian" in topic
    has_budget = "$2.4m" in topic or "2.4m" in topic
    has_ehr = "ehr" in topic
    has_discovery = "discovery" in topic
    if has_meridian:
        c2 += 4
    if has_budget or has_ehr or has_discovery:
        c2 += 4
    score += c2
    feedback.append(f"C2: +{c2} Topic check (found: {int_ch.get('topic', 'none')[:120]})")

    # --- C3 (12pts): Internal delivery team members - 3pts each ---
    int_members = [m.lower() for m in int_ch.get("members", [])]
    c3 = 0
    required_internal = ["solutions.architect", "delivery.lead", "ux.designer", "data.engineer"]
    found_internal = []
    for req in required_internal:
        if req in int_members:
            c3 += 3
            found_internal.append(req)
    score += c3
    feedback.append(f"C3: +{c3} Internal members ({len(found_internal)}/4: {found_internal})")

    # --- C4 (15pts): Kickoff message with requirements from briefing ---
    int_messages = int_ch.get("messages", [])
    c4 = 0
    best_kickoff_score = 0
    for msg in int_messages:
        text = (msg.get("msg") or "").lower()
        has_fhir = "hl7" in text or "fhir" in text
        has_risk = "legacy lab" in text or "legacy" in text or "cerner" in text or "undocumented" in text or "no documented api" in text
        has_timeline = any(kw in text for kw in [
            "discovery", "build phase", "go-live", "go live",
            "uat", "timeline", "mar", "apr", "2026", "2027",
            "milestone", "phase"
        ])
        section_score = 0
        if has_fhir:
            section_score += 5
        if has_risk:
            section_score += 5
        if has_timeline:
            section_score += 5
        best_kickoff_score = max(best_kickoff_score, section_score)
    c4 = best_kickoff_score
    score += c4
    feedback.append(f"C4: +{c4} Kickoff message (FHIR/risk/timeline)")

    # --- C5 (5pts): Kickoff message pinned ---
    pinned = int_ch.get("pinned_messages", [])
    c5 = 0
    if len(pinned) > 0:
        c5 = 5
    else:
        any_pinned = any(m.get("pinned") for m in int_messages)
        if any_pinned:
            c5 = 5
    score += c5
    feedback.append(f"C5: +{c5} Pinned messages ({len(pinned)} found)")

    # --- C6 (8pts): Public channel proj-meridian-client exists ---
    if cli_ch.get("exists"):
        if cli_ch.get("type") == "public":
            score += 8
            feedback.append("C6: +8 Public client channel exists")
        else:
            score += 4
            feedback.append("C6: +4 Client channel exists but is private (expected public)")
    else:
        feedback.append("C6: +0 Channel proj-meridian-client not found")

    # --- C7 (10pts): Client channel members - partial credit ---
    cli_members = [m.lower() for m in cli_ch.get("members", [])]
    c7 = 0
    required_client = ["solutions.architect", "delivery.lead", "account.manager", "client.sponsor"]
    found_client = []
    for req in required_client:
        if req in cli_members:
            c7 += 2.5
            found_client.append(req)
    c7 = int(c7)  # Round down to avoid float issues
    # Give full credit if all 4 found (handle rounding: 2.5*4=10)
    if len(found_client) == len(required_client):
        c7 = 10
    score += c7
    feedback.append(f"C7: +{c7} Client members ({len(found_client)}/4: {found_client})")

    # --- C8 (8pts): Welcome message in client channel ---
    cli_messages = cli_ch.get("messages", [])
    c8 = 0
    for msg in cli_messages:
        text = (msg.get("msg") or "").lower()
        has_project = any(kw in text for kw in ["meridian", "project", "ehr", "integration"])
        has_team = any(kw in text for kw in ["team", "welcome", "introduce", "introducing", "delivery"])
        has_kickoff = any(kw in text for kw in ["kickoff", "kick-off", "kick off", "timeline", "discovery", "onboard"])
        if has_project and (has_team or has_kickoff):
            c8 = 8
            break
        elif has_project:
            c8 = max(c8, 4)
    score += c8
    feedback.append(f"C8: +{c8} Welcome message in client channel")

    # --- C9 (10pts): Thread reply on briefing message confirming handoff ---
    thread_replies = result.get("sales_handoffs", {}).get("thread_replies", [])
    c9 = 0
    if len(thread_replies) > 0:
        c9 = 5
        for reply in thread_replies:
            text = (reply.get("msg") or "").lower()
            if any(kw in text for kw in ["handoff", "hand-off", "hand off", "channels", "set up", "setup", "complete", "created", "taken over", "proj-meridian"]):
                c9 = 10
                break
    score += c9
    feedback.append(f"C9: +{c9} Thread reply on briefing ({len(thread_replies)} replies)")

    # --- C10 (14pts): DM to solutions.architect ---
    dm_messages = result.get("solutions_architect_dm", {}).get("messages", [])
    c10 = 0
    if len(dm_messages) > 0:
        c10 = 4
        for msg in dm_messages:
            text = (msg.get("msg") or "").lower()
            has_fhir_dm = "hl7" in text or "fhir" in text
            has_legacy_dm = "legacy" in text or "lab" in text or "api" in text
            has_assessment = any(kw in text for kw in ["assess", "review", "evaluate", "analysis", "technical", "investigation", "look into", "examine"])
            if has_fhir_dm and has_legacy_dm:
                c10 = 14
                break
            elif has_fhir_dm or has_legacy_dm:
                c10 = max(c10, 9)
            elif has_assessment:
                c10 = max(c10, 7)
    score += c10
    feedback.append(f"C10: +{c10} DM to solutions.architect ({len(dm_messages)} messages)")

    passed = score >= 70
    summary = f"Score: {score}/100 (pass >= 70)\n" + "\n".join(feedback)

    return {
        "passed": passed,
        "score": score,
        "feedback": summary,
    }
