#!/usr/bin/env python3
"""
Verifier for neighborhood_grocery_layout task.

Occupation: Retail Store Planner
Industry: Retail / Grocery

Features required: furniture_placement, wall_creation, room_definition, door_window_placement, dimension_annotation, floor_color

Scoring (total 100 pts, pass threshold 70):
  C1 (20 pts): Aisles & Shelving >= 12 (Partial: 10 pts for >= 6)
  C2 (20 pts): Checkout & Perishables >= 3 desks + >= 3 chairs + >= 4 refrigerators
  C3 (20 pts): Walls & Doors >= 2 new walls + >= 1 new door (back-of-house)
  C4 (20 pts): Room Zones & Flooring >= 2 rooms with distinct floor colors/textures
  C5 (20 pts): Dimensions & Save >= 2 dimension lines + file actually modified and saved

Wrong-target gate: if total furniture < 15, return score=0 immediately.
"""

import json
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_neighborhood_grocery_layout(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if copy_from_env is None:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        result_path = copy_from_env("/tmp/neighborhood_grocery_layout_result.json")
        with open(result_path) as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result JSON: {e}")
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
                "At least 15 items required to qualify for scoring. "
                "Ensure you saved the file after adding furniture."
            )
        }

    shelf_count = result.get("shelf_count", 0)
    checkout_count = result.get("checkout_count", 0)
    chair_count = result.get("chair_count", 0)
    fridge_count = result.get("fridge_count", 0)
    rooms_with_floor_color = result.get("rooms_with_floor_color", 0)
    new_walls = result.get("new_walls", 0)
    new_doors = result.get("new_doors", 0)
    new_dimensions = result.get("new_dimensions", 0)
    file_changed = result.get("file_changed", False)

    # ── Criterion 1 (20 pts): Aisles & Shelving ───────────────────────────────
    if shelf_count >= 12:
        score += 20
        feedback_parts.append(f"PASS C1: Aisles ({shelf_count} shelving units) [+20]")
    elif shelf_count >= 6:
        score += 10
        feedback_parts.append(f"PARTIAL C1: Aisles ({shelf_count} shelving units, need >=12) [+10]")
    else:
        feedback_parts.append(f"FAIL C1: Aisles (only {shelf_count} shelving units found, need >=12)")

    # ── Criterion 2 (20 pts): Checkout & Perishables ──────────────────────────
    c2_score = 0
    c2_parts = []
    
    if checkout_count >= 3:
        c2_score += 7
        c2_parts.append(f"{checkout_count} checkout counters")
    elif checkout_count >= 1:
        c2_score += 3
        c2_parts.append(f"{checkout_count} checkout counter (partial)")
        
    if chair_count >= 3:
        c2_score += 6
        c2_parts.append(f"{chair_count} chairs")
    elif chair_count >= 1:
        c2_score += 3
        c2_parts.append(f"{chair_count} chair (partial)")

    if fridge_count >= 4:
        c2_score += 7
        c2_parts.append(f"{fridge_count} refrigerators")
    elif fridge_count >= 2:
        c2_score += 3
        c2_parts.append(f"{fridge_count} refrigerators (partial)")

    score += c2_score
    if c2_score == 20:
        feedback_parts.append(f"PASS C2: Checkout & Perishables ({', '.join(c2_parts)}) [+20]")
    elif c2_score > 0:
        feedback_parts.append(f"PARTIAL C2: Checkout & Perishables ({', '.join(c2_parts)}) [+{c2_score}]")
    else:
        feedback_parts.append("FAIL C2: Missing required checkout stations and refrigerators")

    # ── Criterion 3 (20 pts): Walls & Doors ───────────────────────────────────
    if new_walls >= 2 and new_doors >= 1:
        score += 20
        feedback_parts.append(f"PASS C3: Back-of-house structure ({new_walls} new walls, {new_doors} doors) [+20]")
    elif new_walls >= 1 or new_doors >= 1:
        score += 10
        feedback_parts.append(f"PARTIAL C3: Partial structure ({new_walls} new walls, {new_doors} doors) [+10]")
    else:
        feedback_parts.append(f"FAIL C3: No back-of-house walls or doors detected")

    # ── Criterion 4 (20 pts): Room Zones & Flooring ───────────────────────────
    if rooms_with_floor_color >= 2:
        score += 20
        feedback_parts.append(f"PASS C4: Zone Flooring ({rooms_with_floor_color} rooms mapped with floor color/texture) [+20]")
    elif rooms_with_floor_color == 1:
        score += 10
        feedback_parts.append(f"PARTIAL C4: Zone Flooring (1 room with floor color/texture, need >=2) [+10]")
    else:
        feedback_parts.append("FAIL C4: Rooms missing floor color or texture differentiation")

    # ── Criterion 5 (20 pts): Dimensions & Save ───────────────────────────────
    c5_score = 0
    c5_parts = []
    
    if new_dimensions >= 2:
        c5_score += 10
        c5_parts.append(f"{new_dimensions} dimension lines")
    elif new_dimensions == 1:
        c5_score += 5
        c5_parts.append("1 dimension line")
        
    if file_changed:
        c5_score += 10
        c5_parts.append("file modified successfully")

    score += c5_score
    if c5_score == 20:
        feedback_parts.append(f"PASS C5: Documentation & Save ({', '.join(c5_parts)}) [+20]")
    elif c5_score > 0:
        feedback_parts.append(f"PARTIAL C5: Documentation & Save ({', '.join(c5_parts)}) [+{c5_score}]")
    else:
        feedback_parts.append("FAIL C5: Missing dimension lines and file unchanged")

    # ── Final Verdict ─────────────────────────────────────────────────────────
    passed = score >= 70
    summary = (
        f"Score: {score}/100 | Furniture: {furniture_count} items "
        f"(shelves={shelf_count}, desks={checkout_count}, chairs={chair_count}, fridges={fridge_count})"
    )
    feedback_parts.insert(0, summary)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }