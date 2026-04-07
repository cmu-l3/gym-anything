#!/usr/bin/env python3
"""
Verifier for auto_repair_shop_layout task.

Occupation: Automotive Service Manager
Industry: Automotive Repair and Maintenance

Scoring (total 100 pts, pass threshold 60):
  C1 (15 pts): Partition walls -- >=4 new walls beyond baseline (partial >=2 -> 8 pts)
  C2 (20 pts): Room zones defined -- >=4 rooms with names (partial >=2 -> 10 pts)
  C3 (20 pts): Service bay furnishings -- >=3 tables/workbenches + >=3 shelves/cabinets (partial >=2+2 -> 10 pts)
  C4 (20 pts): Customer/office furniture -- >=4 chairs + >=2 desks + >=1 lamp (partial >=2 chairs + >=1 desk -> 10 pts)
  C5 (25 pts): Labels (>=3) + doors (>=3) + restroom (>=1 toilet, >=1 sink) + file changed (scored individually)

Wrong-target gate: furniture_count < 8 -> score 0.
"""

import json

def verify_auto_repair_shop_layout(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if copy_from_env is None:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        result_path = copy_from_env("/tmp/auto_repair_shop_layout_result.json")
        with open(result_path) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not retrieve result JSON: {e}"}

    score = 0
    feedback_parts = []

    furniture_count = result.get("furniture_count", 0)
    if furniture_count < 8:
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                f"Wrong-target gate: only {furniture_count} furniture item(s) found. "
                "At least 8 items required to qualify for scoring."
            )
        }

    new_walls = result.get("new_walls", 0)
    rooms_with_names = result.get("rooms_with_names", 0)
    
    table_count = result.get("table_count", 0)
    desk_count = result.get("desk_count", 0)
    shelf_count = result.get("shelf_count", 0)
    chair_count = result.get("chair_count", 0)
    lamp_count = result.get("lamp_count", 0)
    
    label_count = result.get("label_count", 0)
    door_window_count = result.get("door_window_count", 0)
    toilet_count = result.get("toilet_count", 0)
    sink_count = result.get("sink_count", 0)
    file_changed = result.get("file_changed", False)

    # C1 (15 pts): Partition walls
    if new_walls >= 4:
        score += 15
        feedback_parts.append(f"PASS C1: {new_walls} partition walls [+15]")
    elif new_walls >= 2:
        score += 8
        feedback_parts.append(f"PARTIAL C1: {new_walls} partition walls (need >=4) [+8]")
    else:
        feedback_parts.append(f"FAIL C1: insufficient partition walls (got {new_walls}, need >=4)")

    # C2 (20 pts): Room zones defined
    if rooms_with_names >= 4:
        score += 20
        feedback_parts.append(f"PASS C2: {rooms_with_names} named room zones [+20]")
    elif rooms_with_names >= 2:
        score += 10
        feedback_parts.append(f"PARTIAL C2: {rooms_with_names} named room zones (need >=4) [+10]")
    else:
        feedback_parts.append(f"FAIL C2: insufficient named room zones (got {rooms_with_names})")

    # C3 (20 pts): Service bay furnishings
    if table_count >= 3 and shelf_count >= 3:
        score += 20
        feedback_parts.append(f"PASS C3: bay workspace ({table_count} tables/benches, {shelf_count} shelves) [+20]")
    elif table_count >= 2 and shelf_count >= 2:
        score += 10
        feedback_parts.append(f"PARTIAL C3: partial bay workspace ({table_count} tables, {shelf_count} shelves) [+10]")
    else:
        feedback_parts.append(f"FAIL C3: bay workspace needs >=3 tables/benches + >=3 shelves (got {table_count}, {shelf_count})")

    # C4 (20 pts): Customer + office furniture
    # desk_count and table_count can conceptually overlap in Sweet Home 3D, allowing desk_count+table_count for broader workspace mapping
    total_desks = desk_count + (1 if table_count > 3 else 0) # Give benefit of the doubt if extra tables placed
    if chair_count >= 4 and total_desks >= 2 and lamp_count >= 1:
        score += 20
        feedback_parts.append(f"PASS C4: office/waiting ({chair_count} chairs, {total_desks} desks, {lamp_count} lamps) [+20]")
    elif chair_count >= 2 and total_desks >= 1:
        score += 10
        feedback_parts.append(f"PARTIAL C4: partial office/waiting ({chair_count} chairs, {total_desks} desks) [+10]")
    else:
        feedback_parts.append(f"FAIL C4: office/waiting needs >=4 chairs, >=2 desks, >=1 lamp (got {chair_count}, {total_desks}, {lamp_count})")

    # C5 (25 pts): Annotations, structural components, file status
    c5_score = 0
    c5_details = []
    
    if label_count >= 3:
        c5_score += 7
        c5_details.append(f"{label_count} labels")
    
    if door_window_count >= 3:
        c5_score += 6
        c5_details.append(f"{door_window_count} doors")
        
    if toilet_count >= 1 and sink_count >= 1:
        c5_score += 6
        c5_details.append("restroom fixtures")
        
    if file_changed:
        c5_score += 6
        c5_details.append("file changed")
        
    score += c5_score
    if c5_score == 25:
        feedback_parts.append(f"PASS C5: labels, doors, restrooms, save verified [+25]")
    elif c5_score > 0:
        feedback_parts.append(f"PARTIAL C5: {', '.join(c5_details)} [+{c5_score}]")
    else:
        feedback_parts.append(f"FAIL C5: missing labels, doors, restrooms, or file not saved")

    passed = score >= 60
    summary = f"Score: {score}/100 | Furniture: {furniture_count} items"
    feedback_parts.insert(0, summary)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }