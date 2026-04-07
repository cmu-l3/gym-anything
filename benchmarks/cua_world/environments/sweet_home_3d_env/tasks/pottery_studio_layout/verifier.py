#!/usr/bin/env python3
"""
Verifier for pottery_studio_layout task.

Occupation: Ceramic Artist / Small Business Owner
Industry: Arts & Crafts / Education

Scoring (total 100 pts, pass threshold 70):
  C1 (20 pts): Kiln Room & Clearances -- >=1 room named "kiln", >=2 kilns, >=2 dimension lines
  C2 (25 pts): Workspace Furniture -- >=6 chairs/stools, >=10 tables, >=2 sinks
  C3 (15 pts): Storage Racks -- >=8 shelving units/cabinets
  C4 (25 pts): Zones & Flooring -- >=4 distinct room zones defined, >=1 with floor styling
  C5 (15 pts): Retail & Minimums -- >=12 total tables, >=1 plant, >=35 total items, file changed

Wrong-target gate: if total furniture < 10, return score=0 immediately.
"""

import json


def verify_pottery_studio_layout(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if copy_from_env is None:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        result_path = copy_from_env("/tmp/pottery_studio_layout_result.json")
        with open(result_path) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not retrieve result JSON: {e}"}

    score = 0
    feedback_parts = []

    furniture_count = result.get("furniture_count", 0)
    if furniture_count < 10:
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                f"Wrong-target gate: only {furniture_count} furniture item(s) found. "
                "At least 10 items required to qualify for scoring."
            )
        }

    kiln_count = result.get("kiln_count", 0)
    chair_count = result.get("chair_count", 0)
    table_count = result.get("table_count", 0)
    sink_count = result.get("sink_count", 0)
    shelf_count = result.get("shelf_count", 0)
    plant_count = result.get("plant_count", 0)
    
    new_walls = result.get("new_walls", 0)
    new_dimensions = result.get("new_dimensions", 0)
    room_names = result.get("room_names", [])
    rooms_with_floor_color = result.get("rooms_with_floor_color", 0)
    file_changed = result.get("file_changed", False)

    kiln_room_exists = any('kiln' in r for r in room_names)

    # ── Criterion 1: Kiln Room & Clearances (20 pts) ──────────────────────────
    if kiln_room_exists and kiln_count >= 2 and new_dimensions >= 2:
        score += 20
        feedback_parts.append(f"PASS C1: Kiln Room complete ({kiln_count} kilns, {new_dimensions} dimension lines) [+20]")
    elif (kiln_room_exists or kiln_count >= 2) and new_dimensions >= 1:
        score += 10
        feedback_parts.append(f"PARTIAL C1: Kiln Room partial (kiln room defined: {kiln_room_exists}, kilns: {kiln_count}, dimensions: {new_dimensions}) [+10]")
    else:
        feedback_parts.append(f"FAIL C1: Kiln Room needs name 'kiln', >= 2 kilns/appliances, and >= 2 dimension lines")

    # ── Criterion 2: Workspace Furniture (25 pts) ─────────────────────────────
    if chair_count >= 6 and table_count >= 10 and sink_count >= 2:
        score += 25
        feedback_parts.append(f"PASS C2: Workspaces furnished ({chair_count} chairs, {table_count} tables, {sink_count} sinks) [+25]")
    elif chair_count >= 3 and table_count >= 5 and sink_count >= 1:
        score += 15
        feedback_parts.append(f"PARTIAL C2: Workspaces partially furnished ({chair_count} chairs, {table_count} tables, {sink_count} sinks) [+15]")
    else:
        feedback_parts.append(f"FAIL C2: Workspaces need >=6 chairs, >=10 tables, >=2 sinks")

    # ── Criterion 3: Storage Racks (15 pts) ───────────────────────────────────
    if shelf_count >= 8:
        score += 15
        feedback_parts.append(f"PASS C3: Storage sufficient ({shelf_count} shelves/cabinets) [+15]")
    elif shelf_count >= 4:
        score += 7
        feedback_parts.append(f"PARTIAL C3: Storage partial ({shelf_count} shelves/cabinets) [+7]")
    else:
        feedback_parts.append(f"FAIL C3: Storage needs >= 8 shelves/cabinets")

    # ── Criterion 4: Zones & Flooring (25 pts) ────────────────────────────────
    distinct_named_rooms = len(set(room_names))
    if distinct_named_rooms >= 4 and rooms_with_floor_color >= 1:
        score += 25
        feedback_parts.append(f"PASS C4: Zoning complete ({distinct_named_rooms} named zones, {rooms_with_floor_color} with floor styling) [+25]")
    elif distinct_named_rooms >= 3:
        score += 15
        feedback_parts.append(f"PARTIAL C4: Zoning partial ({distinct_named_rooms} named zones, {rooms_with_floor_color} with floor styling) [+15]")
    elif distinct_named_rooms >= 2 or rooms_with_floor_color >= 1:
        score += 10
        feedback_parts.append(f"PARTIAL C4: Minimal zoning ({distinct_named_rooms} named zones, {rooms_with_floor_color} with floor styling) [+10]")
    else:
        feedback_parts.append(f"FAIL C4: Zoning needs >= 4 named zones and >= 1 room with floor styling")

    # ── Criterion 5: Retail & Minimums (15 pts) ───────────────────────────────
    c5_score = 0
    c5_parts = []
    if table_count >= 12:
        c5_score += 5
        c5_parts.append(f"{table_count} tables overall")
    if plant_count >= 1:
        c5_score += 5
        c5_parts.append("1+ plants")
    if furniture_count >= 35 and file_changed:
        c5_score += 5
        c5_parts.append("file changed and >=35 total items")
    
    score += c5_score
    if c5_score == 15:
        feedback_parts.append(f"PASS C5: Retail & minimums met ({', '.join(c5_parts)}) [+15]")
    elif c5_score > 0:
        feedback_parts.append(f"PARTIAL C5: Retail/minimums partial ({', '.join(c5_parts)}) [+{c5_score}]")
    else:
        feedback_parts.append(f"FAIL C5: Retail/minimums require overall tables >=12, plants >=1, total items >=35, and file modified")

    passed = score >= 70
    summary = f"Score: {score}/100 | Furniture: {furniture_count} items (chairs={chair_count}, tables={table_count}, kilns={kiln_count}, sinks={sink_count}, shelves={shelf_count})"
    feedback_parts.insert(0, summary)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }