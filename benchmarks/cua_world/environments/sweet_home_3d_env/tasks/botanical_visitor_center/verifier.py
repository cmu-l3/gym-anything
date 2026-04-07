#!/usr/bin/env python3
"""
Verifier for botanical_visitor_center task.

Occupation: Landscape Architect / Facilities Planner
Industry: Public Parks & Recreation

Features required:
  - Furniture placement (dense flora, commercial racks, seating)
  - Wall creation
  - Room definition w/ Floor Texture/Color
  - Window placement (architectural glazing)

Scoring (total 100 pts, pass threshold 70):
  C1 (20 pts): Conservatory Flora -- >= 15 plants (10 pts for >= 8)
  C2 (20 pts): Architecture & Glazing -- >= 2 walls AND >= 6 windows (10 pts for one)
  C3 (20 pts): Workshop Seating -- >= 4 tables AND >= 16 chairs (10 pts for >=2 tables + >=8 chairs)
  C4 (15 pts): Commercial Fixtures -- >= 6 shelves AND >= 3 desks/counters (7 pts for >=3 shelves + >=1 desk)
  C5 (15 pts): Room Definition -- >= 4 rooms w/ >= 3 having floorColor/floorTexture (7 pts for >= 2 rooms)
  C6 (10 pts): Layout Density & Save -- >= 45 total items AND file successfully modified

Wrong-target gate: if total furniture < 15, return score=0 immediately.
"""

import json

def verify_botanical_visitor_center(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if copy_from_env is None:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        result_path = copy_from_env("/tmp/botanical_visitor_center_result.json")
        with open(result_path) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not retrieve result JSON: {e}"}

    score = 0
    feedback_parts = []

    # ── Wrong-target gate ─────────────────────────────────────────────────────
    furniture_count = result.get("furniture_count", 0)
    if furniture_count < 15:
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                f"Wrong-target gate: only {furniture_count} furniture item(s) found. "
                "At least 15 items required to qualify for scoring."
            )
        }

    plant_count = result.get("plant_count", 0)
    bench_count = result.get("bench_count", 0)
    table_count = result.get("table_count", 0)
    chair_count = result.get("chair_count", 0)
    shelf_count = result.get("shelf_count", 0)
    desk_count = result.get("desk_count", 0)
    
    new_walls = result.get("new_walls", 0)
    new_windows = result.get("new_windows", 0)
    
    room_count = result.get("room_count", 0)
    rooms_with_floor_color = result.get("rooms_with_floor_color", 0)
    
    file_changed = result.get("file_changed", False)

    # ── Criterion 1 (20 pts): Conservatory Flora ─────────────────────────────
    if plant_count >= 15:
        score += 20
        feedback_parts.append(f"PASS C1: {plant_count} plants/flowers placed [+20]")
    elif plant_count >= 8:
        score += 10
        feedback_parts.append(f"PARTIAL C1: {plant_count} plants placed (need >= 15 for full credit) [+10]")
    else:
        feedback_parts.append(f"FAIL C1: indoor botanical flora needs >=15 plants (got {plant_count})")

    # ── Criterion 2 (20 pts): Architecture & Glazing ─────────────────────────
    arch_walls_met = new_walls >= 2
    arch_win_met = new_windows >= 6
    if arch_walls_met and arch_win_met:
        score += 20
        feedback_parts.append(f"PASS C2: Architecture ({new_walls} walls, {new_windows} windows) [+20]")
    elif arch_walls_met or arch_win_met:
        score += 10
        feedback_parts.append(f"PARTIAL C2: Architecture ({new_walls} walls, {new_windows} windows) [+10]")
    else:
        feedback_parts.append(f"FAIL C2: Architecture needs >=2 walls and >=6 windows")

    # ── Criterion 3 (20 pts): Workshop Seating ───────────────────────────────
    if table_count >= 4 and chair_count >= 16:
        score += 20
        feedback_parts.append(f"PASS C3: Workshop seating ({table_count} tables, {chair_count} chairs) [+20]")
    elif table_count >= 2 and chair_count >= 8:
        score += 10
        feedback_parts.append(f"PARTIAL C3: Workshop seating ({table_count} tables, {chair_count} chairs) [+10]")
    else:
        feedback_parts.append(f"FAIL C3: Workshop needs >=4 tables and >=16 chairs (got {table_count}, {chair_count})")

    # ── Criterion 4 (15 pts): Commercial Fixtures ────────────────────────────
    if shelf_count >= 6 and desk_count >= 3:
        score += 15
        feedback_parts.append(f"PASS C4: Commercial fixtures ({shelf_count} shelves, {desk_count} desks/counters) [+15]")
    elif shelf_count >= 3 and desk_count >= 1:
        score += 7
        feedback_parts.append(f"PARTIAL C4: Commercial fixtures ({shelf_count} shelves, {desk_count} desks) [+7]")
    else:
        feedback_parts.append(f"FAIL C4: Commercial needs >=6 shelves and >=3 desks (got {shelf_count}, {desk_count})")

    # ── Criterion 5 (15 pts): Room Definition ────────────────────────────────
    if room_count >= 4 and rooms_with_floor_color >= 3:
        score += 15
        feedback_parts.append(f"PASS C5: Room definition ({room_count} rooms, {rooms_with_floor_color} colored) [+15]")
    elif room_count >= 2:
        score += 7
        feedback_parts.append(f"PARTIAL C5: Room definition ({room_count} rooms, {rooms_with_floor_color} colored) [+7]")
    else:
        feedback_parts.append(f"FAIL C5: Need >=4 defined rooms with >=3 having floor colors (got {room_count}, {rooms_with_floor_color})")

    # ── Criterion 6 (10 pts): Layout Density & Save ──────────────────────────
    if furniture_count >= 45 and file_changed:
        score += 10
        feedback_parts.append(f"PASS C6: Layout dense & saved ({furniture_count} total items, file_changed=True) [+10]")
    elif furniture_count >= 45 or file_changed:
        score += 5
        feedback_parts.append(f"PARTIAL C6: Layout status ({furniture_count} items, file_changed={file_changed}) [+5]")
    else:
        feedback_parts.append(f"FAIL C6: Need >=45 items and successful file save")

    # ── Final verdict ────────────────────────────────────────────────────────
    passed = score >= 70
    summary = (
        f"Score: {score}/100 | Furniture: {furniture_count} items "
        f"(plants={plant_count}, tables={table_count}, chairs={chair_count}, "
        f"shelves={shelf_count}, desks={desk_count})"
    )
    feedback_parts.insert(0, summary)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }