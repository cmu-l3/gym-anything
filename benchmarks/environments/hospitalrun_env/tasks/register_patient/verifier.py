#!/usr/bin/env python3
"""Verifier for register_patient task.
Checks CouchDB to confirm a patient named Samuel Oduya was created.
"""
import json
import urllib.request
import urllib.error


COUCH_URL = "http://couchadmin:test@localhost:5984"
MAIN_DB = "main"


def _couch_get(path):
    url = f"{COUCH_URL}/{path}"
    try:
        with urllib.request.urlopen(url, timeout=10) as resp:
            return json.loads(resp.read())
    except Exception:
        return {}


def verify_register_patient(traj, env_info, task_info):
    """
    Query CouchDB main database for a patient record matching:
      - firstName: Samuel
      - lastName: Oduya
    The record must exist (created by the agent via the HospitalRun UI).
    """
    metadata = task_info.get("metadata", {})
    expected_first = metadata.get("expected_first_name", "Samuel")
    expected_last = metadata.get("expected_last_name", "Oduya")
    expected_sex = metadata.get("expected_sex", "Male")
    expected_blood_type = metadata.get("expected_blood_type", "B+")

    try:
        all_docs = _couch_get(f"{MAIN_DB}/_all_docs?include_docs=true")
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not reach CouchDB: {e}"}

    rows = all_docs.get("rows", [])
    matches = []
    for row in rows:
        doc = row.get("doc", {})
        # HospitalRun stores patient fields either at top level or inside 'data' wrapper
        d = doc.get("data", doc)
        first = d.get("firstName", "")
        last = d.get("lastName", "")
        if first.lower() == expected_first.lower() and last.lower() == expected_last.lower():
            matches.append(d)

    if not matches:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"No patient named '{expected_first} {expected_last}' found in CouchDB. Patient was not registered.",
        }

    # Check the best match for additional fields
    patient = matches[0]
    issues = []

    sex = patient.get("sex", "")
    if sex and sex.lower() != expected_sex.lower():
        issues.append(f"Sex mismatch: expected '{expected_sex}', got '{sex}'")

    blood_type = patient.get("bloodType", "")
    if blood_type and blood_type.replace(" ", "") != expected_blood_type.replace(" ", ""):
        issues.append(f"Blood type mismatch: expected '{expected_blood_type}', got '{blood_type}'")

    dob = patient.get("dateOfBirth", "")
    # Accept multiple date formats: 1988-04-16, 04/16/1988
    expected_dob = metadata.get("expected_dob", "1988-04-16")
    dob_ok = (
        expected_dob in dob
        or "04/16/1988" in dob
        or "1988" in dob
    )
    if dob and not dob_ok:
        issues.append(f"Date of birth mismatch: expected around '{expected_dob}', got '{dob}'")

    if issues:
        return {
            "passed": True,
            "score": 70,
            "feedback": f"Patient '{expected_first} {expected_last}' found but with field issues: {'; '.join(issues)}",
        }

    return {
        "passed": True,
        "score": 100,
        "feedback": f"Patient '{expected_first} {expected_last}' successfully registered in HospitalRun.",
    }
