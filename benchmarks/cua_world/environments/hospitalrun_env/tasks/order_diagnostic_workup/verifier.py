#!/usr/bin/env python3
"""Verifier for order_diagnostic_workup task.

Elena Petrov (patient_p1_000011) must have:
  1. At least 2 laboratory test orders linked to her         — 40 points (20 each, up to 2)
  2. At least 1 imaging study order linked to her            — 40 points
  3. Correct patient confirmed (not wrong record)            — 20 points

Pass threshold: 60 points (labs + correct patient, OR imaging + correct patient + partial lab).
"""
import json
import logging

logger = logging.getLogger(__name__)

EXPECTED_PATIENT_ID = "patient_p1_000011"
EXPECTED_VISIT_ID   = "visit_p1_000011"
LAB_KEYWORDS        = [
    "lab", "tsh", "t4", "t3", "thyroid", "metabolic", "cbc", "panel",
    "blood", "chemistry", "hemoglobin", "glucose", "creatinine", "lipid",
    "hematology", "biochemistry", "urine", "culture", "complete blood",
    "antibod", "serum"
]
IMAGING_KEYWORDS    = [
    "ultrasound", "sonogram", "scan", "mri", "ct", "x-ray", "xray",
    "imaging", "iodine", "scintigraphy", "echo", "radiograph", "nuclear"
]
# Document types that HospitalRun uses for lab/imaging
LAB_DOC_TYPES    = ["lab", "lab-request", "labrequest", "labs"]
IMAGING_DOC_TYPES = ["imaging", "imaging-request", "imagingrequest"]
EXCLUDE_TYPES    = ["patient", "visit", "vitals", "diagnosis", "medication", "appointment"]
# Exclude the patient and visit base documents — they contain clinical keywords
# (e.g. "thyroid" in reasonForVisit) and must not be counted as orders.
EXCLUDE_IDS      = {"patient_p1_000011", "visit_p1_000011"}


def _exec(exec_capture, cmd):
    try:
        return exec_capture(cmd)
    except Exception as e:
        logger.warning(f"exec_capture failed: {e}")
        return ""


def _load_all_docs(exec_capture):
    raw = _exec(
        exec_capture,
        "curl -s 'http://couchadmin:test@localhost:5984/main/_all_docs?include_docs=true'"
    )
    try:
        return json.loads(raw).get("rows", [])
    except Exception:
        return []


def _linked_to_petrov(doc):
    d       = doc.get("data", doc)
    doc_str = json.dumps(doc).lower()
    return (
        EXPECTED_PATIENT_ID in d.get("patient", "")
        or EXPECTED_PATIENT_ID in doc.get("patient", "")
        or EXPECTED_VISIT_ID  in d.get("visit", "")
        or EXPECTED_VISIT_ID  in doc.get("visit", "")
        or "petrov" in doc_str
        or "p00011" in doc_str
    )


def verify_order_diagnostic_workup(traj, env_info, task_info):
    """
    Scoring (100 points total):
      - First lab order found and linked to Elena Petrov   : 20 pts
      - Second lab order found and linked to Elena Petrov  : 20 pts
      - Imaging order found and linked to Elena Petrov     : 40 pts
      - Correct patient bonus (patient exists, not wrong target) : 20 pts
    Pass threshold: 60 points
    """
    exec_capture = env_info.get("exec_capture")
    metadata     = task_info.get("metadata", {})
    expected_pid = metadata.get("patient_couch_id", EXPECTED_PATIENT_ID)

    if not exec_capture:
        return {"passed": False, "score": 0,
                "feedback": "exec_capture not available; cannot query CouchDB"}

    # Verify correct patient exists
    patient_raw = _exec(
        exec_capture,
        f"curl -s 'http://couchadmin:test@localhost:5984/main/{expected_pid}'"
    )
    try:
        patient_doc = json.loads(patient_raw)
        d = patient_doc.get("data", patient_doc)
        if d.get("lastName", "").lower() != "petrov" and d.get("firstName", "").lower() != "elena":
            return {
                "passed": False, "score": 0,
                "feedback": f"Wrong patient! Expected Elena Petrov (patient_p1_000011)"
            }
    except Exception:
        pass  # Continue — patient existence confirmed by other means

    rows = _load_all_docs(exec_capture)
    if not rows:
        return {"passed": False, "score": 0, "feedback": "Could not reach CouchDB or no documents found"}

    score = 0
    feedback_parts = []
    subscores = {}

    # Patient bonus (she exists and is in the system)
    score += 20
    subscores["correct_patient"] = 20
    feedback_parts.append("Correct patient Elena Petrov confirmed")

    # ── Scan for lab and imaging docs ──────────────────────────────────────────
    lab_docs     = []
    imaging_docs = []

    for row in rows:
        doc    = row.get("doc", {})
        doc_id = row.get("id", "")
        if doc_id.startswith("_design"):
            continue
        if doc_id in EXCLUDE_IDS:
            continue
        if not _linked_to_petrov(doc):
            continue
        d        = doc.get("data", doc)
        doc_str  = json.dumps(doc).lower()
        doc_type = (d.get("type") or doc.get("type") or "").lower()

        if doc_type in EXCLUDE_TYPES:
            continue

        # Classify document
        is_lab = (
            doc_type in LAB_DOC_TYPES
            or any(kw in doc_str for kw in LAB_KEYWORDS)
        )
        is_imaging = (
            doc_type in IMAGING_DOC_TYPES
            or any(kw in doc_str for kw in IMAGING_KEYWORDS)
        )

        # Prefer doc_type classification; break tie by first match
        if doc_type in LAB_DOC_TYPES:
            lab_docs.append(doc)
        elif doc_type in IMAGING_DOC_TYPES:
            imaging_docs.append(doc)
        elif is_imaging and not is_lab:
            imaging_docs.append(doc)
        elif is_lab:
            lab_docs.append(doc)

    # ── Subtask 1 + 2: Lab orders ──────────────────────────────────────────────
    lab_found = len(lab_docs)
    if lab_found >= 2:
        score += 40
        subscores["lab_orders"] = 40
        feedback_parts.append(f"{lab_found} lab order(s) found for Elena Petrov")
    elif lab_found == 1:
        score += 20
        subscores["lab_orders"] = 20
        feedback_parts.append("1 lab order found for Elena Petrov (need ≥2 for full credit)")
    else:
        subscores["lab_orders"] = 0
        feedback_parts.append("No lab orders found for Elena Petrov")

    # ── Subtask 3: Imaging order ───────────────────────────────────────────────
    imaging_found = len(imaging_docs)
    if imaging_found >= 1:
        score += 40
        subscores["imaging_orders"] = 40
        feedback_parts.append(f"{imaging_found} imaging order(s) found for Elena Petrov")
    else:
        subscores["imaging_orders"] = 0
        feedback_parts.append("No imaging orders found for Elena Petrov")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) or "No orders placed",
        "subscores": subscores,
    }
