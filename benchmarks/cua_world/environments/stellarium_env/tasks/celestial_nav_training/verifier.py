#!/usr/bin/env python3
"""
Verifier for celestial_nav_training task.

Scoring (100 points):
- Pacific vessel location (lat within 0.10 rad of 0.2618 rad): 20 pts
- Azimuthal grid enabled: 20 pts
- Constellation drawing disabled: 15 pts
- 4+ screenshots taken (one per star): 25 pts
- Navigation log written with star names: 20 pts

Pass threshold: 70 points
"""

import json
import tempfile
import os
import math
import logging

logger = logging.getLogger(__name__)

# Western Pacific ship position (near Mariana Islands)
TARGET_LAT_RAD = 0.26180   # 15.0 degrees N
TARGET_LON_RAD = -2.53073  # -145.0 degrees W
LAT_TOLERANCE_RAD = 0.10   # ~5.7 degrees
LON_TOLERANCE_RAD = 0.15   # ~8.6 degrees (wider for longitude)


def verify_celestial_nav_training(traj, env_info, task_info):
    """
    Verify maritime celestial navigation training setup task.

    Checks:
    1. Location set to Pacific position (near Mariana Islands)
    2. Azimuthal grid enabled
    3. Constellation drawing disabled
    4. 4+ screenshots taken
    5. Navigation log with star names
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env function unavailable"}

    task_name = "celestial_nav_training"

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

        # ── Criterion 1: Pacific vessel location (20 pts) ───────────────────
        lat_rad = result.get('lat_rad')
        lon_rad = result.get('lon_rad')

        if lat_rad is not None and lon_rad is not None:
            lat_diff = abs(lat_rad - TARGET_LAT_RAD)
            lon_diff = abs(lon_rad - TARGET_LON_RAD)

            if lat_diff <= LAT_TOLERANCE_RAD and lon_diff <= LON_TOLERANCE_RAD:
                score += 20
                subscores["location"] = True
                feedback_parts.append(
                    f"Pacific position set (lat={math.degrees(lat_rad):.1f}°N, "
                    f"lon={math.degrees(lon_rad):.1f}°W)"
                )
            else:
                subscores["location"] = False
                feedback_parts.append(
                    f"Wrong location: lat={math.degrees(lat_rad):.1f}°, "
                    f"lon={math.degrees(lon_rad):.1f}° "
                    f"(expected ~15°N, ~145°W near Mariana Islands)"
                )
        else:
            subscores["location"] = False
            feedback_parts.append("Location not found in config")

        # ── Criterion 2: Azimuthal grid enabled (20 pts) ─────────────────────
        flag_az = result.get('flag_azimuthal_grid')
        if flag_az is True:
            score += 20
            subscores["azimuthal_grid"] = True
            feedback_parts.append("Azimuthal grid enabled (altitude/bearing measurements ready)")
        else:
            subscores["azimuthal_grid"] = False
            feedback_parts.append(f"Azimuthal grid not enabled (flag_azimuthal_grid={flag_az})")

        # ── Criterion 3: Constellation drawing disabled (15 pts) ─────────────
        flag_const = result.get('flag_constellation_drawing')
        if flag_const is False:
            score += 15
            subscores["constellation_off"] = True
            feedback_parts.append("Constellation lines disabled (clean navigator view)")
        else:
            subscores["constellation_off"] = False
            feedback_parts.append(
                f"Constellation lines still enabled (flag_constellation_drawing={flag_const}); "
                "must disable for navigator training"
            )

        # ── Criterion 4: 4+ screenshots taken (25 pts) ───────────────────────
        new_ss = result.get('new_screenshot_count', 0)
        if new_ss >= 4:
            score += 25
            subscores["screenshots"] = True
            feedback_parts.append(f"{new_ss} star identification screenshots taken")
        elif new_ss >= 3:
            score += 18
            subscores["screenshots"] = False
            feedback_parts.append(f"Only {new_ss}/4 star screenshots taken (partial credit)")
        elif new_ss >= 2:
            score += 10
            subscores["screenshots"] = False
            feedback_parts.append(f"Only {new_ss}/4 star screenshots taken (partial credit)")
        elif new_ss >= 1:
            score += 5
            subscores["screenshots"] = False
            feedback_parts.append(f"Only {new_ss}/4 star screenshots taken")
        else:
            subscores["screenshots"] = False
            feedback_parts.append("No star screenshots taken")

        # ── Criterion 5: Navigation log with star names (20 pts) ─────────────
        log_exists = result.get('nav_log_exists', False)
        has_polaris = result.get('nav_log_has_polaris', False)
        has_sirius = result.get('nav_log_has_sirius', False)
        has_canopus = result.get('nav_log_has_canopus', False)
        has_vega = result.get('nav_log_has_vega', False)

        stars_documented = sum([has_polaris, has_sirius, has_canopus, has_vega])

        if log_exists and stars_documented >= 4:
            score += 20
            subscores["nav_log"] = True
            feedback_parts.append("Navigation log complete with all 4 stars documented")
        elif log_exists and stars_documented >= 3:
            score += 15
            subscores["nav_log"] = False
            feedback_parts.append(
                f"Navigation log has {stars_documented}/4 stars "
                f"(Polaris={'yes' if has_polaris else 'no'}, "
                f"Sirius={'yes' if has_sirius else 'no'}, "
                f"Canopus={'yes' if has_canopus else 'no'}, "
                f"Vega={'yes' if has_vega else 'no'})"
            )
        elif log_exists and stars_documented >= 2:
            score += 8
            subscores["nav_log"] = False
            feedback_parts.append(f"Navigation log has only {stars_documented}/4 stars")
        elif log_exists:
            score += 3
            subscores["nav_log"] = False
            feedback_parts.append("Navigation log exists but no star names found")
        else:
            subscores["nav_log"] = False
            feedback_parts.append("Navigation log not created at /home/ga/Desktop/nav_log.txt")

        passed = score >= 70

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts) if feedback_parts else "No criteria met",
            "subscores": subscores,
            "debug": {
                "lat_rad": lat_rad,
                "lon_rad": lon_rad,
                "azimuthal_grid": flag_az,
                "constellation_drawing": flag_const,
                "new_screenshots": new_ss,
                "stars_documented": stars_documented
            }
        }

    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found — export script may have failed"
        }
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0, "feedback": f"Invalid JSON: {e}"}
    except Exception as e:
        logger.exception("Verifier error")
        return {"passed": False, "score": 0, "feedback": f"Verifier error: {str(e)}"}
