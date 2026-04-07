#!/usr/bin/env python3
"""
Verifier for sundial_analemma_reference task.

Scoring (100 points):
- Location set to Jaipur (lat within 0.05 rad of 0.4699 rad): 20 pts
- Azimuthal grid enabled (flag_azimuthal_grid = true): 10 pts
- Cardinal points enabled (flag_cardinal_points = true): 10 pts
- Landscape OFF & Atmosphere ON (clean horizon, daytime sky): 10 pts
- 4+ screenshots taken: 30 pts (partial credit: 3=20, 2=10, 1=5)
- Reference notes written with domain & date keywords: 20 pts

Pass threshold: 70 points
"""

import json
import tempfile
import os
import math
import logging

logger = logging.getLogger(__name__)

# Jantar Mantar, Jaipur ground truth
JAIPUR_LAT_RAD = 0.4699   # ~26.9246 degrees
JAIPUR_LON_RAD = 1.3233   # ~75.8235 degrees
LAT_LON_TOLERANCE_RAD = 0.05  # ~2.8 degrees tolerance


def verify_sundial_analemma_reference(traj, env_info, task_info):
    """
    Verify the sundial reference task.
    Uses copy_from_env to safely retrieve the JSON exported by post-task hook.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env function unavailable"}

    task_name = "sundial_analemma_reference"

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

        # ── Criterion 1: Observatory location (20 pts) ──────────────────────
        lat_rad = result.get('lat_rad')
        lon_rad = result.get('lon_rad')

        if lat_rad is not None and lon_rad is not None:
            lat_diff = abs(lat_rad - JAIPUR_LAT_RAD)
            lon_diff = abs(lon_rad - JAIPUR_LON_RAD)

            if lat_diff <= LAT_LON_TOLERANCE_RAD and lon_diff <= LAT_LON_TOLERANCE_RAD:
                score += 20
                subscores["location"] = True
                feedback_parts.append(
                    f"Jaipur location set (lat={math.degrees(lat_rad):.2f}°, "
                    f"lon={math.degrees(lon_rad):.2f}°)"
                )
            else:
                subscores["location"] = False
                feedback_parts.append(
                    f"Wrong location: lat={math.degrees(lat_rad):.2f}°, "
                    f"lon={math.degrees(lon_rad):.2f}° "
                    f"(expected ~26.92°N, ~75.82°E for Jaipur)"
                )
        else:
            subscores["location"] = False
            feedback_parts.append("Location not found in config")

        # ── Criterion 2: Azimuthal grid enabled (10 pts) ────────────────────
        flag_az_grid = result.get('flag_azimuthal_grid')
        if flag_az_grid is True:
            score += 10
            subscores["azimuthal_grid"] = True
            feedback_parts.append("Azimuthal coordinate grid enabled")
        else:
            subscores["azimuthal_grid"] = False
            feedback_parts.append(f"Azimuthal grid not enabled (flag_azimuthal_grid={flag_az_grid})")

        # ── Criterion 3: Cardinal points enabled (10 pts) ────────────────────
        flag_cardinal = result.get('flag_cardinal_points')
        if flag_cardinal is True:
            score += 10
            subscores["cardinal_points"] = True
            feedback_parts.append("Cardinal direction labels enabled")
        else:
            subscores["cardinal_points"] = False
            feedback_parts.append(f"Cardinal points not enabled (flag_cardinal_points={flag_cardinal})")

        # ── Criterion 4: Landscape OFF, Atmosphere ON (10 pts) ───────────────
        flag_landscape = result.get('flag_landscape')
        flag_atmosphere = result.get('flag_atmosphere')
        
        if flag_landscape is False and flag_atmosphere is True:
            score += 10
            subscores["display_clean_horizon"] = True
            feedback_parts.append("Landscape disabled and atmosphere enabled for solar view")
        else:
            subscores["display_clean_horizon"] = False
            feedback_parts.append(
                f"Incorrect horizon settings (landscape={flag_landscape}, atmosphere={flag_atmosphere})"
            )

        # ── Criterion 5: 4+ screenshots taken (30 pts) ───────────────────────
        new_ss = result.get('new_screenshot_count', 0)
        if new_ss >= 4:
            score += 30
            subscores["screenshots"] = True
            feedback_parts.append(f"{new_ss} screenshots taken (required: 4)")
        elif new_ss == 3:
            score += 20
            subscores["screenshots"] = False
            feedback_parts.append(f"Only {new_ss} screenshots taken (partial credit; required: 4)")
        elif new_ss == 2:
            score += 10
            subscores["screenshots"] = False
            feedback_parts.append(f"Only {new_ss} screenshots taken (partial credit; required: 4)")
        elif new_ss == 1:
            score += 5
            subscores["screenshots"] = False
            feedback_parts.append(f"Only {new_ss} screenshot taken (partial credit; required: 4)")
        else:
            subscores["screenshots"] = False
            feedback_parts.append("No screenshots taken to document dates")

        # ── Criterion 6: Reference notes file (20 pts) ───────────────────────
        notes_exists = result.get('notes_exists', False)
        notes_has_domain = result.get('notes_has_domain', False)
        notes_has_date = result.get('notes_has_date', False)

        if notes_exists:
            if notes_has_domain and notes_has_date:
                score += 20
                subscores["notes"] = True
                feedback_parts.append("Reference notes created with valid domain and date content")
            elif notes_has_domain or notes_has_date:
                score += 10
                subscores["notes"] = False
                feedback_parts.append("Reference notes created but missing some required keywords (partial credit)")
            else:
                score += 5
                subscores["notes"] = False
                feedback_parts.append("Reference notes created but lacks expected keywords (Jantar Mantar / dates)")
        else:
            subscores["notes"] = False
            feedback_parts.append("Reference notes file not created")

        # ── Final Determination ─────────────────────────────────────────────
        passed = score >= 70

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": subscores
        }

    except Exception as e:
        logger.error(f"Verification error: {str(e)}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification failed with error: {str(e)}"
        }