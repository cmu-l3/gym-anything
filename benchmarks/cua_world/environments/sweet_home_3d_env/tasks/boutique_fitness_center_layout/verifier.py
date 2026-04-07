#!/usr/bin/env python3
"""
Verifier for boutique_fitness_center_layout task.

Occupation: Commercial Interior Designer
Industry: Commercial Architecture / Fitness

Scoring (total 100 pts, pass threshold 70):
  C1 (20 pts): Room Definition & Flooring (>=4 room/labels + >=3 floor colors)
  C2 (15 pts): Wall Partitioning (>=4 new walls)
  C3 (25 pts): Gym & Reception (>=8 gym items, >=1 desk, >=2 lounge items)
  C4 (20 pts): Locker Rooms (>=4 storage, >=2 toilets, >=2 sinks, >=2 showers/baths)
  C5 (20 pts): 3D Render & Save (Render exists, file modified)

Wrong-target gate: furniture_count < 15 -> score=0.
"""

import json


def verify_boutique_fitness_center_layout(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if copy_from_env is None:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        result_path = copy_from_env("/tmp/boutique_fitness_center_layout_result.json")
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

    zone_identifiers = result.get("zone_identifiers", 0)
    rooms_with_floor_color = result.get("rooms_with_floor_color", 0)
    new_walls = result.get("new_walls", 0)
    
    gym_count = result.get("gym_count", 0)
    desk_count = result.get("desk_count", 0)
    chair_count = result.get("chair_count", 0)
    lounge_count = result.get("lounge_count", 0)
    storage_count = result.get("storage_count", 0)
    toilet_count = result.get("toilet_count", 0)
    sink_count = result.get("sink_count", 0)
    shower_count = result.get("shower_count", 0)
    
    render_found = result.get("render_found", False)
    file_changed = result.get("file_changed", False)

    # ── C1 (20 pts): Room Definition & Flooring ───────────────────────────────
    c1_score = 0
    c1_parts = []
    
    if zone_identifiers >= 4:
        c1_score += 10
        c1_parts.append(f"{zone_identifiers} zones defined")
    elif zone_identifiers >= 2:
        c1_score += 5
        c1_parts.append(f"{zone_identifiers} zones (partial)")
        
    if rooms_with_floor_color >= 3:
        c1_score += 10
        c1_parts.append(f"{rooms_with_floor_color} floor colors")
    elif rooms_with_floor_color >= 1:
        c1_score += 5
        c1_parts.append(f"{rooms_with_floor_color} floor color (partial)")
        
    score += c1_score
    if c1_score == 20:
        feedback_parts.append(f"PASS C1: Room zoning & flooring ({', '.join(c1_parts)}) [+20]")
    elif c1_score > 0:
        feedback_parts.append(f"PARTIAL C1: Room zoning & flooring ({', '.join(c1_parts)}) [+{c1_score}]")
    else:
        feedback_parts.append("FAIL C1: Need >=4 rooms/labels and >=3 floor colors")

    # ── C2 (15 pts): Wall Partitioning ────────────────────────────────────────
    if new_walls >= 4:
        score += 15
        feedback_parts.append(f"PASS C2: Partition walls ({new_walls} new walls built) [+15]")
    elif new_walls >= 2:
        score += 7
        feedback_parts.append(f"PARTIAL C2: Partition walls ({new_walls} new walls built) [+7]")
    else:
        feedback_parts.append(f"FAIL C2: Need >=4 new wall segments to partition the gym (got {new_walls})")

    # ── C3 (25 pts): Gym & Reception Furniture ────────────────────────────────
    c3_score = 0
    c3_parts = []
    
    if gym_count >= 8:
        c3_score += 15
        c3_parts.append(f"{gym_count} gym items")
    elif gym_count >= 4:
        c3_score += 7
        c3_parts.append(f"{gym_count} gym items (partial)")
        
    if desk_count >= 1 and (lounge_count >= 2 or chair_count >= 2):
        c3_score += 10
        c3_parts.append(f"Reception furnished")
    elif desk_count >= 1 or lounge_count >= 1:
        c3_score += 5
        c3_parts.append(f"Reception partial")
        
    score += c3_score
    if c3_score == 25:
        feedback_parts.append(f"PASS C3: Gym floor & Reception ({', '.join(c3_parts)}) [+25]")
    elif c3_score > 0:
        feedback_parts.append(f"PARTIAL C3: Gym & Reception ({', '.join(c3_parts)}) [+{c3_score}]")
    else:
        feedback_parts.append(f"FAIL C3: Need >=8 gym items + Reception desk/lounge (got {gym_count} gym, {desk_count} desks)")

    # ── C4 (20 pts): Locker Rooms ─────────────────────────────────────────────
    c4_score = 0
    c4_parts = []
    
    if storage_count >= 4:
        c4_score += 5
        c4_parts.append(f"{storage_count} lockers")
    if toilet_count >= 2:
        c4_score += 5
        c4_parts.append(f"{toilet_count} toilets")
    if sink_count >= 2:
        c4_score += 5
        c4_parts.append(f"{sink_count} sinks")
    if shower_count >= 2:
        c4_score += 5
        c4_parts.append(f"{shower_count} showers")
        
    score += c4_score
    if c4_score == 20:
        feedback_parts.append(f"PASS C4: Locker rooms ({', '.join(c4_parts)}) [+20]")
    elif c4_score > 0:
        feedback_parts.append(f"PARTIAL C4: Locker rooms ({', '.join(c4_parts)}) [+{c4_score}]")
    else:
        feedback_parts.append("FAIL C4: Locker rooms missing fixtures (need storage, toilets, sinks, showers)")

    # ── C5 (20 pts): 3D Render & Save ─────────────────────────────────────────
    c5_score = 0
    c5_parts = []
    
    if render_found:
        c5_score += 10
        c5_parts.append("3D render created")
    if file_changed:
        c5_score += 10
        c5_parts.append("file saved")
        
    score += c5_score
    if c5_score == 20:
        feedback_parts.append(f"PASS C5: Rendering & Save ({', '.join(c5_parts)}) [+20]")
    elif c5_score > 0:
        feedback_parts.append(f"PARTIAL C5: Rendering & Save ({', '.join(c5_parts)}) [+{c5_score}]")
    else:
        feedback_parts.append("FAIL C5: Missing 3D photo render and/or file not saved")

    # ── Final verdict ─────────────────────────────────────────────────────────
    passed = score >= 70
    summary = (
        f"Score: {score}/100 | Furniture: {furniture_count} items "
        f"(gym={gym_count}, lockers={storage_count}, toilets={toilet_count}, showers={shower_count})"
    )
    feedback_parts.insert(0, summary)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }