#!/usr/bin/env python3
"""
Verifier for coral_spawning_lunar_plan task.

Scoring (100 points):
- Location Configured: Lat/Lon correctly set to Lizard Island (-14.668, 145.459) (25 pts)
- Landscape Set to Ocean: landscape_name = ocean (20 pts)
- Azimuthal Grid Enabled: flag_azimuthal_grid = true (15 pts)
- Reference Screenshots: >= 2 new screenshots (20 pts)
- Dive Plan Document: exists and contains keywords (20 pts)

Pass Threshold: 75 points.
"""

import json
import tempfile
import os
import math
import logging

logger = logging.getLogger(__name__)

# Lizard Island Research Station ground truth
LIZARD_LAT_RAD = -0.25599   # -14.668 degrees
LIZARD_LON_RAD = 2.53874    # 145.459 degrees
LAT_LON_TOLERANCE_RAD = 0.10  # ~5.7 degrees tolerance


def verify_coral_spawning_lunar_plan(traj, env_info, task_info):
    """
    Verify coral spawning lunar planning task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env function unavailable"}

    task_name = "coral_spawning_lunar_plan"

    try:
        # Copy result JSON from VM
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

        # ── Criterion 1: Location Configured (25 pts) ─────────────────────────
        lat_rad = result.get('lat_rad')
        lon_rad = result.get('lon_rad')

        if lat_rad is not None and lon_rad is not None:
            lat_diff = abs(lat_rad - LIZARD_LAT_RAD)
            lon_diff = abs(lon_rad - LIZARD_LON_RAD)

            if lat_diff <= LAT_LON_TOLERANCE_RAD and lon_diff <= LAT_LON_TOLERANCE_RAD:
                score += 25
                subscores["location"] = True
                feedback_parts.append(f"Lizard Island location set (lat={math.degrees(lat_rad):.2f}°, lon={math.degrees(lon_rad):.2f}°)")
            else:
                subscores["location"] = False
                feedback_parts.append(f"Wrong location: lat={math.degrees(lat_rad):.2f}°, lon={math.degrees(lon_rad):.2f}° (expected ~-14.67°S, ~145.46°E)")
        else:
            subscores["location"] = False
            feedback_parts.append("Location not found in config")

        # ── Criterion 2: Landscape Set to Ocean (20 pts) ──────────────────────
        landscape_name = result.get('landscape_name', '').lower()
        if landscape_name == 'ocean':
            score += 20
            subscores["landscape"] = True
            feedback_parts.append("Landscape successfully set to 'ocean'")
        else:
            subscores["landscape"] = False
            feedback_parts.append(f"Landscape not set to 'ocean' (found '{landscape_name}')")

        # ── Criterion 3: Azimuthal Grid Enabled (15 pts) ──────────────────────
        flag_az = result.get('flag_azimuthal_grid')
        if flag_az is True:
            score += 15
            subscores["azimuthal_grid"] = True
            feedback_parts.append("Azimuthal coordinate grid enabled")
        else:
            subscores["azimuthal_grid"] = False
            feedback_parts.append("Azimuthal grid not enabled")

        # ── Criterion 4: Reference Screenshots (20 pts) ───────────────────────
        new_ss = result.get('new_screenshot_count', 0)
        if new_ss >= 2:
            score += 20
            subscores["screenshots"] = True
            feedback_parts.append(f"{new_ss} reference screenshots captured")
        elif new_ss == 1:
            score += 10
            subscores["screenshots"] = False
            feedback_parts.append("Only 1 screenshot captured (partial; required: 2)")
        else:
            subscores["screenshots"] = False
            feedback_parts.append("No screenshots taken")

        # ── Criterion 5: Dive Plan Document (20 pts) ──────────────────────────
        plan_exists = result.get('dive_plan_exists', False)
        has_lizard = result.get('has_lizard', False)
        has_moon = result.get('has_moon', False)
        has_crux = result.get('has_crux', False)

        if plan_exists:
            missing_keywords = []
            if not has_lizard: missing_keywords.append("Lizard Island")
            if not has_moon: missing_keywords.append("Moon")
            if not has_crux: missing_keywords.append("Crux/Southern Cross")

            if len(missing_keywords) == 0:
                score += 20
                subscores["dive_plan"] = True
                feedback_parts.append("Dive plan written with all required keywords")
            else:
                # Partial credit depending on how many keywords were caught
                points_per_kw = 20 / 3
                score += int(points_per_kw * (3 - len(missing_keywords)))
                subscores["dive_plan"] = False
                feedback_parts.append(f"Dive plan missing keywords: {', '.join(missing_keywords)}")
        else:
            subscores["dive_plan"] = False
            feedback_parts.append("Dive plan file (dive_plan.txt) not created")

        # ── Final evaluation ─────────────────────────────────────────────────
        passed = score >= 75
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": subscores
        }

    except Exception as e:
        logger.error(f"Verification failed: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification script error: {str(e)}"}