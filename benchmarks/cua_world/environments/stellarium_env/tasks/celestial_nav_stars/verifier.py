#!/usr/bin/env python3
"""
Verifier for celestial_nav_stars task.

Checks:
1. Location latitude correct (12 pts)
2. Location longitude correct (8 pts)
3. Azimuthal grid enabled (10 pts)
4. Constellation lines enabled (10 pts)
5. Atmosphere enabled (8 pts)
6. Ground/landscape disabled (8 pts)
7. Cardinal points enabled (4 pts)
8. 4+ screenshots captured (25 pts)
9. Navigation log file exists with content (15 pts)

Pass threshold: 65 points
"""

import json
import tempfile
import os
import math
import logging

logger = logging.getLogger(__name__)

EXPECTED_LAT_RAD = 0.5236    # 30.00° N
EXPECTED_LON_RAD = -0.6981   # 40.00° W
LAT_LON_TOLERANCE_RAD = 0.05 # ~2.8 degrees tolerance
TARGETS = ["sirius", "canopus", "polaris", "jupiter"]


def verify_celestial_nav_stars(traj, env_info, task_info):
    """Verify celestial navigation task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env function unavailable"}

    task_name = "celestial_nav_stars"

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
        
        # ── Criteria 1 & 2: Location (20 pts total) ─────────────────────────
        lat_rad = result.get('lat_rad')
        lon_rad = result.get('lon_rad')

        if lat_rad is not None and lon_rad is not None:
            lat_diff = abs(lat_rad - EXPECTED_LAT_RAD)
            lon_diff = abs(lon_rad - EXPECTED_LON_RAD)

            if lat_diff <= LAT_LON_TOLERANCE_RAD:
                score += 12
                feedback_parts.append(f"Latitude correct (~{math.degrees(lat_rad):.1f}°N)")
            else:
                feedback_parts.append(f"Latitude incorrect (expected ~30°N, got {math.degrees(lat_rad):.1f}°)")

            if lon_diff <= LAT_LON_TOLERANCE_RAD:
                score += 8
                feedback_parts.append(f"Longitude correct (~{math.degrees(lon_rad):.1f}°E/W)")
            else:
                feedback_parts.append(f"Longitude incorrect (expected ~40°W, got {math.degrees(lon_rad):.1f}°)")
        else:
            feedback_parts.append("Location config missing")

        # ── Criterion 3: Azimuthal Grid (10 pts) ────────────────────────────
        if result.get('flag_azimuthal_grid') is True:
            score += 10
            feedback_parts.append("Azimuthal grid enabled")
        else:
            feedback_parts.append("Azimuthal grid not enabled")

        # ── Criterion 4: Constellation lines (10 pts) ───────────────────────
        if result.get('flag_constellation_drawing') is True:
            score += 10
            feedback_parts.append("Constellation lines enabled")
        else:
            feedback_parts.append("Constellation lines not enabled")

        # ── Criterion 5: Atmosphere enabled (8 pts) ─────────────────────────
        if result.get('flag_atmosphere') is True:
            score += 8
            feedback_parts.append("Atmosphere enabled")
        else:
            feedback_parts.append("Atmosphere not enabled")

        # ── Criterion 6: Landscape disabled (8 pts) ─────────────────────────
        if result.get('flag_landscape') is False:
            score += 8
            feedback_parts.append("Landscape/ground disabled")
        else:
            feedback_parts.append("Landscape/ground not disabled")

        # ── Criterion 7: Cardinal Points (4 pts) ────────────────────────────
        if result.get('flag_cardinal_points') is True:
            score += 4
            feedback_parts.append("Cardinal points enabled")
        else:
            feedback_parts.append("Cardinal points not enabled")

        # ── Criterion 8: Screenshots (25 pts) ───────────────────────────────
        ss_count = result.get('new_screenshot_count', 0)
        if ss_count >= 4:
            score += 25
            feedback_parts.append(f"Screenshots captured: {ss_count}/4")
        else:
            pts = int((ss_count / 4) * 25)
            score += pts
            feedback_parts.append(f"Screenshots captured: {ss_count}/4 (Partial credit: {pts} pts)")

        # ── Criterion 9: Log File (15 pts) ──────────────────────────────────
        log_exists = result.get('log_exists', False)
        log_content = result.get('log_content', '').lower()
        
        if log_exists:
            found_targets = [t for t in TARGETS if t in log_content]
            if len(found_targets) == 4:
                score += 15
                feedback_parts.append("Log file contains all required targets")
            else:
                pts = int((len(found_targets) / 4) * 15)
                score += pts
                feedback_parts.append(f"Log file missing targets. Found {len(found_targets)}/4. (Partial credit: {pts} pts)")
        else:
            feedback_parts.append("Navigation log file not created")

        # ── Final determination ──────────────────────────────────────────────
        passed = score >= 65
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification encountered an error: {str(e)}"
        }