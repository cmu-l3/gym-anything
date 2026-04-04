#!/usr/bin/env python3
"""Verifier for register_aircraft task.
Checks that a new aircraft named 'Phoenix Mk3' was added to the Aerobridge registry.
Aircraft model confirmed fields: id, name, operator, manufacturer, status, created_at
"""

import json


def verify_register_aircraft(traj, env_info, task_info):
    """Verify that aircraft 'Phoenix Mk3' was successfully registered."""

    result_path = "/tmp/register_aircraft_result.json"
    score = 0
    feedback_parts = []

    # ── Load exported result ──────────────────────────────────────────────────
    try:
        with open(result_path) as f:
            data = json.load(f)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not read result file: {e}"
        }

    aircraft = data.get("aircraft")
    count_before = int(data.get("count_before", 0))
    current_count = int(data.get("current_count", 0))

    # ── Check 1: Count increased (signals something was created) ─────────────
    if current_count > count_before:
        score += 20
        feedback_parts.append(
            f"✓ Aircraft count increased: {count_before} → {current_count} (+20)"
        )
    else:
        feedback_parts.append(
            f"✗ Aircraft count did not change: {count_before} → {current_count}"
        )

    # ── Check 2: Aircraft record found ────────────────────────────────────────
    if aircraft is None:
        return {
            "passed": False,
            "score": score,
            "feedback": "Aircraft 'Phoenix Mk3' was not found in the registry. "
                        "Navigate to Registry > Aircrafts > + Add and enter Name: 'Phoenix Mk3'."
                        "\n" + "\n".join(feedback_parts)
        }

    score += 30
    feedback_parts.append("✓ Aircraft record found in registry (+30)")

    # ── Check 3: Name matches 'Phoenix Mk3' (50 points — primary check) ──────
    name = (aircraft.get("name") or "").strip()
    if name.lower() == "phoenix mk3":
        score += 50
        feedback_parts.append("✓ Aircraft name 'Phoenix Mk3' correct (+50)")
    elif "phoenix" in name.lower():
        score += 25
        feedback_parts.append(f"~ Partial name match: '{name}' (+25)")
    else:
        feedback_parts.append(
            f"✗ Aircraft name mismatch: expected 'Phoenix Mk3', got '{name}'"
        )

    # ── Final decision ────────────────────────────────────────────────────────
    passed = score >= 70  # Must have aircraft found + correct name
    feedback = "\n".join(feedback_parts)
    feedback += f"\n\nTotal score: {score}/100"

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }
