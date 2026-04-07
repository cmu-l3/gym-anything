#!/usr/bin/env python3
"""
Verifier for fire_station_renovation task.

Occupation: Municipal Facilities Planner / Fire Captain
Industry: Public Safety / Municipal Services

Features required: wall_creation, furniture_placement, room_definition, floor_color_texture

Scoring (total 100 pts, pass threshold 70):
  C1 (20 pts): Partition walls + room zones (>=3 new walls, >=4 named/colored rooms)
  C2 (25 pts): Bunk room furnishing (>=8 beds + >=4 nightstands)
  C3 (20 pts): Kitchen/Day room (>=1 table + >=6 chairs + >=2 appliances + >=1 sofa)
  C4 (20 pts): Office + Storage (>=1 desk + >=4 shelves)
  C5 (15 pts): Restrooms (>=2 toilets + >=2 sinks) + Floor colors (>=3) + Total >=40 + File changed

Wrong-target gate: total_furniture < 8 -> score=0.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_fire_station_renovation(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if copy_from_env is None:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/fire_station_renovation_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not retrieve result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []

    # ── Wrong-target gate ─────────────────────────────────────────────────────
    total_furniture = result.get("total_furniture", 0)
    if total_furniture < 8:
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                f"Wrong-target gate: only {total_furniture} furniture item(s) found. "
                "At least 8 items required to qualify for scoring."
            )
        }

    beds = result.get("beds", 0)
    nightstands = result.get("nightstands", 0)
    tables = result.get("tables", 0)
    chairs = result.get("chairs", 0)
    desks = result.get("desks", 0)
    sofas = result.get("sofas", 0)
    shelves = result.get("shelves", 0)
    appliances = result.get("appliances", 0)
    toilets = result.get("toilets", 0)
    sinks = result.get("sinks", 0)
    
    new_walls = result.get("new_walls", 0)
    rooms_with_names = result.get("rooms_with_names", [])
    rooms_with_floor_color = result.get("rooms_with_floor_color", 0)
    file_changed = result.get("file_changed", False)

    # ── C1 (20 pts): Partition walls + room zones ────────────────────────────
    zone_count = max(len(rooms_with_names), rooms_with_floor_color)
    if new_walls >= 3 and zone_count >= 4:
        score += 20
        feedback_parts.append(f"PASS C1: {new_walls} new walls, {zone_count} distinct zones defined [+20]")
    elif new_walls >= 2 and zone_count >= 2:
        score += 10
        feedback_parts.append(f"PARTIAL C1: {new_walls} new walls, {zone_count} zones defined (need 3 walls, 4 zones) [+10]")
    elif new_walls >= 1 or zone_count >= 1:
        score += 5
        feedback_parts.append(f"PARTIAL C1: minimal structure ({new_walls} walls, {zone_count} zones) [+5]")
    else:
        feedback_parts.append(f"FAIL C1: missing new partition walls or defined rooms")

    # ── C2 (25 pts): Bunk room furnishing ────────────────────────────────────
    # Accept shelves as nightstand alternatives if nightstands are missing
    small_storage = nightstands + (shelves if nightstands < 4 else 0)
    if beds >= 8 and small_storage >= 4:
        score += 25
        feedback_parts.append(f"PASS C2: bunk room ({beds} beds, {nightstands} nightstands/cabinets) [+25]")
    elif beds >= 4 and small_storage >= 2:
        score += 12
        feedback_parts.append(f"PARTIAL C2: partial bunk room ({beds} beds, {nightstands} nightstands) [+12]")
    elif beds >= 4:
        score += 8
        feedback_parts.append(f"PARTIAL C2: beds only ({beds} beds) [+8]")
    else:
        feedback_parts.append(f"FAIL C2: bunk room requires >=8 beds (got {beds})")

    # ── C3 (20 pts): Kitchen / Day Room ──────────────────────────────────────
    if tables >= 1 and chairs >= 6 and appliances >= 2 and sofas >= 1:
        score += 20
        feedback_parts.append(f"PASS C3: kitchen/day room ({tables} tables, {chairs} chairs, {appliances} appliances, {sofas} sofas) [+20]")
    elif tables >= 1 and chairs >= 3 and appliances >= 1:
        score += 10
        feedback_parts.append(f"PARTIAL C3: partial kitchen ({tables} tables, {chairs} chairs, {appliances} appliances) [+10]")
    elif tables >= 1 and chairs >= 2:
        score += 5
        feedback_parts.append(f"PARTIAL C3: minimal kitchen ({tables} tables, {chairs} chairs) [+5]")
    else:
        feedback_parts.append(f"FAIL C3: kitchen needs >=1 table, >=6 chairs, >=2 appliances, >=1 sofa")

    # ── C4 (20 pts): Office + Storage ────────────────────────────────────────
    # Desks and shelves
    if desks >= 1 and shelves >= 4:
        score += 20
        feedback_parts.append(f"PASS C4: office & storage ({desks} desks, {shelves} shelves/cabinets) [+20]")
    elif desks >= 1 and shelves >= 2:
        score += 10
        feedback_parts.append(f"PARTIAL C4: partial office/storage ({desks} desks, {shelves} shelves) [+10]")
    elif desks >= 1 or shelves >= 2:
        score += 5
        feedback_parts.append(f"PARTIAL C4: minimal office/storage ({desks} desks, {shelves} shelves) [+5]")
    else:
        feedback_parts.append(f"FAIL C4: office/storage needs >=1 desk, >=4 shelves")

    # ── C5 (15 pts): Restrooms + Floor colors + Total + Save ─────────────────
    c5_score = 0
    c5_parts = []
    
    if rooms_with_floor_color >= 3:
        c5_score += 4
        c5_parts.append(f"{rooms_with_floor_color} floor colors (4/4)")
    elif rooms_with_floor_color >= 1:
        c5_score += 2
        c5_parts.append(f"{rooms_with_floor_color} floor colors (2/4)")
        
    if toilets >= 2 and sinks >= 2:
        c5_score += 4
        c5_parts.append(f"restrooms ok (4/4)")
    elif toilets >= 1 and sinks >= 1:
        c5_score += 2
        c5_parts.append(f"partial restrooms (2/4)")
        
    if total_furniture >= 40:
        c5_score += 4
        c5_parts.append(f"total items={total_furniture} (4/4)")
    elif total_furniture >= 25:
        c5_score += 2
        c5_parts.append(f"total items={total_furniture} (2/4)")
        
    if file_changed:
        c5_score += 3
        c5_parts.append("file saved (3/3)")
        
    score += c5_score
    if c5_score == 15:
        feedback_parts.append(f"PASS C5: all secondary criteria met [+15]")
    elif c5_score > 0:
        feedback_parts.append(f"PARTIAL C5: {', '.join(c5_parts)} [+{c5_score}]")
    else:
        feedback_parts.append(f"FAIL C5: missing secondary criteria (restrooms, floor colors, item count)")

    passed = score >= 70
    summary = (
        f"Score: {score}/100 | Items: {total_furniture} "
        f"(Beds={beds}, Tables={tables}, Chairs={chairs}, Desks={desks}, Shelves={shelves}, Toilets={toilets})"
    )
    feedback_parts.insert(0, summary)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }