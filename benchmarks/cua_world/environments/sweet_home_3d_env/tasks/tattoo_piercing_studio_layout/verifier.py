#!/usr/bin/env python3
"""
Verifier for tattoo_piercing_studio_layout task.

Occupation: Small Business Owner / Facilities Planner
Industry: Personal Care Services / Body Art

Features required: wall creation, room definition, door placement, furniture placement, dimension annotations

Scoring (total 100 pts, pass threshold 70):
  C1 (20 pts): Walls & Doors -- >=3 new walls AND >=2 doors/windows (Partial: 10 pts for one)
  C2 (15 pts): Zones Defined -- >=4 rooms or labels placed identifying the zones
  C3 (20 pts): Sinks & Storage -- >=2 sinks AND >=5 storage units (cabinets/shelves/counters)
  C4 (20 pts): Studio Seating -- >=3 beds/loungers/armchairs (clients) AND >=4 chairs/stools (artists/staff)
  C5 (25 pts): Dimensions & Save -- >=2 dimension lines (15 pts) AND file changed/saved (10 pts)

Wrong-target gate: if total furniture < 10 or file not changed, return score=0 immediately.
"""

import json

def verify_tattoo_piercing_studio_layout(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if copy_from_env is None:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        result_path = copy_from_env("/tmp/tattoo_piercing_studio_layout_result.json")
        with open(result_path) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not retrieve result JSON: {e}"}

    score = 0
    feedback_parts = []

    # ── Wrong-target gate ─────────────────────────────────────────────────────
    furniture_count = result.get("furniture_count", 0)
    file_changed = result.get("file_changed", False)
    
    if not file_changed:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Wrong-target gate: file was not modified or saved from baseline. Ensure you save with Ctrl+S."
        }
        
    if furniture_count < 10:
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                f"Wrong-target gate: only {furniture_count} furniture item(s) found. "
                "At least 10 items required to qualify for scoring."
            )
        }

    new_walls = result.get("new_walls", 0)
    new_doors = result.get("new_doors", 0)
    zone_ids = result.get("zone_identifiers", 0)
    sink_count = result.get("sink_count", 0)
    storage_count = result.get("storage_count", 0)
    bed_count = result.get("bed_count", 0)
    chair_count = result.get("chair_count", 0)
    new_dims = result.get("new_dimensions", 0)

    # ── C1 (20 pts): Walls & Doors ──────────────────────────────────────────
    if new_walls >= 3 and new_doors >= 2:
        score += 20
        feedback_parts.append(f"PASS C1: {new_walls} walls & {new_doors} doors [+20]")
    elif new_walls >= 3 or new_doors >= 2:
        score += 10
        feedback_parts.append(f"PARTIAL C1: {new_walls} walls & {new_doors} doors (need >=3 walls and >=2 doors) [+10]")
    else:
        feedback_parts.append(f"FAIL C1: missing walls or doors for enclosed rooms (got {new_walls} walls, {new_doors} doors)")

    # ── C2 (15 pts): Zones Defined ──────────────────────────────────────────
    if zone_ids >= 4:
        score += 15
        feedback_parts.append(f"PASS C2: {zone_ids} zone identifiers (rooms/labels) [+15]")
    elif zone_ids >= 2:
        score += 7
        feedback_parts.append(f"PARTIAL C2: {zone_ids} zone identifiers (need >=4) [+7]")
    else:
        feedback_parts.append(f"FAIL C2: insufficient zone identifiers (got {zone_ids})")

    # ── C3 (20 pts): Sinks & Storage ────────────────────────────────────────
    if sink_count >= 2 and storage_count >= 5:
        score += 20
        feedback_parts.append(f"PASS C3: plumbing/storage ({sink_count} sinks, {storage_count} storage) [+20]")
    elif sink_count >= 1 and storage_count >= 3:
        score += 10
        feedback_parts.append(f"PARTIAL C3: plumbing/storage ({sink_count} sinks, {storage_count} storage) [+10]")
    else:
        feedback_parts.append(f"FAIL C3: need >=2 sinks and >=5 storage (got {sink_count} sinks, {storage_count} storage)")

    # ── C4 (20 pts): Studio Seating ─────────────────────────────────────────
    if bed_count >= 3 and chair_count >= 4:
        score += 20
        feedback_parts.append(f"PASS C4: seating ({bed_count} beds/loungers, {chair_count} chairs/stools) [+20]")
    elif bed_count >= 2 and chair_count >= 2:
        score += 10
        feedback_parts.append(f"PARTIAL C4: seating ({bed_count} beds, {chair_count} chairs) [+10]")
    else:
        feedback_parts.append(f"FAIL C4: need >=3 beds/loungers and >=4 chairs/stools (got {bed_count} beds, {chair_count} chairs)")

    # ── C5 (25 pts): Dimensions & Save ──────────────────────────────────────
    c5_score = 0
    c5_parts = []
    
    if new_dims >= 2:
        c5_score += 15
        c5_parts.append(f"{new_dims} dimension lines")
    elif new_dims == 1:
        c5_score += 7
        c5_parts.append(f"1 dimension line (partial)")
        
    if file_changed:
        c5_score += 10
        c5_parts.append("file saved")
        
    score += c5_score
    if c5_score == 25:
        feedback_parts.append(f"PASS C5: {', '.join(c5_parts)} [+25]")
    elif c5_score > 0:
        feedback_parts.append(f"PARTIAL C5: {', '.join(c5_parts)} [+{c5_score}]")
    else:
        feedback_parts.append(f"FAIL C5: missing dimensions and save state")

    passed = score >= 70
    summary = (
        f"Score: {score}/100 | Furniture: {furniture_count} items "
        f"(sinks={sink_count}, beds={bed_count}, chairs={chair_count}, storage={storage_count})"
    )
    feedback_parts.insert(0, summary)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }