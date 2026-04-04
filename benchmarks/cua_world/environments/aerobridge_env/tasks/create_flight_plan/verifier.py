#!/usr/bin/env python3
"""Verifier for create_flight_plan task.
Checks that a flight plan named 'Mumbai Coastal Survey' was created.
"""

import json


def verify_create_flight_plan(traj, env_info, task_info):
    """Verify that flight plan 'Mumbai Coastal Survey' was successfully created."""

    result_path = "/tmp/create_flight_plan_result.json"
    score = 0
    feedback_parts = []

    try:
        with open(result_path) as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result file: {e}"}

    if data.get("error"):
        # If there was a model import error, it might mean the app uses different names
        # Fall back to VLM verification hint
        feedback_parts.append(
            f"Note: Database query had an issue: {data['error']}. "
            "VLM trajectory verification will be used."
        )

    flight_plan = data.get("flight_plan")
    count_before = int(data.get("count_before", 0))
    current_count = int(data.get("current_count", 0))

    # ── Check 1: Flight plan exists (60 points) ───────────────────────────────
    if flight_plan is None:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Flight plan 'Mumbai Coastal Survey' was not found in the system. "
                        + "\n".join(feedback_parts)
        }

    score += 60
    feedback_parts.append("✓ Flight plan record found in system (+60)")

    # ── Check 2: Name correct (40 points) ─────────────────────────────────────
    name = (flight_plan.get("name") or "").strip()
    if name.lower() == "mumbai coastal survey":
        score += 40
        feedback_parts.append("✓ Flight plan name 'Mumbai Coastal Survey' correct (+40)")
    elif "mumbai" in name.lower() or "coastal" in name.lower():
        score += 20
        feedback_parts.append(
            f"~ Partial name match: expected 'Mumbai Coastal Survey', got '{name}' (+20)"
        )
    else:
        feedback_parts.append(f"✗ Name mismatch: expected 'Mumbai Coastal Survey', got '{name}'")

    # ── Check 3: Count increased ───────────────────────────────────────────────
    if current_count > count_before:
        feedback_parts.append(f"✓ Flight plan count increased: {count_before} → {current_count}")

    passed = score >= 60
    feedback = "\n".join(feedback_parts)
    feedback += f"\n\nTotal score: {score}/100"

    return {"passed": passed, "score": score, "feedback": feedback}
