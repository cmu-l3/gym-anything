#!/usr/bin/env python3
"""
Verifier for astrophoto_session_planner task.

Scoring (100 points):
- Observatory location (lat within 0.05 rad of Paranal -0.4297 rad): 25 pts
- Atmosphere disabled (flag_atmosphere = false): 15 pts
- Equatorial grid enabled (flag_equatorial_grid = true): 15 pts
- 3+ new screenshots taken: 25 pts
- Session notes file written with NGC content: 20 pts

Pass threshold: 70 points
"""

import json
import tempfile
import os
import math
import logging

logger = logging.getLogger(__name__)

# Paranal Observatory ground truth (IAU code 309)
PARANAL_LAT_RAD = -0.42970   # -24.6272 degrees
PARANAL_LON_RAD = -1.22862   # -70.4042 degrees
PARANAL_ALT_M = 2635
LAT_LON_TOLERANCE_RAD = 0.10  # ~5.7 degrees — generous for observatory identification
ALT_TOLERANCE_M = 500


def verify_astrophoto_session_planner(traj, env_info, task_info):
    """
    Verify astrophoto session planning task.

    Checks:
    1. Location set to Paranal Observatory (lat/lon in radians)
    2. Atmosphere disabled
    3. Equatorial grid enabled
    4. 3+ screenshots taken
    5. Session notes file written with NGC content
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env function unavailable"}

    metadata = task_info.get('metadata', {})
    task_name = "astrophoto_session_planner"

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

        # ── Criterion 1: Observatory location (25 pts) ──────────────────────
        lat_rad = result.get('lat_rad')
        lon_rad = result.get('lon_rad')
        alt_m = result.get('alt_m')

        if lat_rad is not None and lon_rad is not None:
            lat_diff = abs(lat_rad - PARANAL_LAT_RAD)
            lon_diff = abs(lon_rad - PARANAL_LON_RAD)

            if lat_diff <= LAT_LON_TOLERANCE_RAD and lon_diff <= LAT_LON_TOLERANCE_RAD:
                score += 25
                subscores["location"] = True
                feedback_parts.append(
                    f"Paranal location set (lat={math.degrees(lat_rad):.2f}°, "
                    f"lon={math.degrees(lon_rad):.2f}°)"
                )
            else:
                subscores["location"] = False
                feedback_parts.append(
                    f"Wrong location: lat={math.degrees(lat_rad):.2f}°, "
                    f"lon={math.degrees(lon_rad):.2f}° "
                    f"(expected ~-24.63°N, ~-70.40°W for Paranal)"
                )
        else:
            subscores["location"] = False
            feedback_parts.append("Location not found in config")

        # ── Criterion 2: Atmosphere disabled (15 pts) ────────────────────────
        flag_atmosphere = result.get('flag_atmosphere')
        if flag_atmosphere is False:
            score += 15
            subscores["atmosphere_off"] = True
            feedback_parts.append("Atmosphere disabled (dark-sky mode)")
        else:
            subscores["atmosphere_off"] = False
            feedback_parts.append(f"Atmosphere still enabled (flag_atmosphere={flag_atmosphere})")

        # ── Criterion 3: Equatorial grid enabled (15 pts) ────────────────────
        flag_eq_grid = result.get('flag_equatorial_grid')
        if flag_eq_grid is True:
            score += 15
            subscores["equatorial_grid"] = True
            feedback_parts.append("Equatorial coordinate grid enabled")
        else:
            subscores["equatorial_grid"] = False
            feedback_parts.append(f"Equatorial grid not enabled (flag_equatorial_grid={flag_eq_grid})")

        # ── Criterion 4: 3+ screenshots taken (25 pts) ───────────────────────
        new_ss = result.get('new_screenshot_count', 0)
        if new_ss >= 3:
            score += 25
            subscores["screenshots"] = True
            feedback_parts.append(f"{new_ss} target screenshots taken (required: 3)")
        elif new_ss >= 2:
            score += 12
            subscores["screenshots"] = False
            feedback_parts.append(f"Only {new_ss} screenshots (partial credit; required: 3)")
        elif new_ss >= 1:
            score += 5
            subscores["screenshots"] = False
            feedback_parts.append(f"Only {new_ss} screenshot (partial credit; required: 3)")
        else:
            subscores["screenshots"] = False
            feedback_parts.append("No screenshots taken — targets not documented")

        # ── Criterion 5: Session notes file with NGC content (20 pts) ────────
        notes_exists = result.get('session_notes_exists', False)
        notes_has_ngc = result.get('session_notes_has_ngc', False)
        notes_has_date = result.get('session_notes_has_date', False)

        if notes_exists and notes_has_ngc:
            score += 20
            subscores["session_notes"] = True
            feedback_parts.append("Session notes written with NGC target documentation")
        elif notes_exists:
            score += 8
            subscores["session_notes"] = False
            feedback_parts.append("Session notes file exists but missing NGC content")
        else:
            subscores["session_notes"] = False
            feedback_parts.append("Session notes file not created at /home/ga/Desktop/session_notes.txt")

        passed = score >= 70

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts) if feedback_parts else "No criteria met",
            "subscores": subscores,
            "debug": {
                "lat_rad": lat_rad,
                "lon_rad": lon_rad,
                "new_screenshots": new_ss,
                "notes_exists": notes_exists
            }
        }

    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Result file /tmp/{task_name}_result.json not found in VM — export script may have failed"
        }
    except json.JSONDecodeError as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Invalid JSON in result file: {e}"
        }
    except Exception as e:
        logger.exception("Verifier error")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verifier error: {str(e)}"
        }
