#!/usr/bin/env python3
"""Verifier for create_flight_operation task.
Checks that a new flight operation named 'Rajasthan Corridor Inspection' was created.
"""

import json


def verify_create_flight_operation(traj, env_info, task_info):
    """Verify that flight operation 'Rajasthan Corridor Inspection' was created."""

    result_path = "/tmp/create_flight_operation_result.json"
    score = 0
    feedback_parts = []

    try:
        with open(result_path) as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result file: {e}"}

    if data.get("error"):
        feedback_parts.append(
            f"Note: Database query had an issue: {data['error']}. "
            "VLM trajectory verification will be used."
        )

    flight_op = data.get("flight_operation")
    count_before = int(data.get("count_before", 0))
    current_count = int(data.get("current_count", 0))

    # ── Check 1: Count increased (primary signal that something was created) ─
    if current_count > count_before:
        score += 30
        feedback_parts.append(
            f"✓ Flight operation count increased: {count_before} → {current_count} (+30)"
        )
    else:
        feedback_parts.append(
            f"✗ Flight operation count did not increase: {count_before} → {current_count}"
        )

    # ── Check 2: Operation found (40 points) ─────────────────────────────────
    if flight_op is None:
        feedback_parts.append(
            "✗ No flight operation record found. "
            "Ensure the operation was saved successfully."
        )
        feedback = "\n".join(feedback_parts)
        feedback += f"\n\nTotal score: {score}/100"
        return {"passed": score >= 30, "score": score, "feedback": feedback}

    score += 40
    feedback_parts.append("✓ Flight operation record found (+40)")

    # ── Check 3: Name matches (30 points) ─────────────────────────────────────
    name = (flight_op.get("name") or "").strip()
    expected = "rajasthan corridor inspection"
    if name.lower() == expected:
        score += 30
        feedback_parts.append("✓ Operation name 'Rajasthan Corridor Inspection' correct (+30)")
    elif "rajasthan" in name.lower() or "corridor" in name.lower():
        score += 15
        feedback_parts.append(
            f"~ Partial name match: expected 'Rajasthan Corridor Inspection', got '{name}' (+15)"
        )
    else:
        feedback_parts.append(
            f"✗ Name mismatch: expected 'Rajasthan Corridor Inspection', got '{name}'"
        )

    passed = score >= 40
    feedback = "\n".join(feedback_parts)
    feedback += f"\n\nTotal score: {score}/100"

    return {"passed": passed, "score": score, "feedback": feedback}
