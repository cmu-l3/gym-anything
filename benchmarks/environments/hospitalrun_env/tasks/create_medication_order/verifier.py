#!/usr/bin/env python3
"""Verifier for create_medication_order task.
Checks CouchDB for a medication document for Aisha Patel containing 'Salbutamol'.
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


def verify_create_medication_order(traj, env_info, task_info):
    """
    Query CouchDB for a medication document where:
      - medication name contains 'Salbutamol'
      - linked to patient Aisha Patel (patient_p1_000005)
    """
    metadata = task_info.get("metadata", {})
    expected_med = metadata.get("medication_name", "Salbutamol")
    expected_patient_id = metadata.get("patient_couch_id", "patient_p1_000005")
    expected_quantity = metadata.get("medication_quantity", "2")
    expected_frequency = metadata.get("medication_frequency", "Every 4-6 hours as needed")

    try:
        all_docs = _couch_get(f"{MAIN_DB}/_all_docs?include_docs=true")
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not reach CouchDB: {e}"}

    rows = all_docs.get("rows", [])
    med_found = False
    patient_linked = False
    found_doc = None

    for row in rows:
        doc = row.get("doc", {})
        d = doc.get("data", doc)
        doc_id = row.get("id", "")
        if doc_id.startswith("_design"):
            continue

        doc_str = json.dumps(doc).lower()
        med_lower = expected_med.lower()

        if med_lower in doc_str or "salbutamol" in doc_str or "albuterol" in doc_str:
            med_found = True
            found_doc = d
            patient_field = d.get("patient", doc.get("patient", ""))
            if expected_patient_id in patient_field or "patel" in doc_str or "p00005" in doc_str:
                patient_linked = True

    if not med_found:
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                f"No medication document containing '{expected_med}' found in CouchDB. "
                "Medication order was not created."
            ),
        }

    if not patient_linked:
        return {
            "passed": True,
            "score": 60,
            "feedback": (
                f"Medication '{expected_med}' found but not clearly linked to "
                f"patient Aisha Patel ({expected_patient_id})."
            ),
        }

    # Check quantity
    issues = []
    if found_doc:
        qty = str(found_doc.get("quantity", found_doc.get("qty", "")))
        if qty and expected_quantity not in qty:
            issues.append(f"Quantity: expected '{expected_quantity}', got '{qty}'")

    if issues:
        return {
            "passed": True,
            "score": 80,
            "feedback": f"Medication '{expected_med}' created for Aisha Patel but with issues: {'; '.join(issues)}",
        }

    return {
        "passed": True,
        "score": 100,
        "feedback": f"Medication order for '{expected_med}' successfully created for Aisha Patel.",
    }
