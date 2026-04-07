#!/usr/bin/env python3
"""
Verifier for disaster_relief_shelter_layout task.

Occupation: Emergency Management Director / Humanitarian Logistics Coordinator
Industry: Disaster Relief / Emergency Housing

Features required: furniture_placement, wall_creation, label_placement, dimension_annotation

Scoring (total 100 pts, pass threshold 70):
  C1: Evacuee Quarters | 25 | >=30 beds/cots/mattresses placed (Partial: 15 pts for >=15 beds)
  C2: Medical & Admin Zones | 20 | >=3 medical beds + >=3 storage cabinets AND >=3 desks + >=6 chairs
  C3: Food Service Area | 15 | >=4 tables + >=16 chairs (Partial: 7 pts for >=2 tables + 8 chairs)
  C4: Egress Dimensioning | 15 | >=3 dimension lines created (Partial: 5 pts per line up to 15)
  C5: Walls & Wayfinding | 15 | >=3 new partition walls + >=4 text labels
  C6: File Save & Total Volume | 10 | File changed from baseline + >=65 total furniture items placed

Wrong-target gate: furniture count < 20 or file unchanged -> score 0.
"""

import json

def verify_disaster_relief_shelter_layout(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if copy_from_env is None:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        result_path = copy_from_env("/tmp/disaster_relief_shelter_layout_result.json")
        with open(result_path) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not retrieve result JSON: {e}"}

    score = 0
    feedback_parts = []

    # ── Wrong-target gate ─────────────────────────────────────────────────────
    furniture_count = result.get("furniture_count", 0)
    file_changed = result.get("file_changed", False)
    
    if furniture_count < 20 or not file_changed:
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                f"Wrong-target gate: only {furniture_count} furniture item(s) found, and file_changed={file_changed}. "
                "At least 20 items required and file must be saved to qualify for scoring."
            )
        }

    bed_count = result.get("bed_count", 0)
    med_count = result.get("med_count", 0)
    shelf_count = result.get("shelf_count", 0)
    desk_count = result.get("desk_count", 0)
    table_count = result.get("table_count", 0)
    chair_count = result.get("chair_count", 0)
    new_walls = result.get("new_walls", 0)
    new_labels = result.get("new_labels", 0)
    new_dimensions = result.get("new_dimensions", 0)

    # ── C1 (25 pts): Evacuee Quarters ──────────────────────────────────────────
    if bed_count >= 30:
        score += 25
        feedback_parts.append(f"PASS C1: {bed_count} beds placed (>=30 required) [+25]")
    elif bed_count >= 15:
        score += 15
        feedback_parts.append(f"PARTIAL C1: {bed_count} beds placed (>=15 for partial, >=30 for full) [+15]")
    else:
        feedback_parts.append(f"FAIL C1: only {bed_count} beds placed (need >=15 for partial)")

    # ── C2 (20 pts): Medical & Admin Zones ─────────────────────────────────────
    # Allow med beds to overlap with standard beds if med_count is too low but bed_count is very high.
    medical_beds_ok = (med_count >= 3) or (bed_count >= 33)
    storage_ok = (shelf_count >= 3)
    admin_ok = (desk_count >= 3 and chair_count >= 6)
    
    if medical_beds_ok and storage_ok and admin_ok:
        score += 20
        feedback_parts.append(f"PASS C2: Medical & Admin zones fully equipped [+20]")
    elif (medical_beds_ok and storage_ok) or admin_ok:
        score += 10
        feedback_parts.append(f"PARTIAL C2: Medical or Admin zone equipped, but not both [+10]")
    else:
        feedback_parts.append(f"FAIL C2: Medical & Admin zones lack required furniture (need 3 med beds, 3 storage, 3 desks, 6 chairs)")

    # ── C3 (15 pts): Food Service Area ─────────────────────────────────────────
    if table_count >= 4 and chair_count >= 16:
        score += 15
        feedback_parts.append(f"PASS C3: Food service area equipped ({table_count} tables, {chair_count} chairs) [+15]")
    elif table_count >= 2 and chair_count >= 8:
        score += 7
        feedback_parts.append(f"PARTIAL C3: Food service area partially equipped ({table_count} tables, {chair_count} chairs) [+7]")
    else:
        feedback_parts.append(f"FAIL C3: Food service area needs >=4 tables and >=16 chairs")

    # ── C4 (15 pts): Egress Dimensioning ───────────────────────────────────────
    if new_dimensions >= 3:
        score += 15
        feedback_parts.append(f"PASS C4: {new_dimensions} dimension lines created [+15]")
    elif new_dimensions > 0:
        c4_score = min(15, new_dimensions * 5)
        score += c4_score
        feedback_parts.append(f"PARTIAL C4: {new_dimensions} dimension lines created [+{c4_score}]")
    else:
        feedback_parts.append(f"FAIL C4: No dimension lines created (need >=3)")

    # ── C5 (15 pts): Walls & Wayfinding ────────────────────────────────────────
    if new_walls >= 3 and new_labels >= 4:
        score += 15
        feedback_parts.append(f"PASS C5: {new_walls} new walls and {new_labels} text labels [+15]")
    elif new_walls >= 1 or new_labels >= 2:
        score += 7
        feedback_parts.append(f"PARTIAL C5: {new_walls} walls, {new_labels} labels [+{7}]")
    else:
        feedback_parts.append(f"FAIL C5: Need >=3 new walls and >=4 text labels")

    # ── C6 (10 pts): File Save & Total Volume ──────────────────────────────────
    if furniture_count >= 65 and file_changed:
        score += 10
        feedback_parts.append(f"PASS C6: Total {furniture_count} furniture items and file saved [+10]")
    elif file_changed:
        score += 5
        feedback_parts.append(f"PARTIAL C6: File saved but only {furniture_count} items placed [+{5}]")
    else:
        feedback_parts.append(f"FAIL C6: Total volume and save criteria not met")

    passed = score >= 70
    summary = (
        f"Score: {score}/100 | Furniture: {furniture_count} "
        f"(beds={bed_count}, tables={table_count}, chairs={chair_count}, desks={desk_count}, shelves={shelf_count}) | "
        f"Walls: {new_walls} | Labels: {new_labels} | Dims: {new_dimensions}"
    )
    feedback_parts.insert(0, summary)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }