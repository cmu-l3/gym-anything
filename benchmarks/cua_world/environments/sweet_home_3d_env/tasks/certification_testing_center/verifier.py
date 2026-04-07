#!/usr/bin/env python3
"""
Verifier for certification_testing_center task.

Occupation: Testing Center Administrator / Facilities Planner
Industry: Education & Professional Certification

Features required:
  - Furniture placement (desks, chairs, lockers, appliances)
  - Wall creation (partitioning the space)
  - Door/window placement (observation windows & entry)
  - Room definition & floor color
  - Dimension annotation (compliance documentation)

Scoring (total 100 pts, pass threshold 70):
  C1 (25 pts): Testing Stations -- >=12 desks/tables AND >=12 chairs.
  C2 (20 pts): Reception & Break Room -- >=14 desks/tables total, >=18 chairs total, >=4 storage, >=2 appliances.
  C3 (20 pts): Walls & Doors/Windows -- >=3 new walls AND >=4 new doors/windows.
  C4 (20 pts): Room Zones & Flooring -- >=4 room definitions AND >=2 rooms with floorColor.
  C5 (15 pts): Dimensions & Save State -- >=2 new dimensions AND file modified.

Wrong-target gate: if total furniture < 15 -> score=0.
"""

import json


def verify_certification_testing_center(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if copy_from_env is None:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        result_path = copy_from_env("/tmp/certification_testing_center_result.json")
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
                "At least 15 items required to qualify for scoring. Did you forget to save?"
            )
        }

    workspace_count = result.get("workspace_count", 0)
    chair_count = result.get("chair_count", 0)
    storage_count = result.get("storage_count", 0)
    appliance_count = result.get("appliance_count", 0)
    
    new_walls = result.get("new_walls", 0)
    new_doors = result.get("new_doors", 0)
    new_rooms = result.get("new_rooms", 0)
    room_names = result.get("room_names", [])
    rooms_with_floor_color = result.get("rooms_with_floor_color", 0)
    new_dimensions = result.get("new_dimensions", 0)
    
    file_changed = result.get("file_changed", False)

    # ── C1 (25 pts): Testing Stations ─────────────────────────────────────────
    # Requires >=12 desks/tables and >=12 chairs for the testing lab
    if workspace_count >= 12 and chair_count >= 12:
        score += 25
        feedback_parts.append(
            f"PASS C1: Testing stations ({workspace_count} workspaces, {chair_count} chairs total) [+25]"
        )
    elif workspace_count >= 8 and chair_count >= 8:
        score += 15
        feedback_parts.append(
            f"PARTIAL C1: Incomplete testing lab ({workspace_count} workspaces, {chair_count} chairs) [+15]"
        )
    else:
        feedback_parts.append(
            f"FAIL C1: Testing lab requires >=12 desks/tables and >=12 chairs "
            f"(got {workspace_count}, {chair_count})"
        )

    # ── C2 (20 pts): Reception & Break Room Furniture ─────────────────────────
    # Total targets: 14 workspaces, 18 chairs, 4 storage (lockers), 2 appliances
    c2_criteria = sum([
        workspace_count >= 14,
        chair_count >= 18,
        storage_count >= 4,
        appliance_count >= 2
    ])
    
    if c2_criteria >= 4:
        score += 20
        feedback_parts.append(
            f"PASS C2: Reception & Break room ({storage_count} storage, {appliance_count} appliances) [+20]"
        )
    elif c2_criteria >= 2:
        score += 10
        feedback_parts.append(
            f"PARTIAL C2: Missing some reception/break items (storage={storage_count}, appliances={appliance_count}) [+10]"
        )
    else:
        feedback_parts.append(
            f"FAIL C2: Need reception desk, waiting chairs, lockers, and break room appliances"
        )

    # ── C3 (20 pts): Walls & Doors/Windows ────────────────────────────────────
    if new_walls >= 3 and new_doors >= 4:
        score += 20
        feedback_parts.append(
            f"PASS C3: Security boundaries ({new_walls} walls, {new_doors} doors/windows) [+20]"
        )
    elif new_walls >= 1 or new_doors >= 1:
        score += 10
        feedback_parts.append(
            f"PARTIAL C3: Partial boundaries ({new_walls} walls, {new_doors} doors/windows) [+10]"
        )
    else:
        feedback_parts.append(
            f"FAIL C3: Need >=3 new partition walls and >=4 doors/observation windows"
        )

    # ── C4 (20 pts): Room Zones & Flooring ────────────────────────────────────
    named_rooms = len(room_names)
    c4_rooms = max(new_rooms, named_rooms)
    if c4_rooms >= 4 and rooms_with_floor_color >= 2:
        score += 20
        feedback_parts.append(
            f"PASS C4: Zone definitions ({c4_rooms} rooms, {rooms_with_floor_color} distinct floors) [+20]"
        )
    elif c4_rooms >= 4:
        score += 10
        feedback_parts.append(
            f"PARTIAL C4: Rooms defined but missing floor colors ({c4_rooms} rooms, {rooms_with_floor_color} distinct floors) [+10]"
        )
    elif rooms_with_floor_color >= 1:
        score += 10
        feedback_parts.append(
            f"PARTIAL C4: Floors differentiated but insufficient rooms ({c4_rooms} rooms, {rooms_with_floor_color} distinct floors) [+10]"
        )
    else:
        feedback_parts.append(
            f"FAIL C4: Need >=4 defined rooms and >=2 rooms with distinct floor colors/textures"
        )

    # ── C5 (15 pts): Dimensions & Save State ──────────────────────────────────
    if new_dimensions >= 2 and file_changed:
        score += 15
        feedback_parts.append(
            f"PASS C5: Compliance dimensions & file saved ({new_dimensions} annotations) [+15]"
        )
    elif new_dimensions >= 2:
        score += 10
        feedback_parts.append(
            f"PARTIAL C5: Annotations present but file save status ambiguous ({new_dimensions} annotations) [+10]"
        )
    elif new_dimensions == 1 and file_changed:
        score += 7
        feedback_parts.append(
            f"PARTIAL C5: Only 1 dimension annotation provided [+7]"
        )
    else:
        feedback_parts.append(
            f"FAIL C5: Need >=2 dimension annotations for compliance checking"
        )

    passed = score >= 70
    summary = (
        f"Score: {score}/100 | Furniture: {furniture_count} items "
        f"(desks/tables={workspace_count}, chairs={chair_count}, lockers={storage_count}, appliances={appliance_count})"
    )
    feedback_parts.insert(0, summary)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }