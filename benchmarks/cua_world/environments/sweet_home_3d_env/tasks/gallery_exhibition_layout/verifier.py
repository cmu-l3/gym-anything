#!/usr/bin/env python3
"""
Verifier for gallery_exhibition_layout task.

Occupation: Exhibition Designer
Industry: Museums & Art Galleries

Features required: wall_creation, furniture_placement, label_placement, room_floor_color

Scoring (total 100 pts, pass threshold 70):
  Criterion 1 (20 pts): Partition walls -- >=5 new walls beyond baseline (partial >=3 -> 10 pts)
  Criterion 2 (25 pts): Display & Lighting -- >=8 displays + >=10 lamps (partial >=4 displays + >=5 lamps -> 12 pts)
  Criterion 3 (20 pts): Seating & Labels -- >=6 seating items + >=4 labels (partial >=3 seating + >=2 labels -> 10 pts)
  Criterion 4 (20 pts): Floor-colored zones -- >=3 rooms w/ floorColor or floorTexture (partial >=1 -> 10 pts)
  Criterion 5 (15 pts): Total >=40 items, >=10 distinct types, file_changed (5 pts each)

Wrong-target gate: if total furniture < 8, score = 0.
"""

import json

def verify_gallery_exhibition_layout(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if copy_from_env is None:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available (framework error)"}

    try:
        result_path = copy_from_env("/tmp/gallery_exhibition_layout_result.json")
        with open(result_path) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not retrieve or read result JSON: {e}"}

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
                "At least 8 items required to qualify for scoring. Ensure the design was saved."
            )
        }

    # Gather metrics
    new_walls = result.get("new_walls", 0)
    display_count = result.get("display_count", 0)
    lighting_count = result.get("lighting_count", 0)
    seating_count = result.get("seating_count", 0)
    new_labels = result.get("new_labels", 0)
    rooms_styled = result.get("rooms_with_floor_color", 0)
    distinct_types = result.get("distinct_types", 0)
    decor_count = result.get("decor_count", 0)
    file_changed = result.get("file_changed", False)

    # ── C1 (20 pts): Partition walls ──────────────────────────────────────────
    if new_walls >= 5:
        score += 20
        feedback_parts.append(f"PASS C1: partition walls ({new_walls} new walls added) [+20]")
    elif new_walls >= 3:
        score += 10
        feedback_parts.append(f"PARTIAL C1: partial partition walls ({new_walls} new walls, need >=5) [+10]")
    else:
        feedback_parts.append(f"FAIL C1: need >=5 new partition walls to divide zones (got {new_walls})")

    # ── C2 (25 pts): Display fixtures + Lighting ──────────────────────────────
    if display_count >= 8 and lighting_count >= 10:
        score += 25
        feedback_parts.append(f"PASS C2: exhibition displays ({display_count} displays, {lighting_count} lights) [+25]")
    elif display_count >= 4 and lighting_count >= 5:
        score += 12
        feedback_parts.append(f"PARTIAL C2: partial displays ({display_count} displays, {lighting_count} lights) [+12]")
    else:
        feedback_parts.append(f"FAIL C2: need >=8 displays + >=10 lights (got {display_count} displays, {lighting_count} lights)")

    # ── C3 (20 pts): Visitor seating + labels ─────────────────────────────────
    if seating_count >= 6 and new_labels >= 4:
        score += 20
        feedback_parts.append(f"PASS C3: seating/zones ({seating_count} seating, {new_labels} labels) [+20]")
    elif seating_count >= 3 and new_labels >= 2:
        score += 10
        feedback_parts.append(f"PARTIAL C3: partial seating/zones ({seating_count} seating, {new_labels} labels) [+10]")
    else:
        feedback_parts.append(f"FAIL C3: need >=6 seating items + >=4 text labels (got {seating_count} seating, {new_labels} labels)")

    # ── C4 (20 pts): Floor-colored zones ──────────────────────────────────────
    if rooms_styled >= 3:
        score += 20
        feedback_parts.append(f"PASS C4: floor differentiation ({rooms_styled} styled rooms) [+20]")
    elif rooms_styled >= 1:
        score += 10
        feedback_parts.append(f"PARTIAL C4: partial floor differentiation ({rooms_styled} styled rooms, need >=3) [+10]")
    else:
        feedback_parts.append(f"FAIL C4: need >=3 rooms with distinct floor colors/textures (got {rooms_styled})")

    # ── C5 (15 pts): Total volume, diversity, and save confirmation ───────────
    c5_score = 0
    c5_parts = []
    
    if furniture_count >= 40:
        c5_score += 5
        c5_parts.append(f">=40 items (got {furniture_count})")
    
    if distinct_types >= 10:
        c5_score += 5
        c5_parts.append(f">=10 types (got {distinct_types})")
    
    if file_changed:
        c5_score += 5
        c5_parts.append("file modified")
        
    score += c5_score
    if c5_score == 15:
        feedback_parts.append(f"PASS C5: diversity and volume ({', '.join(c5_parts)}) [+15]")
    elif c5_score > 0:
        feedback_parts.append(f"PARTIAL C5: diversity and volume ({', '.join(c5_parts)}) [+{c5_score}]")
    else:
        feedback_parts.append("FAIL C5: need >=40 total items, >=10 types, and modified file")

    # ── Final Verdict ─────────────────────────────────────────────────────────
    pass_threshold = task_info.get("metadata", {}).get("pass_threshold", 70)
    passed = score >= pass_threshold
    
    summary = (
        f"Score: {score}/100 | "
        f"Metrics: {furniture_count} total items, {decor_count} decor items, {new_walls} walls added."
    )
    feedback_parts.insert(0, summary)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }