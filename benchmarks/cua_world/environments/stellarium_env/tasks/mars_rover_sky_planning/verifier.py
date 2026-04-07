#!/usr/bin/env python3
"""
Verifier for mars_rover_sky_planning task.

Scoring (100 points):
- Planet set to Mars: 20 pts
- Latitude near Jezero Crater (18.44°N ≈ 0.3218 rad): 10 pts
- Atmosphere disabled: 10 pts
- Ground/landscape disabled: 5 pts
- Constellation lines enabled: 10 pts
- Constellation labels enabled: 5 pts
- Planet labels enabled: 5 pts
- 3+ new screenshots taken: 20 pts
- Mars sky notes file written with correct content: 15 pts

Pass threshold: 70 points
"""

import json
import tempfile
import os
import math
import logging

logger = logging.getLogger(__name__)

# Jezero Crater, Mars Ground Truth
MARS_LAT_RAD = 0.3218     # 18.44 degrees N
LAT_LON_TOLERANCE_RAD = 0.10  # ~5.7 degrees tolerance

def verify_mars_rover_sky(traj, env_info, task_info):
    """Verify Mars sky simulation planning task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env function unavailable"}

    task_name = "mars_rover_sky_planning"

    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp:
            tmp_path = tmp.name

        try:
            copy_from_env(f"/tmp/{task_name}_result.json", tmp_path)
            with open(tmp_path, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)

        score = 0
        feedback_parts = []
        subscores = {}

        # ── Criterion 1: Planet set to Mars (20 pts) ─────────────────────────
        planet = result.get('planet', '')
        if planet and planet.strip().lower() == "mars":
            score += 20
            subscores["planet"] = True
            feedback_parts.append("Observer planet correctly set to Mars")
        else:
            subscores["planet"] = False
            feedback_parts.append(f"Observer planet not set to Mars (found: '{planet}')")

        # ── Criterion 2: Latitude near Jezero Crater (10 pts) ─────────────────
        lat_rad = result.get('lat_rad')
        
        if lat_rad is not None:
            lat_diff = abs(lat_rad - MARS_LAT_RAD)
            if lat_diff <= LAT_LON_TOLERANCE_RAD:
                score += 10
                subscores["location"] = True
                feedback_parts.append(f"Jezero Crater latitude set (lat={math.degrees(lat_rad):.2f}°N)")
            else:
                subscores["location"] = False
                feedback_parts.append(
                    f"Wrong latitude: lat={math.degrees(lat_rad):.2f}° "
                    f"(expected ~18.44°N for Jezero Crater)"
                )
        else:
            subscores["location"] = False
            feedback_parts.append("Latitude not found in config")

        # ── Criterion 3: Atmosphere disabled (10 pts) ─────────────────────────
        flag_atm = result.get('flag_atmosphere')
        if flag_atm is False:
            score += 10
            subscores["atmosphere_off"] = True
            feedback_parts.append("Atmosphere disabled")
        else:
            subscores["atmosphere_off"] = False
            feedback_parts.append(f"Atmosphere not disabled (flag_atmosphere={flag_atm})")

        # ── Criterion 4: Ground disabled (5 pts) ──────────────────────────────
        flag_land = result.get('flag_landscape')
        if flag_land is False:
            score += 5
            subscores["landscape_off"] = True
            feedback_parts.append("Ground/Landscape disabled")
        else:
            subscores["landscape_off"] = False
            feedback_parts.append(f"Ground not disabled (flag_landscape={flag_land})")

        # ── Criterion 5: Constellation lines enabled (10 pts) ─────────────────
        flag_lines = result.get('flag_constellation_drawing')
        if flag_lines is True:
            score += 10
            subscores["constellation_lines"] = True
            feedback_parts.append("Constellation lines enabled")
        else:
            subscores["constellation_lines"] = False
            feedback_parts.append("Constellation lines not enabled")

        # ── Criterion 6: Constellation labels enabled (5 pts) ─────────────────
        flag_names = result.get('flag_constellation_name')
        if flag_names is True:
            score += 5
            subscores["constellation_names"] = True
            feedback_parts.append("Constellation labels enabled")
        else:
            subscores["constellation_names"] = False
            feedback_parts.append("Constellation labels not enabled")

        # ── Criterion 7: Planet labels enabled (5 pts) ────────────────────────
        flag_planets = result.get('flag_planets_labels')
        if flag_planets is True:
            score += 5
            subscores["planet_labels"] = True
            feedback_parts.append("Planet labels enabled")
        else:
            subscores["planet_labels"] = False
            feedback_parts.append("Planet labels not enabled")

        # ── Criterion 8: 3+ screenshots taken (20 pts) ───────────────────────
        new_ss = result.get('new_screenshot_count', 0)
        if new_ss >= 3:
            score += 20
            subscores["screenshots"] = True
            feedback_parts.append(f"{new_ss} reference screenshots captured")
        elif new_ss > 0:
            score += int((new_ss / 3) * 20)
            subscores["screenshots"] = False
            feedback_parts.append(f"Only {new_ss} screenshots captured (partial; required: 3)")
        else:
            subscores["screenshots"] = False
            feedback_parts.append("No screenshots captured")

        # ── Criterion 9: Notes file (15 pts) ──────────────────────────────────
        notes_exists = result.get('notes_exists', False)
        has_mars = result.get('notes_has_mars', False)
        has_targets = result.get('notes_has_earth_or_saturn', False)

        if notes_exists and has_mars and has_targets:
            score += 15
            subscores["notes"] = True
            feedback_parts.append("Notes file written with valid content")
        elif notes_exists:
            score += 5
            subscores["notes"] = False
            feedback_parts.append("Notes file written but missing expected keywords (Mars, Earth/Saturn)")
        else:
            subscores["notes"] = False
            feedback_parts.append("Notes file not found")

        # ── Final Assessment ──────────────────────────────────────────────────
        passed = score >= 70

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": subscores
        }

    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification encountered an error: {str(e)}"
        }