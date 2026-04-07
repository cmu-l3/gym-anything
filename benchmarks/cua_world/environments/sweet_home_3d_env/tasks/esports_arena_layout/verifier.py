#!/usr/bin/env python3
"""
Verifier for esports_arena_layout task.

Occupation: E-sports Facility Manager
Industry: Entertainment / Gaming

Features required: furniture_placement, wall_creation, room_definition, floor_color

Scoring (total 100 pts, pass threshold 70):
  C1 (25 pts): Competitive stage -- >=10 PCs + >=10 chairs + >=10 desks
  C2 (20 pts): Casual PC Area -- >=15 additional of each (Totaling >=25 PCs, chairs, desks)
  C3 (25 pts): Streaming Booth -- >=3 new walls + >=1 door/window + global desk/chair counts verify furnishing
  C4 (15 pts): Lounge & Reception -- >=2 sofas + >=2 TVs + >=1 reception desk (Total desks >=26)
  C5 (15 pts): Zone Definition & Save -- >=4 rooms + >=3 rooms with color + file_changed

Wrong-target gate: if total PCs < 15 or total seating < 15, return score=0 immediately.
"""

import json


def verify_esports_arena_layout(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if copy_from_env is None:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        result_path = copy_from_env("/tmp/esports_arena_layout_result.json")
        with open(result_path) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not retrieve result JSON: {e}"}

    score = 0
    feedback_parts = []

    # Retrieve counts
    pc_count = result.get("pc_count", 0)
    tv_count = result.get("tv_count", 0)
    desk_count = result.get("desk_count", 0)
    chair_count = result.get("chair_count", 0)
    sofa_count = result.get("sofa_count", 0)
    new_walls = result.get("new_walls", 0)
    new_doors = result.get("new_doors", 0)
    room_count = result.get("room_count", 0)
    rooms_with_floor_color = result.get("rooms_with_floor_color", 0)
    file_changed = result.get("file_changed", False)

    total_seating = chair_count + sofa_count

    # ── Wrong-target gate ─────────────────────────────────────────────────────
    if pc_count < 15 or total_seating < 15:
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                f"Wrong-target gate: only {pc_count} PCs and {total_seating} seats found. "
                "An e-sports arena requires at least 15 PCs and 15 seats to qualify for scoring."
            )
        }

    # ── C1 (25 pts): Competitive Stage (10 PCs, 10 chairs, 10 desks) ─────────
    if pc_count >= 10 and chair_count >= 10 and desk_count >= 10:
        score += 25
        feedback_parts.append("PASS C1: Competitive Stage items present (>=10 PCs, chairs, desks) [+25]")
    elif pc_count >= 5 and chair_count >= 5 and desk_count >= 5:
        score += 15
        feedback_parts.append("PARTIAL C1: Partial Competitive Stage items present (>=5 PCs, chairs, desks) [+15]")
    else:
        feedback_parts.append("FAIL C1: Missing items for 5v5 Competitive Stage")

    # ── C2 (20 pts): Casual PC Area (Total 25 PCs, chairs, desks) ────────────
    if pc_count >= 25 and chair_count >= 25 and desk_count >= 25:
        score += 20
        feedback_parts.append("PASS C2: Casual PC Area items present (Totaling >=25 PCs, chairs, desks) [+20]")
    elif pc_count >= 15 and chair_count >= 15 and desk_count >= 15:
        score += 10
        feedback_parts.append("PARTIAL C2: Partial Casual PC Area items present (Totaling >=15 PCs, chairs, desks) [+10]")
    else:
        feedback_parts.append("FAIL C2: Insufficient density for the Casual PC Area")

    # ── C3 (25 pts): Streaming Booth Construction ────────────────────────────
    c3_score = 0
    c3_parts = []
    if new_walls >= 3:
        c3_score += 15
        c3_parts.append(f"{new_walls} walls built")
    if new_doors >= 1:
        c3_score += 10
        c3_parts.append(f"{new_doors} door/window placed")
    
    score += c3_score
    if c3_score == 25:
        feedback_parts.append(f"PASS C3: Streaming Booth construction ({', '.join(c3_parts)}) [+25]")
    elif c3_score > 0:
        feedback_parts.append(f"PARTIAL C3: Partial Booth construction ({', '.join(c3_parts)}) [+{c3_score}]")
    else:
        feedback_parts.append(f"FAIL C3: Streaming Booth missing (needs >=3 new walls and >=1 door/window)")

    # ── C4 (15 pts): Console Lounge & Reception ──────────────────────────────
    c4_score = 0
    if sofa_count >= 2:
        c4_score += 5
    if tv_count >= 2:
        c4_score += 5
    if desk_count >= 26:  # 25 for PCs + 1 for reception
        c4_score += 5
        
    score += c4_score
    if c4_score == 15:
        feedback_parts.append("PASS C4: Lounge and Reception items present (>=2 sofas, >=2 TVs, reception desk) [+15]")
    elif c4_score > 0:
        feedback_parts.append(f"PARTIAL C4: Partial Lounge/Reception elements present [+{c4_score}]")
    else:
        feedback_parts.append("FAIL C4: Lounge and Reception items missing")

    # ── C5 (15 pts): Zone Definition & Save ──────────────────────────────────
    c5_score = 0
    if room_count >= 4:
        c5_score += 5
    if rooms_with_floor_color >= 3:
        c5_score += 5
    if file_changed:
        c5_score += 5
        
    score += c5_score
    if c5_score == 15:
        feedback_parts.append(f"PASS C5: Zone Definitions saved ({room_count} rooms, {rooms_with_floor_color} colored) [+15]")
    elif c5_score > 0:
        feedback_parts.append(f"PARTIAL C5: Zone Definitions incomplete ({room_count} rooms, {rooms_with_floor_color} colored, changed={file_changed}) [+{c5_score}]")
    else:
        feedback_parts.append("FAIL C5: Missing room definitions or file unchanged")

    # ── Final Verdict ─────────────────────────────────────────────────────────
    passed = score >= 70
    summary = (
        f"Score: {score}/100 | Layout: {pc_count} PCs, {desk_count} desks, "
        f"{chair_count} chairs, {sofa_count} sofas, {tv_count} TVs | "
        f"Architecture: {new_walls} new walls, {room_count} rooms ({rooms_with_floor_color} colored)"
    )
    feedback_parts.insert(0, summary)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }