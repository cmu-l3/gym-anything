#!/usr/bin/env python3
"""
Verifier for nocturnal_insect_navigation_plan task.

Scoring (100 points):
- Location configured: lat near -0.4703 rad (26.95°S): 20 pts
- Atmosphere disabled: flag_atmosphere = false: 10 pts
- Azimuthal Grid ON: flag_azimuthal_grid = true: 10 pts
- Galactic Grid ON: flag_galactic_grid = true: 20 pts
- Screenshot captured: 1+ new files: 20 pts
- Field Plan written: notes_exists & keywords: 20 pts

Pass threshold: 70 points, MUST include Galactic Grid and Field Plan.
"""

import json
import tempfile
import os
import math
import logging

logger = logging.getLogger(__name__)

# Kalahari research site ground truth
KALAHARI_LAT_RAD = -0.47037  # -26.95 degrees
KALAHARI_LON_RAD = 0.43162   # 24.73 degrees
LAT_LON_TOLERANCE_RAD = 0.10 # ~5.7 degrees tolerance


def verify_nocturnal_insect_navigation_plan(traj, env_info, task_info):
    """
    Verify insect navigation planetarium simulation task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env function unavailable"}

    task_name = "nocturnal_insect_navigation_plan"

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

        # ── Criterion 1: Location configured (20 pts) ──────────────
        lat_rad = result.get('lat_rad')
        lon_rad = result.get('lon_rad')

        if lat_rad is not None and lon_rad is not None:
            lat_diff = abs(lat_rad - KALAHARI_LAT_RAD)
            lon_diff = abs(lon_rad - KALAHARI_LON_RAD)

            if lat_diff <= LAT_LON_TOLERANCE_RAD and lon_diff <= LAT_LON_TOLERANCE_RAD:
                score += 20
                subscores["location"] = True
                feedback_parts.append(
                    f"Location set (lat={math.degrees(lat_rad):.2f}°, "
                    f"lon={math.degrees(lon_rad):.2f}°)"
                )
            else:
                subscores["location"] = False
                feedback_parts.append(
                    f"Wrong location: lat={math.degrees(lat_rad):.2f}°, "
                    f"lon={math.degrees(lon_rad):.2f}° "
                    f"(expected ~26.95°S, ~24.73°E)"
                )
        else:
            subscores["location"] = False
            feedback_parts.append("Location not found in config - did the agent save settings?")

        # ── Criterion 2: Atmosphere disabled (10 pts) ─────────────
        flag_atm = result.get('flag_atmosphere')
        if flag_atm is False:
            score += 10
            subscores["atmosphere_off"] = True
            feedback_parts.append("Atmosphere disabled")
        else:
            subscores["atmosphere_off"] = False
            feedback_parts.append(f"Atmosphere still enabled (flag_atmosphere={flag_atm})")

        # ── Criterion 3: Azimuthal Grid ON (10 pts) ─────────────────────
        flag_az = result.get('flag_azimuthal_grid')
        if flag_az is True:
            score += 10
            subscores["azimuthal_grid"] = True
            feedback_parts.append("Azimuthal grid enabled")
        else:
            subscores["azimuthal_grid"] = False
            feedback_parts.append(f"Azimuthal grid not enabled (flag_azimuthal_grid={flag_az})")

        # ── Criterion 4: Galactic Grid ON (20 pts) ─────────────────────────
        flag_gal = result.get('flag_galactic_grid')
        if flag_gal is True:
            score += 20
            subscores["galactic_grid"] = True
            feedback_parts.append("Galactic grid enabled (shows Milky Way track)")
        else:
            subscores["galactic_grid"] = False
            feedback_parts.append(f"Galactic grid disabled (crucial for Milky Way orientation; flag_galactic_grid={flag_gal})")

        # ── Criterion 5: 1+ screenshots taken (20 pts) ───────────────────────
        new_ss = result.get('new_screenshot_count', 0)
        if new_ss >= 1:
            score += 20
            subscores["screenshots"] = True
            feedback_parts.append(f"{new_ss} reference screenshot(s) captured")
        else:
            subscores["screenshots"] = False
            feedback_parts.append("No screenshots captured")

        # ── Criterion 6: Field Plan notes file written (20 pts) ────────────
        notes_exists = result.get('notes_exists', False)
        notes_crux = result.get('notes_has_crux', False)
        notes_sa = result.get('notes_has_sa', False)
        notes_nov = result.get('notes_has_nov', False)
        notes_gal = result.get('notes_has_galactic', False)

        notes_score = 0
        if notes_exists:
            notes_score += 4
            if notes_crux: notes_score += 4
            if notes_sa: notes_score += 4
            if notes_nov: notes_score += 4
            if notes_gal: notes_score += 4

            score += notes_score
            subscores["field_plan"] = True if notes_score >= 12 else False
            feedback_parts.append(f"Field plan written (Score: {notes_score}/20 keywords matched)")
        else:
            subscores["field_plan"] = False
            feedback_parts.append("Field plan (beetle_field_plan.txt) not found")

        # Pass condition: 70+ points, MUST have Galactic Grid and Field Plan
        key_criteria_met = subscores.get("galactic_grid", False) and notes_exists
        passed = (score >= 70) and key_criteria_met

        if not key_criteria_met and score >= 70:
            feedback_parts.append("FAILED: Key criteria (Galactic Grid or Field Plan) missing despite high score")

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }

    except Exception as e:
        logger.error(f"Verification error: {str(e)}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Error during verification: {str(e)}"
        }