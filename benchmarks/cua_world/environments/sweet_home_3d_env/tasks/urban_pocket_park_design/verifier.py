#!/usr/bin/env python3
"""
Verifier for urban_pocket_park_design task.

Occupation: Urban Planner
Industry: Civic Planning

Features required: terrain zoning (rooms + floor colors), vegetation placement, 
public amenities (benches/lights), dimension annotations, and 3D photo rendering.

Scoring (total 100 pts, pass threshold 70):
  C1 (20 pts): Terrain Zoning -- >=3 rooms with names, >=2 with distinct floor treatments
  C2 (20 pts): Vegetation Density -- >=12 plants/trees/bushes
  C3 (20 pts): Public Amenities -- >=6 seats/benches AND >=4 lights
  C4 (15 pts): Code Dimensions -- >=2 dimension lines
  C5 (25 pts): Render & Save -- pocket_park_final.sh3d modified/saved + presentation PNG exists

Wrong-target gate: if total furniture < 15, return score=0.
"""

import json

def verify_urban_pocket_park_design(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if copy_from_env is None:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        result_path = copy_from_env("/tmp/urban_pocket_park_design_result.json")
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
                f"Wrong-target gate: only {furniture_count} item(s) found in the park. "
                "At least 15 items required to qualify for scoring."
            )
        }

    room_count = result.get("room_count", 0)
    room_names = result.get("room_names", [])
    rooms_with_floor_color = result.get("rooms_with_floor_color", 0)
    veg_count = result.get("veg_count", 0)
    seat_count = result.get("seat_count", 0)
    light_count = result.get("light_count", 0)
    dimension_count = result.get("dimension_count", 0)
    photo_found = result.get("photo_found", False)
    file_changed = result.get("file_changed", False)

    # ── Criterion 1 (20 pts): Terrain Zoning ──────────────────────────────────
    # Requires >=3 named rooms and >=2 with floor color/texture
    named_rooms = len(room_names)
    if named_rooms >= 3 and rooms_with_floor_color >= 2:
        score += 20
        feedback_parts.append(f"PASS C1: terrain zones ({named_rooms} named zones, {rooms_with_floor_color} with surface texture) [+20]")
    elif named_rooms >= 2 or rooms_with_floor_color >= 1:
        score += 10
        feedback_parts.append(f"PARTIAL C1: partial zoning ({named_rooms} named zones, {rooms_with_floor_color} with surface texture) [+10]")
    else:
        feedback_parts.append(f"FAIL C1: terrain zones need >=3 names and >=2 floor textures (got {named_rooms}, {rooms_with_floor_color})")

    # ── Criterion 2 (20 pts): Vegetation Density ──────────────────────────────
    if veg_count >= 12:
        score += 20
        feedback_parts.append(f"PASS C2: vegetation density ({veg_count} plants/trees) [+20]")
    elif veg_count >= 6:
        score += 10
        feedback_parts.append(f"PARTIAL C2: partial vegetation ({veg_count} plants/trees) [+10]")
    else:
        feedback_parts.append(f"FAIL C2: vegetation density needs >=12 plants/trees (got {veg_count})")

    # ── Criterion 3 (20 pts): Public Amenities ────────────────────────────────
    if seat_count >= 6 and light_count >= 4:
        score += 20
        feedback_parts.append(f"PASS C3: public amenities ({seat_count} seats, {light_count} lights) [+20]")
    elif seat_count >= 3 and light_count >= 2:
        score += 10
        feedback_parts.append(f"PARTIAL C3: partial amenities ({seat_count} seats, {light_count} lights) [+10]")
    elif seat_count >= 6 or light_count >= 4:
        score += 10
        feedback_parts.append(f"PARTIAL C3: missing one amenity type ({seat_count} seats, {light_count} lights) [+10]")
    else:
        feedback_parts.append(f"FAIL C3: amenities need >=6 seats and >=4 lights (got {seat_count}, {light_count})")

    # ── Criterion 4 (15 pts): Code Dimensions ─────────────────────────────────
    if dimension_count >= 2:
        score += 15
        feedback_parts.append(f"PASS C4: pathway dimensions ({dimension_count} dimension lines) [+15]")
    elif dimension_count >= 1:
        score += 7
        feedback_parts.append(f"PARTIAL C4: partial dimensions ({dimension_count} dimension lines) [+7]")
    else:
        feedback_parts.append(f"FAIL C4: no dimension lines found (need >=2)")

    # ── Criterion 5 (25 pts): Render & Save ───────────────────────────────────
    c5_score = 0
    c5_parts = []
    
    if file_changed:
        c5_score += 10
        c5_parts.append("project saved")
    
    if photo_found:
        c5_score += 15
        c5_parts.append("3D render exported")

    score += c5_score
    if c5_score == 25:
        feedback_parts.append(f"PASS C5: output artifacts ({', '.join(c5_parts)}) [+25]")
    elif c5_score > 0:
        feedback_parts.append(f"PARTIAL C5: missing some outputs ({', '.join(c5_parts)}) [+{c5_score}]")
    else:
        feedback_parts.append(f"FAIL C5: neither file saved nor presentation rendered")

    # ── VLM Visual Verification (Anti-Gaming Overlay) ──────────────────────────
    # Extra check using VLM to ensure work happened during trajectory
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
    frames = sample_trajectory_frames(traj, n=3)
    
    vlm_feedback = ""
    if frames:
        prompt = (
            "You are observing a user operating Sweet Home 3D to design an outdoor pocket park. "
            "Does the workspace show them adding outdoor vegetation (trees/plants), placing paths, "
            "and creating an outdoor layout? Answer 'yes' or 'no'."
        )
        vlm_res = query_vlm(images=frames, prompt=prompt)
        if vlm_res and 'yes' in vlm_res.get('response', '').lower():
            vlm_feedback = " [VLM confirmed outdoor park modeling trajectory]"
        else:
            vlm_feedback = " [VLM could not clearly confirm outdoor modeling trajectory]"

    # ── Final Verdict ─────────────────────────────────────────────────────────
    passed = score >= 70
    summary = (
        f"Score: {score}/100 | Furniture: {furniture_count} total "
        f"(veg={veg_count}, seats={seat_count}, lights={light_count})"
        f"{vlm_feedback}"
    )
    feedback_parts.insert(0, summary)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }