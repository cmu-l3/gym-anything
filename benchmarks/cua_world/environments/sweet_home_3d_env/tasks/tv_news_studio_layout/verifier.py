#!/usr/bin/env python3
"""
Verifier for tv_news_studio_layout task.

Occupation: Broadcast Set Designer
Industry: Media & Broadcasting

Features required: furniture_placement, room_definition, wall_creation, elevation adjustment.

Scoring (total 100 pts, pass threshold 70):
  C1 (20 pts): Zoned Layout -- >=3 new partition walls + >=4 named rooms.
  C2 (20 pts): Studio Floor Set -- >=1 desk + >=2 chairs + >=4 lamps.
  C3 (25 pts): Control Room Console -- >=3 desks/tables + >=6 screens/computers.
  C4 (15 pts): Wall-Mounted Monitors -- >=4 screens with elevation >= 80cm.
  C5 (20 pts): Talent Prep & Save -- >=1 sofa + >=1 sink + >=40 total furniture + file modified.

Wrong-target gate: if total furniture < 15, return score=0.
"""

import json
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_tv_news_studio_layout(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if copy_from_env is None:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        result_path = copy_from_env("/tmp/tv_news_studio_layout_result.json")
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

    new_walls = result.get("new_walls", 0)
    room_names = result.get("room_names", [])
    desk_count = result.get("desk_count", 0)
    chair_count = result.get("chair_count", 0)
    screen_count = result.get("screen_count", 0)
    elevated_screens = result.get("elevated_screens", 0)
    lamp_count = result.get("lamp_count", 0)
    sofa_count = result.get("sofa_count", 0)
    sink_count = result.get("sink_count", 0)
    file_changed = result.get("file_changed", False)

    # ── C1 (20 pts): Zoned Layout ─────────────────────────────────────────────
    c1_score = 0
    c1_parts = []
    if new_walls >= 3:
        c1_score += 10
        c1_parts.append(f"{new_walls} new walls")
    if len(room_names) >= 4:
        c1_score += 10
        c1_parts.append(f"{len(room_names)} named rooms")
    
    score += c1_score
    if c1_score == 20:
        feedback_parts.append(f"PASS C1: Zoned Layout ({', '.join(c1_parts)}) [+20]")
    elif c1_score > 0:
        feedback_parts.append(f"PARTIAL C1: Zoned Layout needs >=3 walls and >=4 named rooms (got {new_walls} walls, {len(room_names)} rooms) [+{c1_score}]")
    else:
        feedback_parts.append(f"FAIL C1: Zoned Layout needs >=3 walls and >=4 named rooms (got {new_walls} walls, {len(room_names)} rooms)")

    # ── C2 (20 pts): Studio Floor Set ─────────────────────────────────────────
    if desk_count >= 1 and chair_count >= 2 and lamp_count >= 4:
        score += 20
        feedback_parts.append(f"PASS C2: Studio Set ({lamp_count} lamps, {desk_count} desks, {chair_count} chairs) [+20]")
    elif desk_count >= 1 and lamp_count >= 2:
        score += 10
        feedback_parts.append(f"PARTIAL C2: Studio Set partial ({lamp_count} lamps, {desk_count} desks) [+10]")
    else:
        feedback_parts.append(f"FAIL C2: Studio Set needs >=1 desk, >=2 chairs, >=4 lamps")

    # ── C3 (25 pts): Control Room Console ─────────────────────────────────────
    if desk_count >= 3 and screen_count >= 6:
        score += 25
        feedback_parts.append(f"PASS C3: Control Console ({desk_count} desks, {screen_count} screens) [+25]")
    elif desk_count >= 1 and screen_count >= 3:
        score += 12
        feedback_parts.append(f"PARTIAL C3: Control Console partial ({desk_count} desks, {screen_count} screens) [+12]")
    else:
        feedback_parts.append(f"FAIL C3: Control Console needs >=3 desks, >=6 screens")

    # ── C4 (15 pts): Wall-Mounted Monitors (Elevation) ────────────────────────
    if elevated_screens >= 4:
        score += 15
        feedback_parts.append(f"PASS C4: Wall-mounted monitors ({elevated_screens} screens with elevation >= 80cm) [+15]")
    elif elevated_screens >= 1:
        score += 7
        feedback_parts.append(f"PARTIAL C4: Wall-mounted monitors ({elevated_screens} screens elevated, need 4) [+7]")
    else:
        feedback_parts.append(f"FAIL C4: No monitors were wall-mounted (elevation >= 80cm)")

    # ── C5 (20 pts): Talent Prep & Total Requirements ─────────────────────────
    c5_score = 0
    c5_parts = []
    if sofa_count >= 1 and sink_count >= 1:
        c5_score += 10
        c5_parts.append(f"Talent Prep furnished")
    if furniture_count >= 40:
        c5_score += 5
        c5_parts.append(f"total items >= 40")
    if file_changed:
        c5_score += 5
        c5_parts.append("file modified")
        
    score += c5_score
    if c5_score == 20:
        feedback_parts.append(f"PASS C5: Extra requirements ({', '.join(c5_parts)}) [+20]")
    elif c5_score > 0:
        feedback_parts.append(f"PARTIAL C5: Extra requirements ({', '.join(c5_parts)}) [+{c5_score}]")
    else:
        feedback_parts.append(f"FAIL C5: Talent prep and total requirements not met")

    # ── Fallback VLM Check for Z-axis usage ───────────────────────────────────
    # We use VLM to verify that the agent actually interacted with the elevation dialog.
    # The programmatic check `elevated_screens >= 4` is strong, but VLM adds robustness.
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
    
    # We only run VLM check if they scored well on elevated screens, to ensure they didn't just place 
    # items that happen to have a high default elevation.
    vlm_feedback = ""
    if elevated_screens >= 1 and env_info.get("exec_in_env") is not None:
        frames = sample_trajectory_frames(traj, n=8)
        if frames:
            prompt = """Look at these screenshots from a user interacting with Sweet Home 3D.
            Did the user open a dialog box titled "Modify furniture" (or similar) to adjust the "Elevation" or "Z" property of an item?
            This verifies they actively changed the elevation of a TV/Monitor.
            Answer TRUE or FALSE."""
            vlm_res = query_vlm(images=frames, prompt=prompt)
            if vlm_res and "true" in vlm_res.get("response", "").lower():
                vlm_feedback = " | VLM confirmed manual elevation adjustment."
            else:
                # We don't penalize strictly as it's a supplementary check, but note it.
                vlm_feedback = " | VLM did not clearly see elevation dialog usage, but XML confirms elevation > 80cm."

    passed = score >= 70
    summary = (
        f"Score: {score}/100 | Furniture: {furniture_count} total "
        f"(desks={desk_count}, screens={screen_count}, elevated_screens={elevated_screens})"
    )
    feedback_parts.insert(0, summary)
    
    full_feedback = " | ".join(feedback_parts) + vlm_feedback

    return {
        "passed": passed,
        "score": score,
        "feedback": full_feedback
    }