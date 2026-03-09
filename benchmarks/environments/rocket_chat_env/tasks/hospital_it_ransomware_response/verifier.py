#!/usr/bin/env python3
"""Verifier for hospital_it_ransomware_response task.

Occupation: Computer and Information Systems Manager
Industry: Healthcare

Scenario: Hospital IT Manager must respond to an active ransomware incident affecting
the EHR system and patient care operations, coordinating across clinical and technical teams.

Scoring (100 points, pass >= 60):
  C1 (15pts): A new private channel was created for incident management
  C2 (10pts): The channel name or topic indicates incident/security/emergency response
  C3 (15pts): Required stakeholders invited: clinical.coordinator, it.security,
               nursing.supervisor, ciso (5pts each, up to 3 required for full score)
  C4 (15pts): A structured incident declaration or status message with required elements
               (impact on patient care, affected systems, containment/response actions)
  C5 (10pts): At least one message pinned in the incident channel
  C6 (15pts): Thread replies on at least 2 of the 3 seeded alert messages
               (clinical-it-alerts, nursing-coordination, it-security-ops)
  C7 (10pts): DMs sent to clinical.coordinator OR it.security about the incident
  C8 (10pts): A follow-up status update message in the incident channel (separate from declaration)
"""

import json
import os
import tempfile
import logging
import re

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/hospital_it_ransomware_response_result.json"


def verify_hospital_it_ransomware_response(traj, env_info, task_info):
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
    threads = result.get("alert_thread_replies", {})
    dms = result.get("direct_messages", {})

    # Do-nothing gate: if no incident channel and no threads and no DMs, likely nothing done
    inc_messages = inc.get("messages", [])
    clinical_threads = threads.get("clinical_it_alerts", [])
    nursing_threads = threads.get("nursing_coordination", [])
    itsec_threads = threads.get("it_security_ops", [])
    total_thread_count = len(clinical_threads) + len(nursing_threads) + len(itsec_threads)
    clin_dm = dms.get("clinical_coordinator", [])
    sec_dm = dms.get("it_security", [])
    ciso_dm = dms.get("ciso", [])
    total_dm_count = len(clin_dm) + len(sec_dm) + len(ciso_dm)

    if not inc.get("found") and total_thread_count == 0 and total_dm_count == 0:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No incident channel created and no coordinating actions taken. Agent likely did nothing.",
        }

    # --- C1 (15pts): New private channel for incident management ---
    c1 = 0
    if inc.get("found"):
        c1 = 15
        feedback.append(f"C1: +15 New incident management channel created: '{inc.get('name', 'unknown')}'")
    else:
        feedback.append("C1: +0 No new private channel detected for incident management")
    score += c1

    # --- C2 (10pts): Channel name or topic indicates incident/security response ---
    c2 = 0
    if inc.get("found"):
        name_lower = (inc.get("name") or "").lower()
        topic_lower = (inc.get("topic") or "").lower()
        combined = name_lower + " " + topic_lower
        incident_kw = ["incident", "inc", "ransomware", "emergency", "ir", "security", "response",
                       "crisis", "ehr", "breach", "lockbit", "cyber", "attack", "outage"]
        severity_kw = ["critical", "p1", "priority", "urgent", "hipaa", "patient", "clinical"]
        if any(kw in combined for kw in incident_kw):
            c2 += 6
        if any(kw in combined for kw in severity_kw):
            c2 += 4
        if c2 == 0:
            c2 = 2  # Partial credit just for creating any channel
    feedback.append(f"C2: +{c2} Channel naming/topic indicates incident response (name='{inc.get('name', 'none')}')")
    score += c2

    # --- C3 (15pts): Required stakeholders invited (5pts each, max 15) ---
    members = [m.lower() for m in inc.get("members", [])]
    c3 = 0
    required = ["clinical.coordinator", "it.security", "nursing.supervisor", "ciso"]
    found_members = []
    for req in required:
        if req in members:
            c3 += 5
            found_members.append(req)
    c3 = min(c3, 15)
    score += c3
    feedback.append(f"C3: +{c3} Stakeholders invited ({len(found_members)}/4 required: {found_members})")

    # --- C4 (15pts): Structured incident declaration with key elements ---
    c4 = 0
    best_score = 0
    for msg in inc_messages:
        text = (msg.get("msg") or "").lower()
        # Check for key incident management elements
        has_patient_impact = any(kw in text for kw in ["patient", "clinical", "ehr", "care", "nursing", "floor"])
        has_system_impact = any(kw in text for kw in ["system", "server", "network", "ehr", "application", "service"])
        has_response = any(kw in text for kw in ["contain", "isolat", "response", "team", "action", "investigat", "remediat"])
        has_status = any(kw in text for kw in ["status", "impact", "affected", "current", "ongoing", "active"])
        section_score = sum([has_patient_impact, has_system_impact, has_response, has_status])
        if section_score >= 3:
            best_score = 15
            break
        elif section_score == 2:
            best_score = max(best_score, 10)
        elif section_score == 1:
            best_score = max(best_score, 5)
    c4 = best_score
    score += c4
    feedback.append(f"C4: +{c4} Incident declaration/status message quality")

    # --- C5 (10pts): Pinned message in incident channel ---
    pinned = inc.get("pinned_messages", [])
    c5 = 0
    if len(pinned) > 0:
        c5 = 10
    elif any(m.get("pinned") for m in inc_messages):
        c5 = 10
    score += c5
    feedback.append(f"C5: +{c5} Pinned message in incident channel ({len(pinned)} pinned)")

    # --- C6 (15pts): Thread replies on at least 2 alert channels (7pts each, max 15) ---
    c6 = 0
    channels_replied = 0
    if len(clinical_threads) > 0:
        c6 += 7
        channels_replied += 1
    if len(nursing_threads) > 0:
        c6 += 7
        channels_replied += 1
    if len(itsec_threads) > 0:
        c6 += 7
        channels_replied += 1
    c6 = min(c6, 15)
    score += c6
    feedback.append(
        f"C6: +{c6} Thread replies on alert channels "
        f"(clinical:{len(clinical_threads)}, nursing:{len(nursing_threads)}, itsec:{len(itsec_threads)})"
    )

    # --- C7 (10pts): DMs to clinical.coordinator or it.security ---
    c7 = 0
    dm_sent_to = []
    if len(clin_dm) > 0:
        c7 += 5
        dm_sent_to.append("clinical.coordinator")
    if len(sec_dm) > 0:
        c7 += 5
        dm_sent_to.append("it.security")
    if len(ciso_dm) > 0 and c7 < 10:
        c7 = min(c7 + 5, 10)
        dm_sent_to.append("ciso")
    c7 = min(c7, 10)
    score += c7
    feedback.append(f"C7: +{c7} DMs sent to: {dm_sent_to}")

    # --- C8 (10pts): Follow-up status update (2nd substantive message in incident channel) ---
    c8 = 0
    status_messages = []
    for msg in inc_messages:
        text = (msg.get("msg") or "").lower()
        # Skip system messages (room created, member joined, etc.)
        if msg.get("u") == "system":
            continue
        if any(kw in text for kw in ["update", "status", "progress", "investigat", "contain", "team"]):
            status_messages.append(msg)
    if len(status_messages) >= 2:
        c8 = 10
    elif len(status_messages) == 1:
        c8 = 5
    score += c8
    feedback.append(f"C8: +{c8} Follow-up status update in incident channel ({len(status_messages)} qualifying messages)")

    passed = score >= 60
    summary = f"Score: {score}/100 (pass >= 60)\n" + "\n".join(feedback)

    return {
        "passed": passed,
        "score": score,
        "feedback": summary,
    }
