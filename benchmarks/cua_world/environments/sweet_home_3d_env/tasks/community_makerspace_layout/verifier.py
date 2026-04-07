#!/usr/bin/env python3
"""
Verifier for community_makerspace_layout task.

Occupation: Makerspace Coordinator
Industry: Nonprofit / Community Organizations

Features evaluated:
  - Wall creation (partitioning)
  - Room definition / labeling (zone identifiers)
  - Floor color/texture (visual separation)
  - Furniture placement (specific counts by category)
  - Door/window placement (access points)

Scoring (Total 100 points, Pass threshold 70):
  C1 (25 pts): Workbenches + seating (>=10 desks/tables + >=10 chairs/stools)
  C2 (20 pts): Storage + lighting (>=8 shelves/cabinets + >=6 lamps)
  C3 (20 pts): Zone ID + floor color (>=4 rooms/labels + >=3 distinct floor colors)
  C4 (20 pts): Partition walls + doors (>=3 new walls + >=2 new doors)
  C5 (15 pts): Decor/plants (>=3) + Total items (>=40) + File changed

Wrong-target gate: Total furniture < 8 -> Score 0 immediately.
"""

import json

def verify_community_makerspace_layout(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if copy_from_env is None:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        result_path = copy_from_env("/tmp/community_makerspace_layout_result.json")
        with open(result_path) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not retrieve result JSON: {e}"}

    score = 0
    feedback_parts = []

    # ── Wrong-target gate ─────────────────────────────────────────────────────
    actual_furniture_count = result.get("actual_furniture_count", 0)
    total_items_count = result.get("total_items_count", 0)
    if total_items_count < 8:
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                f"Wrong-target gate: only {total_items_count} item(s) found in the layout. "
                "At least 8 items required to qualify for scoring."
            )
        }

    desk_count = result.get("desk_count", 0)
    chair_count = result.get("chair_count", 0)
    shelf_count = result.get("shelf_count", 0)
    lamp_count = result.get("lamp_count", 0)
    decor_count = result.get("decor_count", 0)
    
    new_walls = result.get("new_walls", 0)
    new_doors = result.get("new_doors", 0)
    room_names = result.get("room_names", [])
    label_texts = result.get("label_texts", [])
    rooms_with_floor_color = result.get("rooms_with_floor_color", 0)
    
    file_changed = result.get("file_changed", False)

    # ── C1 (25 pts): Workbenches + seating ────────────────────────────────────
    if desk_count >= 10 and chair_count >= 10:
        score += 25
        feedback_parts.append(f"PASS C1: Workstations ({desk_count} desks/tables, {chair_count} chairs) [+25]")
    elif desk_count >= 5 and chair_count >= 5:
        score += 12
        feedback_parts.append(f"PARTIAL C1: Partial workstations ({desk_count} desks, {chair_count} chairs) [+12]")
    else:
        feedback_parts.append(f"FAIL C1: Workstations need >=10 desks + >=10 chairs (got {desk_count}, {chair_count})")

    # ── C2 (20 pts): Storage + lighting ───────────────────────────────────────
    if shelf_count >= 8 and lamp_count >= 6:
        score += 20
        feedback_parts.append(f"PASS C2: Storage & Lighting ({shelf_count} shelves, {lamp_count} lamps) [+20]")
    elif shelf_count >= 4 and lamp_count >= 3:
        score += 10
        feedback_parts.append(f"PARTIAL C2: Partial storage/lighting ({shelf_count} shelves, {lamp_count} lamps) [+10]")
    else:
        feedback_parts.append(f"FAIL C2: Needs >=8 shelves + >=6 lamps (got {shelf_count}, {lamp_count})")

    # ── C3 (20 pts): Zone ID + floor color ────────────────────────────────────
    # Unique zone identifiers (named rooms + text labels)
    zone_ids = len(room_names) + len(label_texts)
    if zone_ids >= 4 and rooms_with_floor_color >= 3:
        score += 20
        feedback_parts.append(f"PASS C3: Zone definitions ({zone_ids} labels/named rooms, {rooms_with_floor_color} floor colors) [+20]")
    elif zone_ids >= 2 and rooms_with_floor_color >= 1:
        score += 10
        feedback_parts.append(f"PARTIAL C3: Partial zones ({zone_ids} labels/named rooms, {rooms_with_floor_color} floor colors) [+10]")
    else:
        feedback_parts.append(f"FAIL C3: Zones need >=4 labels/names + >=3 floor colors (got {zone_ids}, {rooms_with_floor_color})")

    # ── C4 (20 pts): Partition walls + doors ──────────────────────────────────
    if new_walls >= 3 and new_doors >= 2:
        score += 20
        feedback_parts.append(f"PASS C4: Architecture ({new_walls} new walls, {new_doors} new doors) [+20]")
    elif new_walls >= 1 and new_doors >= 1:
        score += 10
        feedback_parts.append(f"PARTIAL C4: Partial architecture ({new_walls} walls, {new_doors} doors) [+10]")
    else:
        feedback_parts.append(f"FAIL C4: Architecture needs >=3 new walls + >=2 new doors (got {new_walls}, {new_doors})")

    # ── C5 (15 pts): Decor + Total count + File modified ──────────────────────
    c5_score = 0
    c5_parts = []
    if decor_count >= 3:
        c5_score += 5
        c5_parts.append(f"{decor_count} decor items")
    if actual_furniture_count >= 40:
        c5_score += 5
        c5_parts.append(f"{actual_furniture_count} total items")
    if file_changed:
        c5_score += 5
        c5_parts.append("file modified")
        
    score += c5_score
    if c5_score == 15:
        feedback_parts.append(f"PASS C5: Environment ({', '.join(c5_parts)}) [+15]")
    elif c5_score > 0:
        feedback_parts.append(f"PARTIAL C5: Environment ({', '.join(c5_parts)}) [+{c5_score}]")
    else:
        feedback_parts.append(f"FAIL C5: Needs >=3 decor, >=40 total items, and saved file changes")

    # ── Final Verdict ─────────────────────────────────────────────────────────
    passed = score >= 70
    summary = (
        f"Score: {score}/100 | Items: {actual_furniture_count} "
        f"(Desks={desk_count}, Chairs={chair_count}, Shelves={shelf_count}, "
        f"Lamps={lamp_count}, Decor={decor_count})"
    )
    feedback_parts.insert(0, summary)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }