#!/usr/bin/env python3
"""
Verifier for medical_clinic_layout task.

Occupation: Healthcare Facilities Manager
Industry: Healthcare / Medical Practice

Scoring (total 100 pts, pass threshold 70):
  Criterion 1 (30 pts): Waiting-area seating ≥ 20 chairs/seats
  Criterion 2 (25 pts): Reception/desk furniture ≥ 2 items (check-in + nurse station)
  Criterion 3 (20 pts): Exam-room furniture: ≥ 2 bed/exam-table items
  Criterion 4 (15 pts): Restroom fixtures present (≥ 1 toilet/sink)
  Criterion 5 (10 pts): File was modified from baseline (anti-copy-paste gate)

Wrong-target gate: if total furniture added < 5 items, return score=0 immediately.
"""

import json


def verify_medical_clinic_layout(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if copy_from_env is None:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Retrieve the result JSON from the VM
    try:
        result_path = copy_from_env("/tmp/medical_clinic_layout_result.json")
        with open(result_path) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not retrieve result JSON: {e}"}

    score = 0
    feedback_parts = []

    # ── Wrong-target gate ─────────────────────────────────────────────────────
    furniture_count = result.get("furniture_count", 0)
    if furniture_count < 5:
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                f"Wrong-target gate: only {furniture_count} furniture item(s) found in the file. "
                "At least 5 furniture items must be added to qualify for scoring. "
                "Ensure you saved the file after adding furniture."
            )
        }

    # ── Criterion 1 (30 pts): Waiting-room seating ≥ 20 ─────────────────────
    chair_count = result.get("chair_count", 0)
    if chair_count >= 20:
        score += 30
        feedback_parts.append(f"PASS C1: {chair_count} seating items found (≥20 required) [+30]")
    elif chair_count >= 10:
        score += 15
        feedback_parts.append(f"PARTIAL C1: {chair_count} seating items found (need 20 for full credit) [+15]")
    else:
        feedback_parts.append(f"FAIL C1: only {chair_count} seating items found (need ≥20 for waiting area)")

    # ── Criterion 2 (25 pts): Reception/desk furniture ≥ 2 ───────────────────
    desk_count = result.get("desk_count", 0)
    if desk_count >= 2:
        score += 25
        feedback_parts.append(f"PASS C2: {desk_count} desk/counter items found (≥2 required) [+25]")
    elif desk_count >= 1:
        score += 12
        feedback_parts.append(f"PARTIAL C2: {desk_count} desk/counter item found (need 2 for full credit) [+12]")
    else:
        feedback_parts.append("FAIL C2: no desk or counter items found (need ≥2 for reception + nurse station)")

    # ── Criterion 3 (20 pts): Exam-room beds/tables ≥ 2 ─────────────────────
    bed_count = result.get("bed_count", 0)
    if bed_count >= 2:
        score += 20
        feedback_parts.append(f"PASS C3: {bed_count} exam table/bed items found (≥2 required) [+20]")
    elif bed_count >= 1:
        score += 10
        feedback_parts.append(f"PARTIAL C3: {bed_count} exam table/bed item found (need 2 for full credit) [+10]")
    else:
        feedback_parts.append("FAIL C3: no exam table or bed found (each exam room needs one)")

    # ── Criterion 4 (15 pts): Restroom fixtures ≥ 1 ─────────────────────────
    toilet_count = result.get("toilet_count", 0)
    if toilet_count >= 1:
        score += 15
        feedback_parts.append(f"PASS C4: {toilet_count} restroom fixture(s) found [+15]")
    else:
        feedback_parts.append("FAIL C4: no restroom fixtures found (toilet/sink required for patient restroom)")

    # ── Criterion 5 (10 pts): File changed from baseline ─────────────────────
    file_changed = result.get("file_changed", False)
    if file_changed:
        score += 10
        feedback_parts.append("PASS C5: file was modified and saved (distinct from starter) [+10]")
    else:
        feedback_parts.append("FAIL C5: file appears unchanged from starter — save the design with Ctrl+S")

    # ── Final verdict ─────────────────────────────────────────────────────────
    passed = score >= 70
    summary = (
        f"Score: {score}/100 | Furniture: {furniture_count} items "
        f"(chairs={chair_count}, desks={desk_count}, beds={bed_count}, toilets={toilet_count})"
    )
    feedback_parts.insert(0, summary)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
