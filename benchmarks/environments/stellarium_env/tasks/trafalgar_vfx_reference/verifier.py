#!/usr/bin/env python3
"""
Verifier for trafalgar_vfx_reference task.

Scoring (100 points):
- Location set to Cape Trafalgar region (lat within 0.10 rad of 0.6314 rad): 20 pts
- Constellation artwork enabled: 15 pts
- Azimuthal coordinate grid enabled: 15 pts
- Atmosphere enabled (realistic sky): 10 pts
- 3+ screenshots taken: 20 pts
- VFX notes file written with Moon/Jupiter content: 20 pts

Pass threshold: 70 points
"""

import json
import tempfile
import os
import math
import logging

logger = logging.getLogger(__name__)

# Cape Trafalgar ground truth
TRAFALGAR_LAT_RAD = 0.63143   # 36.18 degrees N
TRAFALGAR_LON_RAD = -0.10524  # -6.03 degrees W
LAT_LON_TOLERANCE_RAD = 0.10  # ~5.7 degrees tolerance


def verify_trafalgar_vfx_reference(traj, env_info, task_info):
    """
    Verify VFX sky reference task for Battle of Trafalgar.

    Checks:
    1. Location set near Cape Trafalgar
    2. Constellation artwork enabled
    3. Azimuthal grid enabled
    4. Atmosphere enabled
    5. 3+ screenshots taken
    6. VFX notes written with Moon/Jupiter content
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env function unavailable"}

    task_name = "trafalgar_vfx_reference"

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

        # ── Criterion 1: Location near Cape Trafalgar (20 pts) ──────────────
        lat_rad = result.get('lat_rad')
        lon_rad = result.get('lon_rad')

        if lat_rad is not None and lon_rad is not None:
            lat_diff = abs(lat_rad - TRAFALGAR_LAT_RAD)
            lon_diff = abs(lon_rad - TRAFALGAR_LON_RAD)

            if lat_diff <= LAT_LON_TOLERANCE_RAD and lon_diff <= LAT_LON_TOLERANCE_RAD:
                score += 20
                subscores["location"] = True
                feedback_parts.append(
                    f"Cape Trafalgar location set (lat={math.degrees(lat_rad):.2f}°, "
                    f"lon={math.degrees(lon_rad):.2f}°)"
                )
            else:
                subscores["location"] = False
                feedback_parts.append(
                    f"Wrong location: lat={math.degrees(lat_rad):.2f}°, "
                    f"lon={math.degrees(lon_rad):.2f}° "
                    f"(expected ~36.18°N, ~-6.03°W for Cape Trafalgar)"
                )
        else:
            subscores["location"] = False
            feedback_parts.append("Location not found in config")

        # ── Criterion 2: Constellation artwork enabled (15 pts) ─────────────
        flag_art = result.get('flag_constellation_art')
        if flag_art is True:
            score += 15
            subscores["constellation_art"] = True
            feedback_parts.append("Constellation artwork enabled for VFX reference")
        else:
            subscores["constellation_art"] = False
            feedback_parts.append(f"Constellation artwork not enabled (flag_constellation_art={flag_art})")

        # ── Criterion 3: Azimuthal grid enabled (15 pts) ─────────────────────
        flag_az = result.get('flag_azimuthal_grid')
        if flag_az is True:
            score += 15
            subscores["azimuthal_grid"] = True
            feedback_parts.append("Azimuthal coordinate grid enabled")
        else:
            subscores["azimuthal_grid"] = False
            feedback_parts.append(f"Azimuthal grid not enabled (flag_azimuthal_grid={flag_az})")

        # ── Criterion 4: Atmosphere enabled (10 pts) ─────────────────────────
        flag_atm = result.get('flag_atmosphere')
        if flag_atm is True:
            score += 10
            subscores["atmosphere_on"] = True
            feedback_parts.append("Atmosphere enabled (realistic sky rendering)")
        else:
            subscores["atmosphere_on"] = False
            feedback_parts.append(f"Atmosphere disabled (should be ON for sea-view reference; flag_atmosphere={flag_atm})")

        # ── Criterion 5: 3+ screenshots taken (20 pts) ───────────────────────
        new_ss = result.get('new_screenshot_count', 0)
        if new_ss >= 3:
            score += 20
            subscores["screenshots"] = True
            feedback_parts.append(f"{new_ss} reference screenshots captured")
        elif new_ss >= 2:
            score += 10
            subscores["screenshots"] = False
            feedback_parts.append(f"Only {new_ss} screenshots (partial; required: 3)")
        elif new_ss >= 1:
            score += 5
            subscores["screenshots"] = False
            feedback_parts.append(f"Only {new_ss} screenshot (partial; required: 3)")
        else:
            subscores["screenshots"] = False
            feedback_parts.append("No reference screenshots taken")

        # ── Criterion 6: VFX notes file with Moon/Jupiter content (20 pts) ───
        notes_exists = result.get('vfx_notes_exists', False)
        has_moon = result.get('vfx_notes_has_moon', False)
        has_jupiter = result.get('vfx_notes_has_jupiter', False)

        if notes_exists and (has_moon or has_jupiter):
            pts = 20
            if has_moon and has_jupiter:
                pts = 20
            else:
                pts = 12
            score += pts
            subscores["vfx_notes"] = True
            feedback_parts.append(
                f"VFX notes written (Moon={'yes' if has_moon else 'no'}, "
                f"Jupiter={'yes' if has_jupiter else 'no'})"
            )
        elif notes_exists:
            score += 5
            subscores["vfx_notes"] = False
            feedback_parts.append("VFX notes file exists but missing Moon/Jupiter content")
        else:
            subscores["vfx_notes"] = False
            feedback_parts.append("VFX notes file not created at /home/ga/Desktop/trafalgar_sky_notes.txt")

        passed = score >= 70

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts) if feedback_parts else "No criteria met",
            "subscores": subscores,
            "debug": {
                "lat_rad": lat_rad,
                "lon_rad": lon_rad,
                "constellation_art": flag_art,
                "azimuthal_grid": flag_az,
                "atmosphere": flag_atm,
                "new_screenshots": new_ss,
                "notes_exists": notes_exists
            }
        }

    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Result file /tmp/{task_name}_result.json not found — export script may have failed"
        }
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0, "feedback": f"Invalid JSON in result: {e}"}
    except Exception as e:
        logger.exception("Verifier error")
        return {"passed": False, "score": 0, "feedback": f"Verifier error: {str(e)}"}
