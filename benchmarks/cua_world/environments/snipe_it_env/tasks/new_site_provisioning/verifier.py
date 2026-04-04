#!/usr/bin/env python3
"""Verifier for new_site_provisioning task.

Scoring breakdown (100 points):
  C1: Chicago Distribution Center location created with correct address (15 pts)
  C2: Logistics department created at Chicago location (10 pts)
  C3: User trivera created with correct details (15 pts)
  C4: ASSET-D001 and ASSET-D002 transferred to Chicago (20 pts)
  C5: Transfer notes added to relocated assets (10 pts)
  C6: ASSET-M002 checked out to Thomas Rivera (15 pts)
  C7: Monitor checkout note present (5 pts)
  C8: Control assets not modified (10 pts)
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/new_site_provisioning_result.json"


def verify_new_site_provisioning(traj, env_info, task_info):
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

    location = result.get("location", {})
    department = result.get("department", {})
    user = result.get("user", {})
    transfers = result.get("asset_transfers", {})
    monitor = result.get("monitor_checkout", {})

    # --- Do-nothing gate ---
    if (not location.get("found") and
        not department.get("found") and
        not user.get("found") and
        not transfers.get("d001_at_chicago") and
        not transfers.get("d002_at_chicago")):
        return {"passed": False, "score": 0,
                "feedback": "DO-NOTHING: No provisioning actions were taken."}

    # --- C1: Chicago location created (15 pts) ---
    if location.get("found"):
        c1_score = 8  # Base for creating location
        city = location.get("city", "").strip()
        state = location.get("state", "").strip()
        if city.lower() == "chicago":
            c1_score += 4
        else:
            feedback.append(f"C1: City is '{city}', expected 'Chicago'")
        if state.upper() in ("IL", "ILLINOIS"):
            c1_score += 3
        else:
            feedback.append(f"C1: State is '{state}', expected 'IL'")
        score += c1_score
        feedback.append(f"C1: Chicago location created (+{c1_score})")
    else:
        feedback.append("C1: Chicago Distribution Center location not found (+0)")

    # --- C2: Logistics department at Chicago (10 pts) ---
    if department.get("found"):
        if department.get("at_chicago"):
            score += 10
            feedback.append("C2: Logistics department created at Chicago location (+10)")
        else:
            score += 5
            feedback.append("C2: Logistics department exists but not at Chicago (+5)")
    else:
        feedback.append("C2: Logistics department not found (+0)")

    # --- C3: User trivera created (15 pts) ---
    if user.get("found"):
        c3_score = 8  # Base for creating user
        email = user.get("email", "").strip()
        if "thomas.rivera@example.com" in email.lower():
            c3_score += 4
        else:
            feedback.append(f"C3: Email is '{email}', expected 'thomas.rivera@example.com'")
        if user.get("at_chicago"):
            c3_score += 3
        else:
            feedback.append("C3: User not assigned to Chicago location")
        score += c3_score
        feedback.append(f"C3: User trivera created (+{c3_score})")
    else:
        feedback.append("C3: User trivera not found (+0)")

    # --- C4: Assets transferred to Chicago (20 pts) ---
    c4_score = 0
    if transfers.get("d001_at_chicago"):
        c4_score += 10
        feedback.append("C4a: ASSET-D001 transferred to Chicago (+10)")
    else:
        feedback.append("C4a: ASSET-D001 not at Chicago (+0)")
    if transfers.get("d002_at_chicago"):
        c4_score += 10
        feedback.append("C4b: ASSET-D002 transferred to Chicago (+10)")
    else:
        feedback.append("C4b: ASSET-D002 not at Chicago (+0)")
    score += c4_score

    # --- C5: Transfer notes (10 pts) ---
    c5_score = 0
    if transfers.get("d001_has_note"):
        c5_score += 5
    else:
        feedback.append("C5: ASSET-D001 missing transfer note")
    if transfers.get("d002_has_note"):
        c5_score += 5
    else:
        feedback.append("C5: ASSET-D002 missing transfer note")
    score += c5_score
    if c5_score > 0:
        feedback.append(f"C5: Transfer notes added (+{c5_score})")

    # --- C6: Monitor checked out to trivera (15 pts) ---
    if monitor.get("checked_out_to_trivera"):
        score += 15
        feedback.append("C6: ASSET-M002 checked out to Thomas Rivera (+15)")
    else:
        feedback.append("C6: ASSET-M002 not checked out to Thomas Rivera (+0)")

    # --- C7: Checkout note (5 pts) ---
    if monitor.get("checkout_note_correct"):
        score += 5
        feedback.append("C7: Monitor checkout note present (+5)")
    else:
        feedback.append("C7: Monitor checkout note missing or incorrect (+0)")

    # --- C8: Control assets unchanged (10 pts) ---
    control_changed = int(result.get("control_assets_changed", 0))
    if control_changed == 0:
        score += 10
        feedback.append("C8: Control assets unchanged (+10)")
    else:
        feedback.append(f"C8: {control_changed} control assets were wrongly modified (+0)")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }
