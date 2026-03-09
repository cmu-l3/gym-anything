#!/usr/bin/env python3
"""Verifier for stolen_device_incident_response task.

Scoring breakdown (100 points):
  C1: Stolen laptop checked in from David Kim (15 pts)
  C2: Stolen laptop status changed to Lost/Stolen (15 pts)
  C3: Stolen laptop notes contain incident reference SI-2025-0042 (10 pts)
  C4: Replacement ASSET-L009 checked out to David Kim (20 pts)
  C5: Replacement checkout note references SI-2025-0042 (10 pts)
  C6: Insurance claim asset ASSET-L012 created (15 pts)
  C7: Insurance asset has correct details (serial, status=Pending) (10 pts)
  C8: Control asset ASSET-L001 unchanged — wrong-target gate (5 pts)
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/stolen_device_incident_response_result.json"


def verify_stolen_device_incident_response(traj, env_info, task_info):
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

    stolen = result.get("stolen_asset", {})
    replacement = result.get("replacement_asset", {})
    insurance = result.get("insurance_asset", {})

    # --- Do-nothing gate ---
    if (not stolen.get("checked_in") and
        not stolen.get("is_lost_stolen") and
        not replacement.get("checked_out_to_dkim") and
        not insurance.get("found")):
        return {"passed": False, "score": 0,
                "feedback": "DO-NOTHING: No incident response actions were taken."}

    # --- C1: Stolen laptop checked in (15 pts) ---
    if stolen.get("checked_in"):
        score += 15
        feedback.append("C1: Stolen laptop successfully checked in (+15)")
    else:
        feedback.append("C1: Stolen laptop still checked out (+0)")

    # --- C2: Status changed to Lost/Stolen (15 pts) ---
    if stolen.get("is_lost_stolen"):
        score += 15
        feedback.append("C2: Stolen laptop status set to Lost/Stolen (+15)")
    else:
        feedback.append(f"C2: Stolen laptop status is '{stolen.get('status_name', 'unknown')}', expected 'Lost/Stolen' (+0)")

    # --- C3: Incident note on stolen laptop (10 pts) ---
    if stolen.get("has_incident_note"):
        score += 10
        feedback.append("C3: Stolen laptop notes reference SI-2025-0042 (+10)")
    else:
        feedback.append("C3: Stolen laptop notes missing incident reference (+0)")

    # --- C4: Replacement checked out to David Kim (20 pts) ---
    if replacement.get("checked_out_to_dkim"):
        score += 20
        feedback.append("C4: ASSET-L009 checked out to David Kim (+20)")
    else:
        feedback.append("C4: ASSET-L009 not checked out to David Kim (+0)")

    # --- C5: Replacement checkout note (10 pts) ---
    if replacement.get("note_has_incident"):
        score += 10
        feedback.append("C5: Replacement checkout note references SI-2025-0042 (+10)")
    else:
        feedback.append("C5: Replacement checkout note missing incident reference (+0)")

    # --- C6: Insurance asset created (15 pts) ---
    if insurance.get("found"):
        score += 15
        feedback.append("C6: Insurance claim asset ASSET-L012 created (+15)")
    else:
        feedback.append("C6: Insurance claim asset ASSET-L012 not found (+0)")

    # --- C7: Insurance asset correct details (10 pts) ---
    c7_score = 0
    if insurance.get("found"):
        serial = insurance.get("serial", "")
        if "INSURANCE-CLAIM-SI-2025-0042" in serial:
            c7_score += 5
            feedback.append("C7a: Insurance asset serial correct (+5)")
        else:
            feedback.append(f"C7a: Insurance serial '{serial}', expected 'INSURANCE-CLAIM-SI-2025-0042' (+0)")

        status = insurance.get("status", "")
        if status == "Pending":
            c7_score += 5
            feedback.append("C7b: Insurance asset status is Pending (+5)")
        else:
            feedback.append(f"C7b: Insurance status '{status}', expected 'Pending' (+0)")
    else:
        feedback.append("C7: Insurance asset not found, skipping detail checks (+0)")
    score += c7_score

    # --- C8: Control asset unchanged — wrong-target gate (5 pts) ---
    if result.get("control_asset_unchanged"):
        score += 5
        feedback.append("C8: Control asset ASSET-L001 unchanged (+5)")
    else:
        # Wrong-target penalty: cap score
        score = min(score, 40)
        feedback.append("C8: WRONG TARGET - Control asset ASSET-L001 was modified! Score capped at 40.")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }
