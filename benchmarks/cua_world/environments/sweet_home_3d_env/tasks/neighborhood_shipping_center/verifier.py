#!/usr/bin/env python3
"""
Verifier for neighborhood_shipping_center task.

Occupation: Logistics Facility Planner
Industry: Transportation and Warehousing

This task exercises 4 Sweet Home 3D features:
  - Furniture placement (highly specific capacity modeling)
  - Wall & Door creation (public vs secure zone logic)
  - Room floor color (visual zoning)
  - Dimension lines (ADA compliance documentation)

Cumulative Tracking Logic:
Because an agent might use a "desk" or a "table" interchangeably, we use `total_surfaces = desk_count + table_count`.
- 3 surfaces for Service Counter
- 4 surfaces for Sorting
- 2 surfaces for Packing
=> Total surfaces needed for full credit = 9
- 8 shelves for Storage
- 3 shelves for Retail
=> Total shelves needed = 11

Scoring (total 100 pts, pass threshold 70):
  C1 (20 pts): Service Counter -- >=3 surfaces, >=3 computers, >=3 chairs
  C2 (25 pts): Back-of-House Sorting -- Total surfaces >=7 (3 service + 4 sorting), Total shelves >=8
  C3 (15 pts): Retail & Packing -- Total surfaces >=9 (7 prior + 2 packing), Total shelves >=11, Total chairs >=5 (3 staff + 2 customer)
  C4 (15 pts): Zoning Walls & Doors -- >=2 new walls, >=2 new doors
  C5 (25 pts): Specs & Polish -- >=3 dimension lines, >=2 rooms with floor colors, file changed & >=45 total items

Wrong-target gate: furniture_count < 15 -> score=0.
"""

import json


def verify_neighborhood_shipping_center(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if copy_from_env is None:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        result_path = copy_from_env("/tmp/neighborhood_shipping_center_result.json")
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

    total_surfaces = result.get("total_surfaces", 0)
    computer_count = result.get("computer_count", 0)
    chair_count = result.get("chair_count", 0)
    shelf_count = result.get("shelf_count", 0)
    
    new_walls = result.get("new_walls", 0)
    new_doors = result.get("new_doors", 0)
    new_dimensions = result.get("new_dimensions", 0)
    rooms_with_floor_color = result.get("rooms_with_floor_color", 0)
    file_changed = result.get("file_changed", False)

    # ── C1 (20 pts): Service Counter ──────────────────────────────────────────
    if total_surfaces >= 3 and computer_count >= 3 and chair_count >= 3:
        score += 20
        feedback_parts.append(f"PASS C1: Service counter furnished (>=3 surfaces, {computer_count} computers, >=3 chairs) [+20]")
    elif total_surfaces >= 2 and computer_count >= 2 and chair_count >= 2:
        score += 10
        feedback_parts.append(f"PARTIAL C1: Service counter partially furnished ({total_surfaces} surfaces, {computer_count} computers, {chair_count} chairs) [+10]")
    else:
        feedback_parts.append(f"FAIL C1: Service counter needs >=3 surfaces/desks, >=3 computers, >=3 chairs (got {total_surfaces}, {computer_count}, {chair_count})")

    # ── C2 (25 pts): Back-of-House Sorting ────────────────────────────────────
    # Cumulative: needs 3 (service) + 4 (sorting) = 7 surfaces, and 8 shelves
    if total_surfaces >= 7 and shelf_count >= 8:
        score += 25
        feedback_parts.append(f"PASS C2: Sorting area furnished (total surfaces >= 7, {shelf_count} shelves) [+25]")
    elif total_surfaces >= 5 and shelf_count >= 4:
        score += 12
        feedback_parts.append(f"PARTIAL C2: Sorting area partially furnished (total surfaces={total_surfaces}, shelves={shelf_count}) [+12]")
    else:
        feedback_parts.append(f"FAIL C2: Sorting area needs >=4 additional tables/surfaces and >=8 shelves (got total surfaces={total_surfaces}, shelves={shelf_count})")

    # ── C3 (15 pts): Retail & Packing ─────────────────────────────────────────
    # Cumulative: needs 7 (prior) + 2 (packing) = 9 surfaces, 8 (prior) + 3 (retail) = 11 shelves, 3 (staff) + 2 (customer) = 5 chairs
    if total_surfaces >= 9 and shelf_count >= 11 and chair_count >= 5:
        score += 15
        feedback_parts.append(f"PASS C3: Retail & Packing areas furnished (total surfaces >= 9, shelves >= 11, chairs >= 5) [+15]")
    elif total_surfaces >= 8 and shelf_count >= 9:
        score += 7
        feedback_parts.append(f"PARTIAL C3: Retail & Packing areas partially furnished (total surfaces={total_surfaces}, shelves={shelf_count}, chairs={chair_count}) [+7]")
    else:
        feedback_parts.append(f"FAIL C3: Retail & Packing needs >=2 additional tables, >=3 display shelves, >=2 customer chairs")

    # ── C4 (15 pts): Zoning Walls & Doors ─────────────────────────────────────
    if new_walls >= 2 and new_doors >= 2:
        score += 15
        feedback_parts.append(f"PASS C4: Zoning boundaries created ({new_walls} new walls, {new_doors} new doors) [+15]")
    elif new_walls >= 1 or new_doors >= 1:
        score += 7
        feedback_parts.append(f"PARTIAL C4: Some zoning boundaries created ({new_walls} new walls, {new_doors} new doors) [+7]")
    else:
        feedback_parts.append(f"FAIL C4: Zoning requires >=2 new partition walls and >=2 new doors")

    # ── C5 (25 pts): Specs & Polish ───────────────────────────────────────────
    c5_score = 0
    c5_parts = []
    
    if new_dimensions >= 3:
        c5_score += 10
        c5_parts.append(f"{new_dimensions} dimension lines")
    elif new_dimensions >= 1:
        c5_score += 5
        c5_parts.append(f"partial dimensions")
        
    if rooms_with_floor_color >= 2:
        c5_score += 10
        c5_parts.append(f"{rooms_with_floor_color} floor zones")
    elif rooms_with_floor_color >= 1:
        c5_score += 5
        c5_parts.append(f"partial floor zones")
        
    if file_changed and furniture_count >= 45:
        c5_score += 5
        c5_parts.append(f"file saved & capacity met ({furniture_count} items)")
        
    score += c5_score
    if c5_score == 25:
        feedback_parts.append(f"PASS C5: Specs & Polish complete ({', '.join(c5_parts)}) [+25]")
    elif c5_score > 0:
        feedback_parts.append(f"PARTIAL C5: Specs & Polish incomplete ({', '.join(c5_parts)}) [+{c5_score}]")
    else:
        feedback_parts.append(f"FAIL C5: Missing dimension lines, floor colors, and total item capacity")

    # ── Final Verdict ─────────────────────────────────────────────────────────
    passed = score >= 70
    summary = (
        f"Score: {score}/100 | Items: {furniture_count} "
        f"(Surfaces={total_surfaces}, Computers={computer_count}, Chairs={chair_count}, Shelves={shelf_count})"
    )
    feedback_parts.insert(0, summary)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }