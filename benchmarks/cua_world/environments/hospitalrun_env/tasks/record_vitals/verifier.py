#!/usr/bin/env python3
"""Verifier for record_vitals task.
Checks CouchDB for a vitals document linked to Harold Whitmore's visit
with the expected vital measurements.
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


def _val_close(actual, expected_str, tolerance=5):
    """Check if actual value is within tolerance of expected (numeric comparison)."""
    try:
        exp = float(expected_str)
        act = float(str(actual).replace(",", ""))
        return abs(act - exp) <= tolerance
    except (ValueError, TypeError):
        return str(actual) == expected_str


def verify_record_vitals(traj, env_info, task_info):
    """
    Query CouchDB for a vitals document where:
      - linked to patient Harold Whitmore (patient_p1_000004) or visit (visit_p1_000004)
      - contains key vital fields: weight (~82), height (~175), BP systolic (~145),
        BP diastolic (~92), heart rate (~88)

    HospitalRun stores vitals as separate 'vitals' documents.
    """
    metadata = task_info.get("metadata", {})
    expected_patient_id = metadata.get("patient_couch_id", "patient_p1_000004")
    expected_visit_id = metadata.get("visit_couch_id", "visit_p1_000004")
    expected_weight = metadata.get("weight_kg", "82")
    expected_height = metadata.get("height_cm", "175")
    expected_bp_sys = metadata.get("bp_systolic", "145")
    expected_bp_dia = metadata.get("bp_diastolic", "92")
    expected_hr = metadata.get("heart_rate", "88")
    expected_rr = metadata.get("respiratory_rate", "18")
    expected_temp = metadata.get("temperature_celsius", "37.1")
    expected_o2 = metadata.get("o2_saturation", "94")

    try:
        all_docs = _couch_get(f"{MAIN_DB}/_all_docs?include_docs=true")
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not reach CouchDB: {e}"}

    rows = all_docs.get("rows", [])
    vitals_candidates = []

    for row in rows:
        doc = row.get("doc", {})
        d = doc.get("data", doc)
        doc_id = row.get("id", "")
        if doc_id.startswith("_design"):
            continue

        doc_str = json.dumps(doc).lower()

        # Identify vitals documents: either type='vitals' or contain vital field names
        doc_type = d.get("type", doc.get("type", ""))
        has_vitals_fields = any(
            field in doc_str
            for field in ["weight", "height", "systolic", "diastolic", "heartrate", "heart_rate",
                          "temperature", "o2sat", "o2saturation", "spo2"]
        )

        patient_ref = d.get("patient", doc.get("patient", ""))
        visit_ref = d.get("visit", doc.get("visit", ""))

        linked_to_patient = (
            expected_patient_id in patient_ref
            or expected_patient_id in visit_ref
            or "whitmore" in doc_str
            or "p00004" in doc_str
            or expected_visit_id in patient_ref
            or expected_visit_id in visit_ref
        )

        if has_vitals_fields and linked_to_patient:
            vitals_candidates.append(d)
        elif has_vitals_fields and "whitmore" in doc_str:
            vitals_candidates.append(d)

    if not vitals_candidates:
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                "No vitals document linked to Harold Whitmore (patient_p1_000004) found in CouchDB. "
                "Vitals were not recorded."
            ),
        }

    # Check the best candidate
    v = vitals_candidates[0]
    v_str = json.dumps(v)
    checks_passed = 0
    total_checks = 5
    issues = []

    # Weight check (may be stored as 'weight', 'weightKg', etc.)
    weight_val = v.get("weight", v.get("weightKg", v.get("Weight", None)))
    if weight_val is not None:
        if _val_close(weight_val, expected_weight, tolerance=2):
            checks_passed += 1
        else:
            issues.append(f"Weight: expected ~{expected_weight}kg, got {weight_val}")
    elif expected_weight in v_str:
        checks_passed += 1

    # Height check
    height_val = v.get("height", v.get("heightCm", v.get("Height", None)))
    if height_val is not None:
        if _val_close(height_val, expected_height, tolerance=2):
            checks_passed += 1
        else:
            issues.append(f"Height: expected ~{expected_height}cm, got {height_val}")
    elif expected_height in v_str:
        checks_passed += 1

    # Systolic BP
    sys_val = v.get("systolic", v.get("bpSystolic", v.get("bloodPressureSystolic", None)))
    if sys_val is not None:
        if _val_close(sys_val, expected_bp_sys, tolerance=5):
            checks_passed += 1
        else:
            issues.append(f"Systolic BP: expected ~{expected_bp_sys}, got {sys_val}")
    elif expected_bp_sys in v_str:
        checks_passed += 1

    # Diastolic BP
    dia_val = v.get("diastolic", v.get("bpDiastolic", v.get("bloodPressureDiastolic", None)))
    if dia_val is not None:
        if _val_close(dia_val, expected_bp_dia, tolerance=5):
            checks_passed += 1
        else:
            issues.append(f"Diastolic BP: expected ~{expected_bp_dia}, got {dia_val}")
    elif expected_bp_dia in v_str:
        checks_passed += 1

    # Heart rate
    hr_val = v.get("heartRate", v.get("pulse", v.get("hr", None)))
    if hr_val is not None:
        if _val_close(hr_val, expected_hr, tolerance=5):
            checks_passed += 1
        else:
            issues.append(f"Heart rate: expected ~{expected_hr}, got {hr_val}")
    elif expected_hr in v_str:
        checks_passed += 1

    score = int((checks_passed / total_checks) * 100)

    if checks_passed == 0:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Vitals document found for Harold Whitmore but no expected values matched. Issues: {'; '.join(issues)}",
        }

    if issues:
        return {
            "passed": checks_passed >= 3,
            "score": score,
            "feedback": f"Vitals recorded ({checks_passed}/{total_checks} fields correct). Issues: {'; '.join(issues)}",
        }

    return {
        "passed": True,
        "score": 100,
        "feedback": "All vital signs recorded correctly for Harold Whitmore.",
    }
