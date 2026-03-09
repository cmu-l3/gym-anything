#!/usr/bin/env python3
"""Verifier for add_pilot task.
Checks that a new Person 'Aditya Kumar' and corresponding Pilot record
were added to the Aerobridge registry.
"""

import json


def verify_add_pilot(traj, env_info, task_info):
    """Verify that pilot 'Aditya Kumar' was successfully added."""

    result_path = "/tmp/add_pilot_result.json"
    score = 0
    feedback_parts = []

    try:
        with open(result_path) as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result file: {e}"}

    person = data.get("person")
    pilot = data.get("pilot")
    count_before = int(data.get("count_before", 0))
    current_count = int(data.get("current_count", 0))

    # ── Check 1: Person exists (30 points) ───────────────────────────────────
    if person is None:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Person 'Aditya Kumar' was not found in the registry."
        }

    score += 30
    feedback_parts.append("✓ Person record found in registry (+30)")

    # ── Check 2: First name (15 points) ──────────────────────────────────────
    first_name = (person.get("first_name") or "").strip()
    if first_name.lower() == "aditya":
        score += 15
        feedback_parts.append("✓ First name 'Aditya' correct (+15)")
    else:
        feedback_parts.append(f"✗ First name mismatch: expected 'Aditya', got '{first_name}'")

    # ── Check 3: Last name (15 points) ───────────────────────────────────────
    last_name = (person.get("last_name") or "").strip()
    if last_name.lower() == "kumar":
        score += 15
        feedback_parts.append("✓ Last name 'Kumar' correct (+15)")
    else:
        feedback_parts.append(f"✗ Last name mismatch: expected 'Kumar', got '{last_name}'")

    # ── Check 4: Email (15 points) ───────────────────────────────────────────
    email = (person.get("email") or "").strip().lower()
    if email == "aditya.kumar@droneops.in":
        score += 15
        feedback_parts.append("✓ Email 'aditya.kumar@droneops.in' correct (+15)")
    else:
        feedback_parts.append(
            f"✗ Email mismatch: expected 'aditya.kumar@droneops.in', got '{email}'"
        )

    # ── Check 5: Pilot record exists linking this Person (25 points) ─────────
    if pilot is not None:
        score += 25
        feedback_parts.append("✓ Pilot record linked to Person found (+25)")
    else:
        feedback_parts.append(
            "✗ No Pilot record found for this Person — the Pilot form must be saved, "
            "not just the Person popup. The task requires creating a full Pilot record."
        )

    # ── Check 6: Count increased ──────────────────────────────────────────────
    if current_count > count_before:
        feedback_parts.append(f"✓ Person count increased: {count_before} → {current_count}")
    else:
        feedback_parts.append(f"Note: Person count: {count_before} → {current_count}")

    passed = score >= 60
    feedback = "\n".join(feedback_parts)
    feedback += f"\n\nTotal score: {score}/100"

    return {"passed": passed, "score": score, "feedback": feedback}
