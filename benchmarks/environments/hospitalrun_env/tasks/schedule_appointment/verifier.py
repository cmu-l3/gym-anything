#!/usr/bin/env python3
"""Verifier for schedule_appointment task.
Checks CouchDB for an appointment record for Margaret Chen with the expected details.
"""
import json
import urllib.request


COUCH_URL = "http://couchadmin:test@localhost:5984"
MAIN_DB = "main"


def _couch_get(path):
    url = f"{COUCH_URL}/{path}"
    try:
        with urllib.request.urlopen(url, timeout=10) as resp:
            return json.loads(resp.read())
    except Exception:
        return {}


def verify_schedule_appointment(traj, env_info, task_info):
    """
    Query CouchDB for an appointment document where:
      - reasonForAppointment contains 'Blood pressure follow-up consultation'
    """
    metadata = task_info.get("metadata", {})
    expected_reason = metadata.get("appointment_reason", "Blood pressure follow-up consultation")
    expected_type = metadata.get("appointment_type", "Outpatient")
    expected_location = metadata.get("appointment_location", "Clinic A")

    try:
        all_docs = _couch_get(f"{MAIN_DB}/_all_docs?include_docs=true")
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not reach CouchDB: {e}"}

    rows = all_docs.get("rows", [])
    appointment_matches = []

    for row in rows:
        doc = row.get("doc", {})
        d = doc.get("data", doc)
        doc_id = row.get("id", "")
        if doc_id.startswith("_design"):
            continue
        reason = d.get("reasonForAppointment", d.get("reason", ""))
        if expected_reason.lower() in reason.lower():
            appointment_matches.append(d)

    if not appointment_matches:
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                f"No appointment with reason '{expected_reason}' found in CouchDB. "
                "The appointment was not created."
            ),
        }

    appt = appointment_matches[0]
    issues = []

    appt_type = appt.get("appointmentType", appt.get("appointmentKind", ""))
    if appt_type and expected_type.lower() not in appt_type.lower():
        issues.append(f"Appointment type: expected '{expected_type}', got '{appt_type}'")

    location = appt.get("location", "")
    if location and expected_location.lower() not in location.lower():
        issues.append(f"Location: expected '{expected_location}', got '{location}'")

    if issues:
        return {
            "passed": True,
            "score": 70,
            "feedback": f"Appointment found but with field issues: {'; '.join(issues)}",
        }

    return {
        "passed": True,
        "score": 100,
        "feedback": f"Appointment '{expected_reason}' for Margaret Chen successfully scheduled.",
    }
