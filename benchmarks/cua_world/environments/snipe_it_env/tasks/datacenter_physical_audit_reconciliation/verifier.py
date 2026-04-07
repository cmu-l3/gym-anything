#!/usr/bin/env python3
"""Verifier for datacenter_physical_audit_reconciliation task."""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/datacenter_audit_result.json"

def verify_datacenter_physical_audit_reconciliation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env(RESULT_PATH, temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_file.name)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found in VM."}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    score = 0
    feedback = []

    assets = result.get("assets", {})
    loc_a_id = result.get("loc_a_id", "")
    sl_lost_id = result.get("sl_lost_id", "")

    audited_tags = ["SRV-RACKA-01", "SRV-RACKA-02", "SRV-RACKA-03", "SRV-RACKB-99"]
    
    # Do-nothing gate
    if int(result.get("current_audits", 0)) <= int(result.get("initial_audits", 0)):
        b99 = assets.get("SRV-RACKB-99", {})
        a04 = assets.get("SRV-RACKA-04", {})
        if str(b99.get("rtd_location_id")) != str(loc_a_id) and str(a04.get("status_id")) != str(sl_lost_id):
            return {"passed": False, "score": 0, "feedback": "DO-NOTHING: No assets audited, moved, or marked lost."}

    # C1: Audit logs (20 pts)
    c1_score = 0
    for tag in audited_tags:
        if assets.get(tag, {}).get("audit_logged"):
            c1_score += 5
    score += c1_score
    feedback.append(f"C1: {c1_score//5}/4 required assets audited (+{c1_score})")

    # Anti-gaming: A04 audited?
    if assets.get("SRV-RACKA-04", {}).get("audit_logged"):
        score = max(0, score - 10)
        feedback.append("Penalty: SRV-RACKA-04 was audited despite being missing (-10)")

    # C2: Next Audit Date (20 pts)
    c2_score = 0
    for tag in audited_tags:
        date = assets.get(tag, {}).get("next_audit_date", "")
        if date and "2026-09-08" in date:
            c2_score += 5
    score += c2_score
    feedback.append(f"C2: {c2_score//5}/4 audited assets have correct next audit date (+{c2_score})")

    # C3: Audit notes (10 pts)
    c3_score = 0.0
    for tag in audited_tags:
        note = assets.get(tag, {}).get("audit_note", "")
        if note and "Q1 2026 Physical Audit".lower() in note.lower():
            c3_score += 2.5
    c3_score_int = int(c3_score)
    score += c3_score_int
    feedback.append(f"C3: {c3_score_int}/10 points for correct audit notes (+{c3_score_int})")

    # C4: Moved Asset (20 pts)
    b99 = assets.get("SRV-RACKB-99", {})
    if str(b99.get("rtd_location_id")) == str(loc_a_id) or str(b99.get("location_id")) == str(loc_a_id):
        score += 20
        feedback.append("C4: SRV-RACKB-99 successfully moved to Datacenter - Rack A (+20)")
    else:
        feedback.append("C4: SRV-RACKB-99 not moved to Datacenter - Rack A (+0)")

    # C5: Missing Asset Status (20 pts)
    a04 = assets.get("SRV-RACKA-04", {})
    if str(a04.get("status_id")) == str(sl_lost_id):
        score += 20
        feedback.append("C5: SRV-RACKA-04 status set to Lost/Stolen (+20)")
    else:
        feedback.append(f"C5: SRV-RACKA-04 status not set to Lost/Stolen (is {a04.get('status_id')}) (+0)")

    # C6: Missing Asset Note (10 pts)
    a04_notes = a04.get("notes", "")
    if a04_notes and "Not found during Q1 2026 physical audit".lower() in a04_notes.lower():
        score += 10
        feedback.append("C6: SRV-RACKA-04 has correct missing note (+10)")
    else:
        feedback.append("C6: SRV-RACKA-04 missing required note (+0)")

    passed = score >= 70 and (c1_score > 0 or c2_score > 0) and (score >= 30)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }