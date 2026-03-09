#!/usr/bin/env python3
"""Verifier for warranty_audit_remediation task.

Scoring breakdown (100 points):
  C1: Correct expired-warranty assets identified and changed to Pending (30 pts)
  C2: Notes contain 'WARRANTY EXPIRED' on correct assets (20 pts)
  C3: Active-warranty asset W004 NOT modified (20 pts)
  C4: No false positives — active-warranty assets left unchanged (15 pts)
  C5: Retired asset (ASSET-L010) not modified (15 pts)
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/warranty_audit_remediation_result.json"


def verify_warranty_audit_remediation(traj, env_info, task_info):
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

    injected = result.get("injected_assets", {})

    # --- Do-nothing gate (check FIRST) ---
    expired_tags = ["W001", "W002", "W003", "W005"]
    any_expired_changed = False
    for tag in expired_tags:
        asset = injected.get(tag, {})
        if asset.get("found") and asset.get("status_name") == "Pending":
            any_expired_changed = True
            break
        if asset.get("found") and "WARRANTY EXPIRED" in asset.get("notes", "").upper():
            any_expired_changed = True
            break
    if not any_expired_changed:
        return {"passed": False, "score": 0,
                "feedback": "DO-NOTHING: No expired-warranty assets were changed."}

    # --- C1: Correct expired-warranty assets changed to Pending (30 pts) ---
    expired_correct = 0
    for tag in expired_tags:
        asset = injected.get(tag, {})
        if asset.get("found") and asset.get("status_name") == "Pending":
            expired_correct += 1
        else:
            status = asset.get("status_name", "unknown")
            feedback.append(f"C1: {tag} status is '{status}', expected 'Pending'")

    if expired_correct == len(expired_tags):
        score += 30
        feedback.append("C1: All 4 expired-warranty assets correctly set to Pending (+30)")
    elif expired_correct > 0:
        partial = int(30 * expired_correct / len(expired_tags))
        score += partial
        feedback.append(f"C1: {expired_correct}/{len(expired_tags)} expired assets set to Pending (+{partial})")
    else:
        feedback.append("C1: No expired-warranty assets changed to Pending (+0)")

    # --- C2: Notes contain 'WARRANTY EXPIRED' (20 pts) ---
    note_correct = 0
    for tag in expired_tags:
        asset = injected.get(tag, {})
        notes = asset.get("notes", "")
        if "WARRANTY EXPIRED" in notes.upper():
            note_correct += 1
        else:
            feedback.append(f"C2: {tag} notes missing 'WARRANTY EXPIRED'")

    if note_correct == len(expired_tags):
        score += 20
        feedback.append("C2: All 4 expired assets have WARRANTY EXPIRED note (+20)")
    elif note_correct > 0:
        partial = int(20 * note_correct / len(expired_tags))
        score += partial
        feedback.append(f"C2: {note_correct}/{len(expired_tags)} expired assets have note (+{partial})")
    else:
        feedback.append("C2: No expired assets have WARRANTY EXPIRED note (+0)")

    # --- C3: Active-warranty asset W004 NOT modified (20 pts) ---
    w004 = injected.get("W004", {})
    if w004.get("found"):
        w004_status = w004.get("status_name", "")
        w004_notes = w004.get("notes", "")
        if w004_status != "Pending" and "WARRANTY EXPIRED" not in w004_notes.upper():
            score += 20
            feedback.append("C3: Active-warranty asset W004 correctly left unchanged (+20)")
        else:
            feedback.append(f"C3: Active-warranty asset W004 was wrongly modified (status={w004_status}) (+0)")
    else:
        feedback.append("C3: Asset W004 not found (+0)")

    # --- C4: No false positives (15 pts) ---
    false_positives = int(result.get("false_positive_count", 0))
    if false_positives == 0:
        score += 15
        feedback.append("C4: No false positives — only expired assets modified (+15)")
    else:
        feedback.append(f"C4: {false_positives} active-warranty assets wrongly set to Pending (+0)")

    # --- C5: Retired asset not modified (15 pts) ---
    retired_status = result.get("retired_current_status", "")
    if retired_status == "Retired":
        score += 15
        feedback.append("C5: Retired asset ASSET-L010 correctly left unchanged (+15)")
    else:
        feedback.append(f"C5: Retired asset ASSET-L010 status changed to '{retired_status}' (+0)")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }
