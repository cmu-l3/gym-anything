#!/usr/bin/env python3
"""
Verifier for archaeoastronomy_stonehenge task.

Scoring (100 points):
- Stonehenge location set (lat within 0.08 rad of 0.8932 rad): 25 pts
- Azimuthal grid enabled: 10 pts
- Equatorial grid enabled: 10 pts
- Ancient date navigated to (preset_sky_time < 1,000,000 JD): 20 pts
- 2+ screenshots taken: 15 pts
- Research notes with Stonehenge/BCE/solstice keywords: 20 pts

Pass threshold: 70 points
"""

import json
import tempfile
import os
import math
import logging

logger = logging.getLogger(__name__)

# Stonehenge ground truth (Ordnance Survey / English Heritage)
STONEHENGE_LAT_RAD = 0.89316   # 51.1789 degrees N
STONEHENGE_LON_RAD = -0.03188  # -1.8262 degrees W
LAT_TOLERANCE_RAD = 0.08       # ~4.6 degrees tolerance
LON_TOLERANCE_RAD = 0.10       # ~5.7 degrees tolerance

# Ancient date threshold: any date before 1000 CE is "ancient"
# JD for ~1000 CE ≈ 2086302; for 2500 BCE ≈ 808589
# We accept any JD < 1,400,000 as "genuinely ancient navigation"
ANCIENT_JD_THRESHOLD = 1400000
BCE_2500_JD = 808589
BCE_JD_TOLERANCE = 90  # ±90 days


def verify_archaeoastronomy_stonehenge(traj, env_info, task_info):
    """
    Verify archaeoastronomy Stonehenge solstice task.

    Checks:
    1. Location set to Stonehenge coordinates
    2. Azimuthal grid enabled
    3. Equatorial grid enabled
    4. Ancient date navigated (JD < 1,400,000)
    5. 2+ screenshots taken
    6. Research notes with Stonehenge/BCE keywords
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env function unavailable"}

    metadata = task_info.get('metadata', {})
    task_name = "archaeoastronomy_stonehenge"

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

        # ── Criterion 1: Stonehenge location (25 pts) ───────────────────────
        lat_rad = result.get('lat_rad')
        lon_rad = result.get('lon_rad')
        alt_m = result.get('alt_m')

        if lat_rad is not None and lon_rad is not None:
            lat_diff = abs(lat_rad - STONEHENGE_LAT_RAD)
            lon_diff = abs(lon_rad - STONEHENGE_LON_RAD)

            if lat_diff <= LAT_TOLERANCE_RAD and lon_diff <= LON_TOLERANCE_RAD:
                score += 25
                subscores["location"] = True
                feedback_parts.append(
                    f"Stonehenge location set (lat={math.degrees(lat_rad):.3f}°, "
                    f"lon={math.degrees(lon_rad):.3f}°)"
                )
            else:
                subscores["location"] = False
                feedback_parts.append(
                    f"Wrong location: lat={math.degrees(lat_rad):.2f}°, "
                    f"lon={math.degrees(lon_rad):.2f}° "
                    f"(expected ~51.18°N, ~-1.83°W for Stonehenge)"
                )
        else:
            subscores["location"] = False
            feedback_parts.append("Location not found in config")

        # ── Criterion 2: Azimuthal grid enabled (10 pts) ─────────────────────
        flag_az = result.get('flag_azimuthal_grid')
        if flag_az is True:
            score += 10
            subscores["azimuthal_grid"] = True
            feedback_parts.append("Azimuthal grid enabled (bearing measurements)")
        else:
            subscores["azimuthal_grid"] = False
            feedback_parts.append(f"Azimuthal grid not enabled (flag_azimuthal_grid={flag_az})")

        # ── Criterion 3: Equatorial grid enabled (10 pts) ────────────────────
        flag_eq = result.get('flag_equatorial_grid')
        if flag_eq is True:
            score += 10
            subscores["equatorial_grid"] = True
            feedback_parts.append("Equatorial grid enabled (celestial coordinates for paper)")
        else:
            subscores["equatorial_grid"] = False
            feedback_parts.append(f"Equatorial grid not enabled (flag_equatorial_grid={flag_eq})")

        # ── Criterion 4: Ancient date navigated (20 pts) ─────────────────────
        jd = result.get('preset_sky_time')
        if jd is not None:
            if jd < ANCIENT_JD_THRESHOLD:
                # Ancient date confirmed
                jd_diff = abs(jd - BCE_2500_JD)
                if jd_diff <= BCE_JD_TOLERANCE:
                    score += 20
                    subscores["ancient_date"] = True
                    feedback_parts.append(
                        f"Correct date: June 2500 BCE reached (JD={jd:.1f}, "
                        f"diff from target={jd_diff:.1f} days)"
                    )
                else:
                    # Some ancient date but not 2500 BCE
                    score += 10
                    subscores["ancient_date"] = False
                    feedback_parts.append(
                        f"Ancient date reached (JD={jd:.1f}) but not Jun 2500 BCE "
                        f"(target JD≈{BCE_2500_JD})"
                    )
            else:
                subscores["ancient_date"] = False
                feedback_parts.append(
                    f"Not an ancient date (JD={jd:.1f} ≈ modern era; "
                    f"need JD < {ANCIENT_JD_THRESHOLD} for 2500 BCE)"
                )
        else:
            subscores["ancient_date"] = False
            feedback_parts.append(
                "Date not saved to config (Stellarium may not have exited cleanly). "
                "Check that agent navigated to 2500 BCE."
            )

        # ── Criterion 5: 2+ screenshots taken (15 pts) ───────────────────────
        new_ss = result.get('new_screenshot_count', 0)
        if new_ss >= 2:
            score += 15
            subscores["screenshots"] = True
            feedback_parts.append(f"{new_ss} research screenshots documented")
        elif new_ss >= 1:
            score += 7
            subscores["screenshots"] = False
            feedback_parts.append(f"Only {new_ss} screenshot (partial; required: 2)")
        else:
            subscores["screenshots"] = False
            feedback_parts.append("No screenshots taken — sunrise not documented")

        # ── Criterion 6: Research notes (20 pts) ─────────────────────────────
        notes_exists = result.get('research_notes_exists', False)
        has_stonehenge = result.get('research_notes_has_stonehenge', False)
        has_bce = result.get('research_notes_has_bce', False)
        has_solstice = result.get('research_notes_has_solstice', False)

        keyword_count = sum([has_stonehenge, has_bce, has_solstice])

        if notes_exists and keyword_count >= 2:
            score += 20
            subscores["research_notes"] = True
            feedback_parts.append(
                f"Research notes written with {keyword_count}/3 required keywords "
                f"(Stonehenge={'yes' if has_stonehenge else 'no'}, "
                f"BCE/date={'yes' if has_bce else 'no'}, "
                f"solstice/sun={'yes' if has_solstice else 'no'})"
            )
        elif notes_exists and keyword_count >= 1:
            score += 10
            subscores["research_notes"] = False
            feedback_parts.append(
                f"Research notes written but only {keyword_count}/3 keywords found"
            )
        elif notes_exists:
            score += 5
            subscores["research_notes"] = False
            feedback_parts.append("Research notes file exists but lacks expected content")
        else:
            subscores["research_notes"] = False
            feedback_parts.append("Research notes not written to /home/ga/Desktop/stonehenge_alignment.txt")

        passed = score >= 70

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts) if feedback_parts else "No criteria met",
            "subscores": subscores,
            "debug": {
                "lat_rad": lat_rad,
                "jd": jd,
                "azimuthal_grid": flag_az,
                "equatorial_grid": flag_eq,
                "new_screenshots": new_ss,
                "notes_exists": notes_exists
            }
        }

    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Result file not found — export script may have failed"
        }
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0, "feedback": f"Invalid JSON in result: {e}"}
    except Exception as e:
        logger.exception("Verifier error")
        return {"passed": False, "score": 0, "feedback": f"Verifier error: {str(e)}"}
