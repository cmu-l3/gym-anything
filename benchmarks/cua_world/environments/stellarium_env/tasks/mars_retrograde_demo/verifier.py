#!/usr/bin/env python3
"""
Verifier for mars_retrograde_demo task.

Scoring (100 points):
- Location set to Greenwich (lat within 0.05 rad of 0.8984 rad): 20 pts
- Atmosphere disabled: 10 pts
- Ground/landscape disabled: 10 pts
- Ecliptic line enabled: 15 pts
- Constellation lines enabled: 10 pts
- 3+ new screenshots taken: 20 pts
- Teaching notes file with required content: 15 pts

Pass threshold: 65 points
"""

import json
import tempfile
import os
import math
import logging

logger = logging.getLogger(__name__)

# Greenwich Observatory ground truth
GREENWICH_LAT_RAD = 0.8984   # ~51.4769 degrees
GREENWICH_LON_RAD = 0.0000   # ~0.0005 degrees
LAT_LON_TOLERANCE_RAD = 0.05 # ~2.9 degrees (generous, rejects default 40 deg lat)

def verify_mars_retrograde_demo(traj, env_info, task_info):
    """
    Verify Mars retrograde demo task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env function unavailable"}

    task_name = "mars_retrograde_demo"

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
            lat_diff = abs(lat_rad - GREENWICH_LAT_RAD)
            lon_diff = abs(lon_rad - GREENWICH_LON_RAD)

            if lat_diff <= LAT_LON_TOLERANCE_RAD and lon_diff <= LAT_LON_TOLERANCE_RAD:
                score += 20
                subscores["location"] = True
                feedback_parts.append(
                    f"Greenwich location set (lat={math.degrees(lat_rad):.2f}°, "
                    f"lon={math.degrees(lon_rad):.2f}°)"
                )
            else:
                subscores["location"] = False
                feedback_parts.append(
                    f"Wrong location: lat={math.degrees(lat_rad):.2f}°, "
                    f"lon={math.degrees(lon_rad):.2f}° "
                    f"(expected ~51.48°N, ~0.00°W for Greenwich)"
                )
        else:
            subscores["location"] = False
            feedback_parts.append("Location not found in config")

        # ── Criterion 2: Atmosphere disabled (10 pts) ────────────────────────
        flag_atmosphere = result.get('flag_atmosphere')
        if flag_atmosphere is False:
            score += 10
            subscores["atmosphere_off"] = True
            feedback_parts.append("Atmosphere disabled")
        else:
            subscores["atmosphere_off"] = False
            feedback_parts.append(f"Atmosphere still enabled (flag_atmosphere={flag_atmosphere})")

        # ── Criterion 3: Ground disabled (10 pts) ────────────────────────
        flag_landscape = result.get('flag_landscape')
        if flag_landscape is False:
            score += 10
            subscores["landscape_off"] = True
            feedback_parts.append("Landscape/ground disabled")
        else:
            subscores["landscape_off"] = False
            feedback_parts.append(f"Landscape still enabled (flag_landscape={flag_landscape})")

        # ── Criterion 4: Ecliptic line enabled (15 pts) ────────────────────
        flag_ecliptic = result.get('flag_ecliptic_line')
        if flag_ecliptic is True:
            score += 15
            subscores["ecliptic_line"] = True
            feedback_parts.append("Ecliptic line enabled")
        else:
            subscores["ecliptic_line"] = False
            feedback_parts.append(f"Ecliptic line not enabled (flag_ecliptic_line={flag_ecliptic})")

        # ── Criterion 5: Constellation lines enabled (10 pts) ────────────────────
        flag_const = result.get('flag_constellation_drawing')
        if flag_const is True:
            score += 10
            subscores["constellation_lines"] = True
            feedback_parts.append("Constellation lines enabled")
        else:
            subscores["constellation_lines"] = False
            feedback_parts.append(f"Constellation lines not enabled (flag_constellation_drawing={flag_const})")

        # ── Criterion 6: 3+ screenshots taken (20 pts) ───────────────────────
        new_ss = result.get('new_screenshot_count', 0)
        if new_ss >= 3:
            score += 20
            subscores["screenshots"] = True
            feedback_parts.append(f"{new_ss} target screenshots taken (required: 3)")
        elif new_ss == 2:
            score += 10
            subscores["screenshots"] = False
            feedback_parts.append("Only 2 screenshots taken (partial credit; required: 3)")
        elif new_ss == 1:
            score += 5
            subscores["screenshots"] = False
            feedback_parts.append("Only 1 screenshot taken (partial credit; required: 3)")
        else:
            subscores["screenshots"] = False
            feedback_parts.append("No screenshots taken")

        # ── Criterion 7: Teaching notes file content (15 pts) ────────
        notes_exists = result.get('notes_exists', False)
        notes_content = result.get('notes_content', '').lower()
        
        if notes_exists and len(notes_content) > 10:
            has_retrograde = "retrograde" in notes_content
            has_opposition = "opposition" in notes_content
            
            # Check for dates
            months_found = sum([
                "october" in notes_content or "oct" in notes_content,
                "december" in notes_content or "dec" in notes_content,
                "january" in notes_content or "jan" in notes_content
            ])
            has_year = "2022" in notes_content or "2023" in notes_content

            content_criteria = [has_retrograde, has_opposition, (months_found >= 2), has_year]
            met_count = sum(content_criteria)
            
            if met_count == 4:
                score += 15
                subscores["notes"] = True
                feedback_parts.append("Notes file complete with all required concepts and dates")
            elif met_count >= 2:
                score += 8
                subscores["notes"] = False
                feedback_parts.append(f"Notes file partially correct ({met_count}/4 criteria met)")
            else:
                score += 3
                subscores["notes"] = False
                feedback_parts.append("Notes file exists but missing most required keywords")
        else:
            subscores["notes"] = False
            feedback_parts.append("Teaching notes file missing or empty")

        # Final Evaluation
        passed = score >= 65
        
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
            "feedback": f"Verification encountered an error: {e}"
        }