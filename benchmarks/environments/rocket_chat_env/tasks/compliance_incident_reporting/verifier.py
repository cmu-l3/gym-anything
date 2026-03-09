#!/usr/bin/env python3
"""Verifier for compliance_incident_reporting task.

Scoring breakdown (100 points, pass >= 70):
  C1  (7pts):  PHI alert message starred in #security-monitoring
  C2  (10pts): Private channel hipaa-inc-2026-0306 exists
  C3  (8pts):  Channel topic contains HIPAA + PHI/patients/847 + /api/v2/records
  C4  (12pts): Required members invited (privacy.officer, legal.counsel, it.director, sys.admin) - 3pts each
  C5  (15pts): Structured incident report with required sections
  C6  (5pts):  Incident report pinned
  C7  (10pts): Thread reply on PHI alert confirming HIPAA process initiated
  C8  (12pts): DM to privacy.officer about 60-day notification / affected patients
  C9  (11pts): DM to legal.counsel about legal hold / HHS / OCR
  C10 (10pts): Message in #compliance-log about the incident
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/compliance_incident_reporting_result.json"


def verify_compliance_incident_reporting(traj, env_info, task_info):
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
        dm_priv = result.get("privacy_officer_dm", {}).get("messages", [])
        dm_legal = result.get("legal_counsel_dm", {}).get("messages", [])
        thread_msgs = result.get("security_monitoring", {}).get("thread_replies", [])
        comp_msgs = result.get("compliance_log", {}).get("messages", [])
        starred = result.get("phi_alert_starred", False)
        if (
            len(messages) == 0
            and len(dm_priv) == 0
            and len(dm_legal) == 0
            and len(thread_msgs) == 0
            and len(comp_msgs) == 0
            and not starred
        ):
            return {
                "passed": False,
                "score": 0,
                "feedback": "No incident channel created and no actions taken. Agent likely did nothing.",
            }

    # --- C1 (7pts): PHI alert message starred ---
    c1 = 0
    if result.get("phi_alert_starred", False):
        c1 = 7
    score += c1
    feedback.append(f"C1: +{c1} PHI alert starred ({result.get('phi_alert_starred', False)})")

    # --- C2 (10pts): Private channel exists ---
    c2 = 0
    if inc.get("exists"):
        if inc.get("type") == "private":
            c2 = 10
            feedback.append("C2: +10 Private incident channel hipaa-inc-2026-0306 exists")
        else:
            c2 = 5
            feedback.append("C2: +5 Incident channel exists but is public (expected private)")
    else:
        feedback.append("C2: +0 Incident channel hipaa-inc-2026-0306 not found")
    score += c2

    # --- C3 (8pts): Channel topic ---
    topic = (inc.get("topic") or "").lower()
    c3 = 0
    if "hipaa" in topic:
        c3 += 3
    if any(kw in topic for kw in ["phi", "patients", "847"]):
        c3 += 3
    if "/api/v2" in topic or "records" in topic:
        c3 += 2
    score += c3
    feedback.append(f"C3: +{c3} Topic check (found: {inc.get('topic', 'none')[:120]})")

    # --- C4 (12pts): Members invited - 3pts each ---
    members = [m.lower() for m in inc.get("members", [])]
    c4 = 0
    required_members = ["privacy.officer", "legal.counsel", "it.director", "sys.admin"]
    found_members = []
    for req in required_members:
        if req in members:
            c4 += 3
            found_members.append(req)
    score += c4
    feedback.append(f"C4: +{c4} Members ({len(found_members)}/4: {found_members})")

    # --- C5 (15pts): Structured incident report with required sections ---
    messages = inc.get("messages", [])
    c5 = 0
    best_report_score = 0
    for msg in messages:
        text = (msg.get("msg") or "").lower()
        sec_score = 0
        # (a) Incident Summary
        has_summary = "incident summary" in text or ("incident" in text and "summary" in text)
        if has_summary:
            sec_score += 3
        # (b) Affected Data (patient names, DOBs, MRNs, ICD-10)
        has_affected = any(kw in text for kw in ["affected data", "patient names", "dob", "mrn", "icd-10", "medical record"])
        if has_affected:
            sec_score += 3
        # (c) Timeline
        has_timeline = "timeline" in text
        if has_timeline:
            sec_score += 3
        # (d) Containment Actions
        has_containment = "containment" in text
        if has_containment:
            sec_score += 3
        # (e) Regulatory Requirements / HIPAA reference
        has_regulatory = any(kw in text for kw in ["regulatory", "hipaa", "45 cfr", "breach notification"])
        if has_regulatory:
            sec_score += 3
        best_report_score = max(best_report_score, sec_score)
    c5 = best_report_score
    score += c5
    feedback.append(f"C5: +{c5} Incident report sections (max 15)")

    # --- C6 (5pts): Incident report pinned ---
    pinned = inc.get("pinned_messages", [])
    c6 = 0
    if len(pinned) > 0:
        c6 = 5
    else:
        any_pinned = any(m.get("pinned") for m in messages)
        if any_pinned:
            c6 = 5
    score += c6
    feedback.append(f"C6: +{c6} Pinned messages ({len(pinned)} found)")

    # --- C7 (10pts): Thread reply on PHI alert confirming HIPAA process ---
    thread_replies = result.get("security_monitoring", {}).get("thread_replies", [])
    c7 = 0
    if len(thread_replies) > 0:
        c7 = 5
        for reply in thread_replies:
            text = (reply.get("msg") or "").lower()
            if any(kw in text for kw in ["hipaa", "incident", "channel", "initiated", "response"]):
                c7 = 10
                break
    score += c7
    feedback.append(f"C7: +{c7} Thread reply on PHI alert ({len(thread_replies)} replies)")

    # --- C8 (12pts): DM to privacy.officer ---
    dm_priv_messages = result.get("privacy_officer_dm", {}).get("messages", [])
    c8 = 0
    if len(dm_priv_messages) > 0:
        c8 = 4
        for msg in dm_priv_messages:
            text = (msg.get("msg") or "").lower()
            kw_count = sum(
                1
                for kw in ["60-day", "60 day", "notification", "847", "patient", "breach", "letter"]
                if kw in text
            )
            if kw_count >= 2:
                c8 = 12
                break
            elif kw_count >= 1:
                c8 = max(c8, 8)
    score += c8
    feedback.append(f"C8: +{c8} DM to privacy.officer ({len(dm_priv_messages)} messages)")

    # --- C9 (11pts): DM to legal.counsel ---
    dm_legal_messages = result.get("legal_counsel_dm", {}).get("messages", [])
    c9 = 0
    if len(dm_legal_messages) > 0:
        c9 = 4
        for msg in dm_legal_messages:
            text = (msg.get("msg") or "").lower()
            kw_count = sum(
                1
                for kw in ["legal hold", "hhs", "ocr", "office for civil rights", "log", "notification"]
                if kw in text
            )
            if kw_count >= 2:
                c9 = 11
                break
            elif kw_count >= 1:
                c9 = max(c9, 7)
    score += c9
    feedback.append(f"C9: +{c9} DM to legal.counsel ({len(dm_legal_messages)} messages)")

    # --- C10 (10pts): Message in #compliance-log ---
    comp_messages = result.get("compliance_log", {}).get("messages", [])
    c10 = 0
    if len(comp_messages) > 0:
        c10 = 3
        for msg in comp_messages:
            text = (msg.get("msg") or "").lower()
            kw_count = sum(
                1
                for kw in ["phi", "exposure", "847", "hipaa-inc", "2026-03-06", "patient", "breach"]
                if kw in text
            )
            if kw_count >= 3:
                c10 = 10
                break
            elif kw_count >= 2:
                c10 = max(c10, 7)
            elif kw_count >= 1:
                c10 = max(c10, 5)
    score += c10
    feedback.append(f"C10: +{c10} Compliance log entry ({len(comp_messages)} messages)")

    passed = score >= 70
    summary = f"Score: {score}/100 (pass >= 70)\n" + "\n".join(feedback)

    return {
        "passed": passed,
        "score": score,
        "feedback": summary,
    }
