#!/usr/bin/env python3
"""Verifier for add_manufacturer task.
Checks that 'SkyTech Innovations' (country: IN/India) was added to the registry.
"""

import json


def verify_add_manufacturer(traj, env_info, task_info):
    """Verify that company 'SkyTech Innovations' was successfully added."""

    result_path = "/tmp/add_manufacturer_result.json"
    score = 0
    feedback_parts = []

    try:
        with open(result_path) as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result file: {e}"}

    manufacturer = data.get("manufacturer")
    count_before = int(data.get("count_before", 0))
    current_count = int(data.get("current_count", 0))

    # ── Check 1: Company exists (50 points) ──────────────────────────────────
    if manufacturer is None:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Company 'SkyTech Innovations' was not found in the registry."
        }

    score += 50
    feedback_parts.append("✓ Company record found in registry (+50)")

    # ── Check 2: Name correct (35 points) ────────────────────────────────────
    name = (manufacturer.get("full_name") or "").strip()
    if name.lower() == "skytech innovations":
        score += 35
        feedback_parts.append("✓ Company name 'SkyTech Innovations' correct (+35)")
    else:
        feedback_parts.append(
            f"✗ Name mismatch: expected 'SkyTech Innovations', got '{name}'"
        )

    # ── Check 3: Country is India (15 points) ────────────────────────────────
    country = (manufacturer.get("country") or "").strip().upper()
    india_codes = {"IN", "IND", "INDIA"}
    if country in india_codes:
        score += 15
        feedback_parts.append(f"✓ Country 'India' ('{country}') correct (+15)")
    else:
        feedback_parts.append(
            f"✗ Country mismatch: expected 'IN' (India), got '{country}'"
        )

    # ── Check 4: Count increased ──────────────────────────────────────────────
    if current_count > count_before:
        feedback_parts.append(f"✓ Company count increased: {count_before} → {current_count}")

    passed = score >= 50
    feedback = "\n".join(feedback_parts)
    feedback += f"\n\nTotal score: {score}/100"

    return {"passed": passed, "score": score, "feedback": feedback}
