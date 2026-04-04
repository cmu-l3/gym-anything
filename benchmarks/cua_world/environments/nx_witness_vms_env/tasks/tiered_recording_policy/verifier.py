#!/usr/bin/env python3
"""
Verifier for tiered_recording_policy task.

Scenario: Security integrator configuring three cameras with different recording tiers.
  - Parking Lot Camera: always-on, 25 fps, high quality (Tier 1 exterior)
  - Entrance Camera:    always-on, 15 fps, high quality (Tier 1 entry)
  - Server Room Camera: motion/metadata+low quality, 10 fps  (Tier 2 interior)
  - Layout 'Security Operations Center' with all 3 cameras

Scoring (100 points):
  - Parking Lot Camera: continuous recording (always), fps >= 20      : 20 pts
  - Entrance Camera:    continuous recording (always), fps >= 10      : 20 pts
  - Server Room Camera: motion/metadata recording, NOT always-on      : 20 pts
  - Layout 'Security Operations Center' created                       : 10 pts
  - Layout contains all 3 cameras                                     : 30 pts

Pass threshold: 70 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/tiered_recording_policy_result.json"


def verify_tiered_recording_policy(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        try:
            copy_from_env(RESULT_PATH, tmp.name)
            with open(tmp.name, "r") as f:
                result = json.load(f)
        finally:
            try:
                os.unlink(tmp.name)
            except Exception:
                pass
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found — export script may not have run",
        }
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    score = 0
    feedback_parts = []

    def sched_is_active(s):
        return s.get("is_enabled", False) and s.get("task_count", 0) > 0

    def sched_covers_week(s):
        return s.get("days_covered", 0) >= 5

    # --- Subtask 1: Parking Lot Camera — always-on, >= 20 fps ---
    parking = result.get("parking_lot_schedule", {})
    p_ok_type = parking.get("has_always", False)
    p_fps = max(parking.get("fps_values", [0]) or [0])
    p_ok_fps = p_fps >= 20

    if sched_is_active(parking) and p_ok_type and p_ok_fps and sched_covers_week(parking):
        score += 20
        feedback_parts.append(f"Parking Lot Camera: always-on, {p_fps} fps, full week (20/20)")
    elif sched_is_active(parking) and p_ok_type:
        score += 12
        feedback_parts.append(
            f"Parking Lot Camera: always-on recording but fps={p_fps} (expected >=20) "
            f"or incomplete week (12/20)"
        )
    elif sched_is_active(parking):
        score += 6
        feedback_parts.append(
            f"Parking Lot Camera: recording enabled but not always-on type "
            f"(types={parking.get('recording_types', [])}) (6/20)"
        )
    else:
        feedback_parts.append("Parking Lot Camera: recording NOT configured (0/20)")

    # --- Subtask 2: Entrance Camera — always-on, >= 10 fps ---
    entrance = result.get("entrance_schedule", {})
    e_ok_type = entrance.get("has_always", False)
    e_fps = max(entrance.get("fps_values", [0]) or [0])
    e_ok_fps = e_fps >= 10

    if sched_is_active(entrance) and e_ok_type and e_ok_fps and sched_covers_week(entrance):
        score += 20
        feedback_parts.append(f"Entrance Camera: always-on, {e_fps} fps, full week (20/20)")
    elif sched_is_active(entrance) and e_ok_type:
        score += 12
        feedback_parts.append(
            f"Entrance Camera: always-on but fps={e_fps} (expected >=10) "
            f"or incomplete week (12/20)"
        )
    elif sched_is_active(entrance):
        score += 6
        feedback_parts.append(
            f"Entrance Camera: recording enabled but not always-on type "
            f"(types={entrance.get('recording_types', [])}) (6/20)"
        )
    else:
        feedback_parts.append("Entrance Camera: recording NOT configured (0/20)")

    # --- Subtask 3: Server Room Camera — motion/metadata recording (NOT always-on) ---
    server = result.get("server_room_schedule", {})
    s_has_motion = server.get("has_motion", False)
    s_not_always = not server.get("has_always", False)

    if sched_is_active(server) and s_has_motion and s_not_always:
        score += 20
        feedback_parts.append(
            f"Server Room Camera: motion/metadata recording configured correctly (20/20)"
        )
    elif sched_is_active(server) and s_has_motion:
        score += 12
        feedback_parts.append(
            "Server Room Camera: has motion recording but also has always-on — "
            "should be motion-only for storage savings (12/20)"
        )
    elif sched_is_active(server):
        score += 6
        feedback_parts.append(
            f"Server Room Camera: recording enabled but wrong type "
            f"(types={server.get('recording_types', [])}, expected motion/metadata) (6/20)"
        )
    else:
        feedback_parts.append("Server Room Camera: recording NOT configured (0/20)")

    # --- Subtask 4: Layout 'Security Operations Center' created ---
    layout_check = result.get("layout_check", {})
    layout_found = layout_check.get("layout_found", False)
    cameras_matched = layout_check.get("cameras_matched", 0)

    if layout_found:
        score += 10
        feedback_parts.append("'Security Operations Center' layout created (10/10)")
    else:
        feedback_parts.append("'Security Operations Center' layout NOT found (0/10)")

    # --- Subtask 5: Layout contains all 3 cameras ---
    if layout_found and cameras_matched >= 3:
        score += 30
        feedback_parts.append("Layout contains all 3 cameras (30/30)")
    elif layout_found and cameras_matched == 2:
        score += 15
        feedback_parts.append(f"Layout contains 2 of 3 cameras (15/30)")
    elif layout_found and cameras_matched == 1:
        score += 7
        feedback_parts.append(f"Layout contains only 1 of 3 cameras (7/30)")
    else:
        feedback_parts.append("Layout empty or no recognized cameras (0/30)")

    passed = score >= 70
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts),
    }
