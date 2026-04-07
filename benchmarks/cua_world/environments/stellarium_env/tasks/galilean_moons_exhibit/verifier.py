#!/usr/bin/env python3
"""
Verifier for galilean_moons_exhibit task.

Scoring (100 points):
- Location explicitly saved to config (Padua, Italy): 20 pts
- Display settings explicitly saved (atmosphere/landscape OFF): 20 pts
- 2+ screenshots captured: 30 pts
- Exhibit notes written containing required keywords: 30 pts

Pass threshold: 70 points
"""

import json
import tempfile
import os
import math
import logging

logger = logging.getLogger(__name__)

# Ground truth for Padua, Italy
PADUA_LAT_RAD = 0.79249  # 45.4064° N
PADUA_LON_RAD = 0.20729  # 11.8768° E
TOLERANCE_RAD = 0.05


def verify_galilean_moons_exhibit(traj, env_info, task_info):
    """
    Verify historical reconstruction and exhibit notes task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    task_name = "galilean_moons_exhibit"
    
    with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp:
        tmp_path = tmp.name

    try:
        copy_from_env(f"/tmp/{task_name}_result.json", tmp_path)
        with open(tmp_path, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)

    score = 0
    feedback_parts = []
    config = result.get('config', {})
    
    # ── Criterion 1: Location Explicitly Saved (20 pts) ───────────────────────
    # We check init_location (returned as lat_rad/lon_rad) to verify "Save settings" was clicked
    lat_rad = config.get('lat_rad')
    lon_rad = config.get('lon_rad')
    
    if lat_rad is not None and lon_rad is not None and lat_rad != -999:
        if abs(lat_rad - PADUA_LAT_RAD) <= TOLERANCE_RAD and abs(lon_rad - PADUA_LON_RAD) <= TOLERANCE_RAD:
            score += 20
            feedback_parts.append(f"Padua location explicitly saved (lat: {math.degrees(lat_rad):.2f}°)")
        else:
            feedback_parts.append(f"Saved location incorrect (lat: {math.degrees(lat_rad):.2f}°, expected 45.41°)")
    else:
        feedback_parts.append("Location not permanently saved in configuration (did you click 'Save settings'?)")

    # ── Criterion 2: Display settings Explicitly Saved (20 pts) ───────────────
    flag_atm = config.get('flag_atmosphere')
    flag_land = config.get('flag_landscape')
    
    if flag_atm is False and flag_land is False:
        score += 20
        feedback_parts.append("Atmosphere and landscape states correctly saved")
    else:
        feedback_parts.append(f"Display settings not saved correctly (atmosphere: {flag_atm}, landscape: {flag_land})")

    # ── Criterion 3: 2+ Screenshots Captured (30 pts) ─────────────────────────
    new_ss = result.get('new_screenshot_count', 0)
    if new_ss >= 2:
        score += 30
        feedback_parts.append(f"{new_ss} observation screenshots captured")
    elif new_ss == 1:
        score += 15
        feedback_parts.append("Only 1 screenshot captured (expected 2)")
    else:
        feedback_parts.append("No screenshots captured")

    # ── Criterion 4: Exhibit Notes Text (30 pts) ─────────────────────────────
    notes_exists = result.get('notes_exists', False)
    notes_content = result.get('notes_content', "").lower()
    
    if notes_exists:
        keywords = ["padua", "1610", "io", "europa", "ganymede", "callisto"]
        found = [k for k in keywords if k in notes_content]
        
        if len(found) == len(keywords):
            score += 30
            feedback_parts.append("Exhibit notes contain all 6 required historical keywords")
        else:
            partial_score = int(30 * (len(found) / len(keywords)))
            score += partial_score
            missing = [k for k in keywords if k not in found]
            feedback_parts.append(f"Exhibit notes missing keywords: {', '.join(missing)}")
    else:
        feedback_parts.append("Exhibit notes file was not created or modified during task")

    passed = score >= 70 and notes_exists and new_ss >= 1
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }