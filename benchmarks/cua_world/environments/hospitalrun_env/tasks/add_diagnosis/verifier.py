#!/usr/bin/env python3
"""Verifier for add_diagnosis task.
Checks CouchDB for a diagnosis document linked to patient James Okafor
containing 'Type 2 Diabetes Mellitus'.
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


def verify_add_diagnosis(traj, env_info, task_info):
    """
    Query CouchDB for a diagnosis document where:
      - diagnosisDescription (or similar field) contains 'Type 2 Diabetes Mellitus'
      - linked to patient James Okafor (patient_p1_000002)

    HospitalRun stores diagnoses as separate docs of type 'diagnosis' or embedded in
    visit documents. Search all docs for the diagnosis string.
    """
    metadata = task_info.get("metadata", {})
    expected_diagnosis = metadata.get("diagnosis_name", "Type 2 Diabetes Mellitus")
    expected_patient_id = metadata.get("patient_couch_id", "patient_p1_000002")

    try:
        all_docs = _couch_get(f"{MAIN_DB}/_all_docs?include_docs=true")
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not reach CouchDB: {e}"}

    rows = all_docs.get("rows", [])
    diagnosis_found = False
    patient_linked = False

    for row in rows:
        doc = row.get("doc", {})
        d = doc.get("data", doc)
        doc_id = row.get("id", "")
        if doc_id.startswith("_design"):
            continue

        # Convert doc to string to do a broad search for the diagnosis name
        doc_str = json.dumps(doc).lower()
        diag_lower = expected_diagnosis.lower()

        if diag_lower in doc_str or "diabetes mellitus" in doc_str:
            diagnosis_found = True
            # Check if this doc or visit is linked to James Okafor
            patient_field = d.get("patient", doc.get("patient", ""))
            if expected_patient_id in patient_field or "okafor" in doc_str or "p00002" in doc_str:
                patient_linked = True

    if not diagnosis_found:
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                f"No document containing diagnosis '{expected_diagnosis}' found in CouchDB. "
                "Diagnosis was not added."
            ),
        }

    if not patient_linked:
        return {
            "passed": True,
            "score": 60,
            "feedback": (
                f"Diagnosis '{expected_diagnosis}' found but not clearly linked to "
                f"patient James Okafor ({expected_patient_id})."
            ),
        }

    return {
        "passed": True,
        "score": 100,
        "feedback": f"Diagnosis '{expected_diagnosis}' successfully added for patient James Okafor.",
    }
