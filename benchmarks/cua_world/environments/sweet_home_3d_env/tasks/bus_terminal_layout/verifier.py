#!/usr/bin/env python3
"""
Verifier for bus_terminal_layout task.

Occupation: Transportation Facilities Planner
Industry: Public Transportation / Civil Engineering

Features required: wall creation, room definition, furniture placement, dimension annotation

Scoring (total 100 pts, pass threshold 70):
  C1 (15 pts): Enclosed Partitions -- >=5 new walls (partial >=3 -> 8)
  C2 (15 pts): Room Zones -- >=4 rooms defined with names (partial >=2 -> 7)
  C3 (25 pts): Passenger Concourse -- >=20 waiting seats + >=3 counters + >=2 displays
  C4 (15 pts): Staff Zones -- >=2 lounge seats + >=1 appliance + >=1 sec desk + >=1 sec display
  C5 (15 pts): Mass Restrooms -- >=4 toilets + >=4 sinks (partial >=2 -> 7)
  C6 (15 pts): Dimensions & Save -- >=3 dimension lines + file changed + >=45 total items

Wrong-target gate: if total furniture < 15, return score=0 immediately.
"""

import json

def verify_bus_terminal_layout(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if copy_from_env is None:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        result_path = copy_from_env("/tmp/bus_terminal_layout_result.json")
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

    new_walls = result.get("new_walls", 0)
    room_names = result.get("room_names", [])
    wait_count = result.get("wait_count", 0)
    lounge_count = result.get("lounge_count", 0)
    counter_count = result.get("counter_count", 0)
    tech_count = result.get("tech_count", 0)
    appliance_count = result.get("appliance_count", 0)
    toilet_count = result.get("toilet_count", 0)
    sink_count = result.get("sink_count", 0)
    new_dimensions = result.get("new_dimensions", 0)
    file_changed = result.get("file_changed", False)

    # ── C1 (15 pts): Enclosed Partitions ──────────────────────────────────────
    if new_walls >= 5:
        score += 15
        feedback_parts.append(f"PASS C1: {new_walls} new partition walls [+15]")
    elif new_walls >= 3:
        score += 8
        feedback_parts.append(f"PARTIAL C1: {new_walls} new partition walls (need >=5) [+8]")
    else:
        feedback_parts.append(f"FAIL C1: need >=5 new partition walls (got {new_walls})")

    # ── C2 (15 pts): Room Zones Defined ───────────────────────────────────────
    named_rooms = len(room_names)
    if named_rooms >= 4:
        score += 15
        feedback_parts.append(f"PASS C2: {named_rooms} named room zones [+15]")
    elif named_rooms >= 2:
        score += 7
        feedback_parts.append(f"PARTIAL C2: {named_rooms} named room zones (need >=4) [+7]")
    else:
        feedback_parts.append(f"FAIL C2: need >=4 named room zones (got {named_rooms})")

    # ── C3 (25 pts): Passenger Concourse ──────────────────────────────────────
    c3_score = 0
    c3_parts = []
    
    if wait_count >= 20: 
        c3_score += 10
        c3_parts.append(f"{wait_count} waiting seats")
    elif wait_count >= 10: 
        c3_score += 5
        c3_parts.append(f"{wait_count} waiting seats (partial)")
    else:
        c3_parts.append(f"missing seats ({wait_count}/20)")
        
    if counter_count >= 3: 
        c3_score += 10
        c3_parts.append(f"{counter_count} counters")
    elif counter_count >= 1: 
        c3_score += 5
        c3_parts.append(f"{counter_count} counters (partial)")
    else:
        c3_parts.append(f"missing counters ({counter_count}/3)")
        
    if tech_count >= 2: 
        c3_score += 5
        c3_parts.append(f"{tech_count} displays")
    elif tech_count >= 1: 
        c3_score += 2
        c3_parts.append(f"{tech_count} displays (partial)")
    else:
        c3_parts.append(f"missing displays ({tech_count}/2)")

    score += c3_score
    if c3_score == 25:
        feedback_parts.append(f"PASS C3: Passenger Concourse ({', '.join(c3_parts)}) [+25]")
    else:
        feedback_parts.append(f"PARTIAL C3: Passenger Concourse ({', '.join(c3_parts)}) [+{c3_score}]")

    # ── C4 (15 pts): Staff Zones ──────────────────────────────────────────────
    c4_score = 0
    c4_parts = []
    
    if lounge_count >= 2: 
        c4_score += 5
        c4_parts.append(f"{lounge_count} lounge seats")
    elif lounge_count >= 1: 
        c4_score += 2
        c4_parts.append(f"{lounge_count} lounge seat (partial)")
        
    if appliance_count >= 1: 
        c4_score += 4
        c4_parts.append(f"{appliance_count} appliances")
        
    # Desks/Tech shared counting (requires extra beyond C3 for full credit)
    if counter_count >= 4: 
        c4_score += 3
        c4_parts.append(f"security desk found")
    elif counter_count >= 1: 
        c4_score += 1
        
    if tech_count >= 3: 
        c4_score += 3
        c4_parts.append(f"security display found")
    elif tech_count >= 1: 
        c4_score += 1

    score += c4_score
    if c4_score == 15:
        feedback_parts.append(f"PASS C4: Staff Zones ({', '.join(c4_parts)}) [+15]")
    else:
        feedback_parts.append(f"PARTIAL C4: Staff Zones ({', '.join(c4_parts)}) [+{c4_score}]")

    # ── C5 (15 pts): Mass Restrooms ───────────────────────────────────────────
    if toilet_count >= 4 and sink_count >= 4:
        score += 15
        feedback_parts.append(f"PASS C5: Mass Restrooms ({toilet_count} toilets, {sink_count} sinks) [+15]")
    elif toilet_count >= 2 and sink_count >= 2:
        score += 7
        feedback_parts.append(f"PARTIAL C5: Restrooms ({toilet_count} toilets, {sink_count} sinks) [+7]")
    else:
        feedback_parts.append(f"FAIL C5: Restrooms need >=4 toilets + >=4 sinks (got {toilet_count}, {sink_count})")

    # ── C6 (15 pts): Dimensions & Total & Save ────────────────────────────────
    c6_score = 0
    c6_parts = []
    if new_dimensions >= 3:
        c6_score += 5
        c6_parts.append(f"{new_dimensions} dimension lines")
    if file_changed:
        c6_score += 5
        c6_parts.append("file saved")
    if furniture_count >= 45:
        c6_score += 5
        c6_parts.append(f"total items={furniture_count}")
        
    score += c6_score
    if c6_score == 15:
        feedback_parts.append(f"PASS C6: Technical details ({', '.join(c6_parts)}) [+15]")
    elif c6_score > 0:
        feedback_parts.append(f"PARTIAL C6: Technical details ({', '.join(c6_parts)}) [+{c6_score}]")
    else:
        feedback_parts.append(f"FAIL C6: Missing dimension lines, saves, or total furniture volume.")

    # ── Final Verdict ─────────────────────────────────────────────────────────
    passed = score >= 70
    summary = (
        f"Score: {score}/100 | Furniture: {furniture_count} total "
        f"(Wait={wait_count}, Lounge={lounge_count}, Desk={counter_count}, "
        f"Tech={tech_count}, App={appliance_count}, Toilet={toilet_count})"
    )
    feedback_parts.insert(0, summary)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }