#!/usr/bin/env python3
"""
Verifier for branch_library_conversion task.

Scoring (total 100 pts, pass threshold 70):
  C1 (25 pts): Reference stacks -- >=10 shelving units (partial >=5 -> 12)
  C2 (25 pts): Reading/study furniture -- >=6 tables + >=12 chairs (partial >=3+6 -> 12)
  C3 (20 pts): Zone identification -- >=4 rooms defined with names OR labels + >=2 rooms with distinct floorColor/floorTexture (partial >=2 OR >=1 -> 10)
  C4 (15 pts): Service desk + ambient -- >=2 desks + >=4 lamps + >=3 plants/decor (partial >=1+2+0 -> 7)
  C5 (15 pts): Labels + total + file saved -- >=3 text labels (5) + >=40 total furniture items (5) + file changed (5)
  
Wrong-target gate: if total furniture < 8, return score=0 immediately.
"""

import json

def verify_branch_library_conversion(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if copy_from_env is None:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        result_path = copy_from_env("/tmp/branch_library_conversion_result.json")
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

    shelves = result.get("shelves", 0)
    tables = result.get("tables", 0)
    chairs = result.get("chairs", 0)
    desks = result.get("desks", 0)
    lamps = result.get("lamps", 0)
    plants_decor = result.get("plants_decor", 0)
    
    # We define "named zones" as the number of rooms with explicit names PLUS text labels placed on the plan
    named_zones = result.get("rooms_with_names", 0) + result.get("labels_count", 0)
    distinct_floor_colors = result.get("distinct_floor_colors", 0)
    labels = result.get("labels_count", 0)
    file_changed = result.get("file_changed", False)

    # C1 (25 pts): Reference stacks
    if shelves >= 10:
        score += 25
        feedback_parts.append(f"PASS C1: {shelves} shelving units found (>=10 required) [+25]")
    elif shelves >= 5:
        score += 12
        feedback_parts.append(f"PARTIAL C1: {shelves} shelving units found (need >=10 for full credit) [+12]")
    else:
        feedback_parts.append(f"FAIL C1: only {shelves} shelving units found (need >=10)")

    # C2 (25 pts): Reading/study furniture
    if tables >= 6 and chairs >= 12:
        score += 25
        feedback_parts.append(f"PASS C2: reading furniture ({tables} tables, {chairs} chairs) [+25]")
    elif tables >= 3 and chairs >= 6:
        score += 12
        feedback_parts.append(f"PARTIAL C2: reading furniture ({tables} tables, {chairs} chairs) [+12]")
    else:
        feedback_parts.append(f"FAIL C2: reading furniture needs >=6 tables + >=12 chairs (got {tables}, {chairs})")

    # C3 (20 pts): Zone identification
    if named_zones >= 4 and distinct_floor_colors >= 2:
        score += 20
        feedback_parts.append(f"PASS C3: zone identification ({named_zones} named/labeled zones, {distinct_floor_colors} distinct floor colors) [+20]")
    elif named_zones >= 2 or distinct_floor_colors >= 1:
        score += 10
        feedback_parts.append(f"PARTIAL C3: partial zone identification ({named_zones} named/labeled zones, {distinct_floor_colors} floor colors) [+10]")
    else:
        feedback_parts.append(f"FAIL C3: zone identification needs >=4 named/labeled zones and >=2 floor colors")

    # C4 (15 pts): Service desk + ambient
    if desks >= 2 and lamps >= 4 and plants_decor >= 3:
        score += 15
        feedback_parts.append(f"PASS C4: service+ambient ({desks} desks, {lamps} lamps, {plants_decor} decor) [+15]")
    elif desks >= 1 and (lamps >= 2 or plants_decor >= 2):
        score += 7
        feedback_parts.append(f"PARTIAL C4: partial service+ambient ({desks} desks, {lamps} lamps, {plants_decor} decor) [+7]")
    else:
        feedback_parts.append(f"FAIL C4: service+ambient needs >=2 desks, >=4 lamps, >=3 decor items")

    # C5 (15 pts): Labels + total + file saved
    c5_score = 0
    c5_parts = []
    if labels >= 3:
        c5_score += 5
        c5_parts.append(f"{labels} labels")
    if furniture_count >= 40:
        c5_score += 5
        c5_parts.append(f"{furniture_count} total furniture")
    if file_changed:
        c5_score += 5
        c5_parts.append("file modified")
    
    score += c5_score
    if c5_score == 15:
        feedback_parts.append(f"PASS C5: {', '.join(c5_parts)} [+15]")
    elif c5_score > 0:
        feedback_parts.append(f"PARTIAL C5: {', '.join(c5_parts)} [+{c5_score}]")
    else:
        feedback_parts.append(f"FAIL C5: need >=3 labels, >=40 furniture, file changed")

    passed = score >= 70
    summary = f"Score: {score}/100 | Furniture: {furniture_count} items (shelves={shelves}, tables={tables}, chairs={chairs}, desks={desks})"
    feedback_parts.insert(0, summary)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }