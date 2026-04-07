#!/usr/bin/env python3
"""
Verifier for polynesian_wayfinding_training task.

Scoring (100 points):
- Location set to Hilo, Hawaii (lat within 0.10 rad of 0.344 rad, lon -2.706 rad): 20 pts
- Sky culture set to 'hawaiian_starlines': 20 pts
- Display Settings: Azimuthal grid ON, Landscape OFF, Constellations ON: 20 pts
- 2+ screenshots taken (Arcturus and Acrux documentation): 20 pts
- Wayfinding guide written with keywords (Hilo, Arcturus, Acrux, Hawaiian): 20 pts

Pass threshold: 70 points
"""

import json
import tempfile
import os
import math
import logging

logger = logging.getLogger(__name__)

# Hilo, Hawaii ground truth
HILO_LAT_RAD = 0.34417   # 19.72 degrees N
HILO_LON_RAD = -2.70685  # -155.09 degrees W
LAT_LON_TOLERANCE_RAD = 0.10  # ~5.7 degrees tolerance

def verify_polynesian_wayfinding_training(traj, env_info, task_info):
    """
    Verify Polynesian wayfinding ethno-navigation training task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env function unavailable"}

    task_name = "polynesian_wayfinding_training"

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

        # ── Criterion 1: Location near Hilo, Hawaii (20 pts) ──────────────
        lat_rad = result.get('lat_rad')
        lon_rad = result.get('lon_rad')

        if lat_rad is not None and lon_rad is not None:
            lat_diff = abs(lat_rad - HILO_LAT_RAD)
            # Longitude can sometimes be expressed as positive equivalent
            lon_rad_norm = lon_rad if lon_rad <= math.pi else lon_rad - 2*math.pi
            lon_diff = abs(lon_rad_norm - HILO_LON_RAD)

            if lat_diff <= LAT_LON_TOLERANCE_RAD and lon_diff <= LAT_LON_TOLERANCE_RAD:
                score += 20
                subscores["location"] = True
                feedback_parts.append(f"Hilo location set (lat={math.degrees(lat_rad):.2f}°, lon={math.degrees(lon_rad):.2f}°)")
            else:
                subscores["location"] = False
                feedback_parts.append(
                    f"Wrong location: lat={math.degrees(lat_rad):.2f}°, lon={math.degrees(lon_rad):.2f}° "
                    f"(expected ~19.72°N, ~-155.09°W for Hilo, HI)"
                )
        else:
            subscores["location"] = False
            feedback_parts.append("Location not found in config")

        # ── Criterion 2: Sky culture set to Hawaiian Starlines (20 pts) ─────
        sky_culture = result.get('sky_culture', '')
        if sky_culture and 'hawaiian' in sky_culture.lower():
            score += 20
            subscores["sky_culture"] = True
            feedback_parts.append(f"Sky culture correctly set to {sky_culture}")
        else:
            subscores["sky_culture"] = False
            feedback_parts.append(f"Sky culture incorrect (found: '{sky_culture}', expected 'hawaiian_starlines')")

        # ── Criterion 3: Display Settings (20 pts total) ────────────────────
        display_score = 0
        if result.get('flag_azimuthal_grid'):
            display_score += 7
            feedback_parts.append("Azimuthal grid enabled")
        else:
            feedback_parts.append("Azimuthal grid not enabled")

        if result.get('flag_landscape') is False:
            display_score += 7
            feedback_parts.append("Landscape disabled (sea view)")
        else:
            feedback_parts.append("Landscape not disabled")

        if result.get('flag_constellation_drawing'):
            display_score += 6
            feedback_parts.append("Constellation lines enabled")
        else:
            feedback_parts.append("Constellation lines not enabled")

        score += display_score
        subscores["display_settings"] = (display_score == 20)

        # ── Criterion 4: 2+ screenshots taken (20 pts) ───────────────────────
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
            feedback_parts.append("No new screenshots captured")

        # ── Criterion 5: Wayfinding Guide Document (20 pts) ──────────────────
        guide_score = 0
        if result.get('guide_exists'):
            guide_score += 5
            
            keywords = []
            if result.get('guide_has_hilo'):
                guide_score += 3
                keywords.append('hilo')
            if result.get('guide_has_arcturus'):
                guide_score += 4
                keywords.append('arcturus')
            if result.get('guide_has_acrux'):
                guide_score += 4
                keywords.append('acrux')
            if result.get('guide_has_hawaiian'):
                guide_score += 4
                keywords.append('hawaiian')
                
            feedback_parts.append(f"Guide file present with keywords: {', '.join(keywords) if keywords else 'none'}")
        else:
            feedback_parts.append("Wayfinding guide file not found")
            
        score += guide_score
        subscores["guide"] = (guide_score == 20)

        passed = score >= 70
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": subscores
        }

    except Exception as e:
        logger.error(f"Verification failed: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Error during verification: {e}"
        }