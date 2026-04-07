#!/usr/bin/env python3
"""
Verifier for wedding_venue_banquet_layout task.

Occupation: Wedding Coordinator / Event Planner
Industry: Events & Hospitality

Scoring (total 100 pts, pass threshold 70):
  Criterion 1 (25 pts): Guest dining furniture -- >=8 tables + >=32 chairs
  Criterion 2 (20 pts): Zone floor differentiation -- >=3 rooms with distinct floorColor/Texture
  Criterion 3 (20 pts): Head table + bar/lounge -- total tables >=11 (8+1+2), total chairs >=36 (32+4), >=1 sofa
  Criterion 4 (20 pts): Decorative ambiance -- >=6 lamps/lights + >=4 plants/decor
  Criterion 5 (15 pts): Text labels >=4 (5), total items >=55 (5), file changed (5)

Wrong-target gate: if total furniture < 8, return score=0 immediately.
"""

import json


def verify_wedding_venue_banquet_layout(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if copy_from_env is None:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        result_path = copy_from_env("/tmp/wedding_venue_banquet_layout_result.json")
        with open(result_path) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not retrieve result JSON: {e}"}

    score = 0
    feedback_parts = []

    # ── Wrong-target gate ─────────────────────────────────────────────────────
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

    table_count = result.get("table_count", 0)
    chair_count = result.get("chair_count", 0)
    sofa_count = result.get("sofa_count", 0)
    lamp_count = result.get("lamp_count", 0)
    plant_count = result.get("plant_count", 0)
    rooms_with_floor_color = result.get("rooms_with_floor_color", 0)
    new_labels = result.get("new_labels", 0)
    file_changed = result.get("file_changed", False)

    # ── Criterion 1 (25 pts): Guest dining furniture ────────────────────────
    if table_count >= 8 and chair_count >= 32:
        score += 25
        feedback_parts.append(f"PASS C1: dining furniture ({table_count} tables, {chair_count} chairs) [+25]")
    elif table_count >= 4 and chair_count >= 16:
        score += 12
        feedback_parts.append(f"PARTIAL C1: partial dining setup ({table_count} tables, {chair_count} chairs) [+12]")
    elif table_count >= 2 and chair_count >= 8:
        score += 6
        feedback_parts.append(f"PARTIAL C1: minimal dining setup ({table_count} tables, {chair_count} chairs) [+6]")
    else:
        feedback_parts.append(f"FAIL C1: need >=8 tables and >=32 chairs (got {table_count}, {chair_count})")

    # ── Criterion 2 (20 pts): Zone floor differentiation ────────────────────
    if rooms_with_floor_color >= 3:
        score += 20
        feedback_parts.append(f"PASS C2: zone differentiation ({rooms_with_floor_color} rooms with floor color/texture) [+20]")
    elif rooms_with_floor_color >= 2:
        score += 15
        feedback_parts.append(f"PARTIAL C2: partial differentiation ({rooms_with_floor_color} rooms colored) [+15]")
    elif rooms_with_floor_color >= 1:
        score += 10
        feedback_parts.append(f"PARTIAL C2: minimal differentiation ({rooms_with_floor_color} room colored) [+10]")
    else:
        feedback_parts.append(f"FAIL C2: need >=3 rooms with distinct floor colors/textures (got {rooms_with_floor_color})")

    # ── Criterion 3 (20 pts): Head table + bar/lounge ───────────────────────
    # We look for total accumulation: 8 (dining) + 1 (head) + 2 (bar) = 11 tables
    # Chairs: 32 (dining) + 4 (head) = 36 chairs
    c3_tables_ok = table_count >= 11
    c3_chairs_ok = chair_count >= 36
    c3_sofa_ok = sofa_count >= 1
    
    c3_met = sum([c3_tables_ok, c3_chairs_ok, c3_sofa_ok])
    
    if c3_met == 3:
        score += 20
        feedback_parts.append(f"PASS C3: head table + lounge (total {table_count} tables, {chair_count} chairs, {sofa_count} sofa) [+20]")
    elif c3_met == 2:
        score += 10
        feedback_parts.append(f"PARTIAL C3: missing elements for head table or lounge [+10]")
    elif c3_met == 1:
        score += 5
        feedback_parts.append(f"PARTIAL C3: minimal head table or lounge items [+5]")
    else:
        feedback_parts.append(f"FAIL C3: head table and lounge setup incomplete (need tables >=11, chairs >=36, sofas >=1)")

    # ── Criterion 4 (20 pts): Decorative ambiance ───────────────────────────
    if lamp_count >= 6 and plant_count >= 4:
        score += 20
        feedback_parts.append(f"PASS C4: decorative ambiance ({lamp_count} lamps, {plant_count} decor items) [+20]")
    elif lamp_count >= 3 and plant_count >= 2:
        score += 10
        feedback_parts.append(f"PARTIAL C4: partial ambiance ({lamp_count} lamps, {plant_count} decor) [+10]")
    elif lamp_count >= 2 or plant_count >= 2:
        score += 5
        feedback_parts.append(f"PARTIAL C4: minimal ambiance ({lamp_count} lamps, {plant_count} decor) [+5]")
    else:
        feedback_parts.append(f"FAIL C4: ambiance requires >=6 lamps + >=4 decor items (got {lamp_count}, {plant_count})")

    # ── Criterion 5 (15 pts): Labels, totals, and file save ─────────────────
    c5_score = 0
    c5_parts = []
    
    if new_labels >= 4:
        c5_score += 5
        c5_parts.append(f"labels({new_labels})")
    if furniture_count >= 55:
        c5_score += 5
        c5_parts.append(f"count({furniture_count})")
    if file_changed:
        c5_score += 5
        c5_parts.append("file_changed")
        
    score += c5_score
    if c5_score == 15:
        feedback_parts.append(f"PASS C5: formatting/saves ({', '.join(c5_parts)}) [+15]")
    elif c5_score > 0:
        feedback_parts.append(f"PARTIAL C5: ({', '.join(c5_parts)}) [+{c5_score}]")
    else:
        feedback_parts.append("FAIL C5: need >=4 labels, >=55 items, file changed")

    # ── Final verdict ─────────────────────────────────────────────────────────
    passed = score >= 70
    summary = (
        f"Score: {score}/100 | Items: {furniture_count} "
        f"(tables={table_count}, chairs={chair_count}, sofas={sofa_count}, "
        f"lamps={lamp_count}, decor={plant_count}, zones={rooms_with_floor_color})"
    )
    feedback_parts.insert(0, summary)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }