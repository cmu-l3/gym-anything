#!/usr/bin/env python3
"""
Verifier: oc_tb_contact_trace — TB Contact Tracing

Reads /tmp/oc_tb_contact_trace_result.json written by export_result.sh.

Three TB contacts must each be: registered, given a MALAR lab order, and
scheduled for a follow-up appointment.

Contacts:
  - Kofi Asante        (M, 1988-07-22, GH)
  - Rania Aziz         (F, 1975-03-10, EG)
  - Dimitri Papadopoulos (M, 1962-11-30, GR)

Scoring (100 pts — 3 contacts x ~33 pts each):
  Per contact (~33 pts):
    - Registered as patient (11 pts)
    - MALAR lab test ordered (11 pts)
    - Follow-up appointment scheduled (11 pts)
  (Total is 99; Kofi gets 11+11+12=34 to reach 100)

Pass threshold: 60 / 100 (at least 2 contacts fully processed)
Do-nothing: 0/100 (none of the 3 contacts exist), passed=False
"""

import json
import os
import tempfile


RESULT_FILE_IN_VM = "/tmp/oc_tb_contact_trace_result.json"

CONTACTS = [
    {"key": "kofi",    "firstname": "KOFI",    "lastname": "ASANTE",
     "dob": "1988-07-22", "reg_pts": 11, "lab_pts": 11, "appt_pts": 12},
    {"key": "rania",   "firstname": "RANIA",   "lastname": "AZIZ",
     "dob": "1975-03-10", "reg_pts": 11, "lab_pts": 11, "appt_pts": 11},
    {"key": "dimitri", "firstname": "DIMITRI", "lastname": "PAPADOPOULOS",
     "dob": "1962-11-30", "reg_pts": 11, "lab_pts": 11, "appt_pts": 11},
]


def verify_oc_tb_contact_trace(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0,
                "feedback": "copy_from_env not available"}

    with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
        tmp_path = tmp.name
    try:
        copy_from_env(RESULT_FILE_IN_VM, tmp_path)
        with open(tmp_path, "r") as f:
            result = json.load(f)
    except (FileNotFoundError, OSError):
        return {"passed": False, "score": 0,
                "feedback": "Result file not found — export_result.sh may not have run"}
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0,
                "feedback": f"Result JSON is malformed: {e}"}
    finally:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)

    score = 0
    criteria = {}
    contacts_complete = 0

    for contact in CONTACTS:
        key = contact["key"]
        fname = contact["firstname"]
        lname = contact["lastname"]
        expected_dob = contact["dob"]

        contact_criteria = {}
        contact_score = 0
        contact_fully_done = True

        pid = result.get(f"{key}_pid")
        dob = result.get(f"{key}_dob") or ""
        malar = result.get(f"{key}_malar", 0)
        appt = result.get(f"{key}_appt", 0)

        # ---- Step (a): Registration ----
        if pid is not None:
            dob_ok = expected_dob in dob
            if dob_ok:
                pts = contact["reg_pts"]
                score += pts
                contact_score += pts
                contact_criteria["registered"] = {
                    "passed": True, "points": pts,
                    "detail": f"{fname} {lname} registered (ID={pid}, DOB verified)"
                }
            else:
                # Partial: found but DOB wrong
                pts = contact["reg_pts"] // 2
                score += pts
                contact_score += pts
                contact_fully_done = False
                contact_criteria["registered"] = {
                    "passed": False, "points": pts,
                    "detail": f"{fname} {lname} registered (ID={pid}) but DOB mismatch: got '{dob}', expected '{expected_dob}'"
                }
        else:
            contact_fully_done = False
            contact_criteria["registered"] = {
                "passed": False, "points": 0,
                "detail": f"{fname} {lname} NOT found in patient registry"
            }

        # ---- Step (b): MALAR lab ordered ----
        if pid is not None:
            lab_ok = malar >= 1
            if lab_ok:
                pts = contact["lab_pts"]
                score += pts
                contact_score += pts
                contact_criteria["malar_ordered"] = {
                    "passed": True, "points": pts,
                    "detail": f"MALAR (TB AFB smear) ordered for {fname} {lname}"
                }
            else:
                contact_fully_done = False
                contact_criteria["malar_ordered"] = {
                    "passed": False, "points": 0,
                    "detail": f"MALAR lab test NOT ordered for {fname} {lname}"
                }
        else:
            contact_fully_done = False
            contact_criteria["malar_ordered"] = {
                "passed": False, "points": 0,
                "detail": f"Cannot check lab — {fname} {lname} not registered"
            }

        # ---- Step (c): Follow-up appointment scheduled ----
        if pid is not None:
            appt_ok = appt >= 1
            if appt_ok:
                pts = contact["appt_pts"]
                score += pts
                contact_score += pts
                contact_criteria["followup_scheduled"] = {
                    "passed": True, "points": pts,
                    "detail": f"Follow-up appointment scheduled for {fname} {lname}"
                }
            else:
                contact_fully_done = False
                contact_criteria["followup_scheduled"] = {
                    "passed": False, "points": 0,
                    "detail": f"No follow-up appointment found for {fname} {lname}"
                }
        else:
            contact_fully_done = False
            contact_criteria["followup_scheduled"] = {
                "passed": False, "points": 0,
                "detail": f"Cannot check appointment — {fname} {lname} not registered"
            }

        if contact_fully_done:
            contacts_complete += 1

        criteria[key] = {
            "patient": f"{fname} {lname}",
            "score": contact_score,
            "fully_complete": contact_fully_done,
            "checks": contact_criteria,
        }

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": {
            "total_score": score,
            "pass_threshold": 60,
            "contacts_fully_processed": contacts_complete,
            "criteria": criteria,
            "summary": (
                f"{contacts_complete}/3 TB contacts fully processed "
                f"(registered + lab ordered + follow-up scheduled)."
            )
        }
    }
