#!/usr/bin/env python3
"""
Verifier for setup_commute_favorites task.

Scoring (100 points total):
  - Home address set (type=0 in place table):      25 pts
  - Work address set (type=1 in place table):      25 pts
  - At least one favorite added (favorites table):  25 pts
  - Home/Work coordinates within tolerance:         25 pts
    (12.5 pts for Home coords, 12.5 pts for Work coords)

Pass threshold: 70 points.
Gate: If no place entries AND no favorites exist at all, return score=0 immediately.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Expected coordinates
EXPECTED_HOME_LAT = 38.8977
EXPECTED_HOME_LON = -77.0365
EXPECTED_WORK_LAT = 40.7484
EXPECTED_WORK_LON = -73.9857

# Tolerance in degrees (~0.1 deg is roughly 11 km)
COORD_TOLERANCE = 0.1

PASS_THRESHOLD = 70


def _coords_within_tolerance(actual_lat, actual_lon, expected_lat, expected_lon, tolerance):
    """Check if actual coordinates are within tolerance of expected coordinates."""
    if actual_lat is None or actual_lon is None:
        return False
    try:
        lat_diff = abs(float(actual_lat) - expected_lat)
        lon_diff = abs(float(actual_lon) - expected_lon)
        return lat_diff <= tolerance and lon_diff <= tolerance
    except (ValueError, TypeError):
        return False


def check_setup_commute_favorites(traj, env_info, task_info):
    """
    Multi-criterion verifier for setup_commute_favorites.

    Reads the JSON result file produced by export_result.sh and checks:
    1. Home address exists in place table (type=0)         -> 25 pts
    2. Work address exists in place table (type=1)         -> 25 pts
    3. At least one favorite was added to favorites table  -> 25 pts
    4. Home/Work coordinates are near expected values       -> 25 pts
       (12.5 for Home, 12.5 for Work)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/data/local/tmp/setup_commute_favorites_result.json", temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_file.name)

        # Check for error in result
        if result.get("error"):
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Export error: {result['error']}"
            }

        home = result.get("home")
        work = result.get("work")
        favorites = result.get("favorites", [])
        favorites_count = int(result.get("favorites_count", 0))

        # Gate: if absolutely nothing exists, return 0 immediately
        if home is None and work is None and favorites_count == 0 and len(favorites) == 0:
            return {
                "passed": False,
                "score": 0,
                "feedback": "GATE: No place entries and no favorites found. "
                            "The agent did not interact with the places database at all."
            }

        score = 0
        feedback_parts = []

        # --- Criterion 1: Home address set (25 pts) ---
        if home is not None and home != "null":
            score += 25
            home_title = home.get("title", "")
            home_lat = home.get("latitude")
            home_lon = home.get("longitude")
            feedback_parts.append(
                f"Home set: title='{home_title}', lat={home_lat}, lon={home_lon} [+25]"
            )
        else:
            feedback_parts.append("Home address NOT set in place table (type=0) [+0]")

        # --- Criterion 2: Work address set (25 pts) ---
        if work is not None and work != "null":
            score += 25
            work_title = work.get("title", "")
            work_lat = work.get("latitude")
            work_lon = work.get("longitude")
            feedback_parts.append(
                f"Work set: title='{work_title}', lat={work_lat}, lon={work_lon} [+25]"
            )
        else:
            feedback_parts.append("Work address NOT set in place table (type=1) [+0]")

        # --- Criterion 3: At least one favorite added (25 pts) ---
        if favorites_count > 0 or len(favorites) > 0:
            actual_count = max(favorites_count, len(favorites))
            score += 25
            fav_names = [f.get("title", "?") for f in favorites] if favorites else []
            feedback_parts.append(
                f"Favorites found: count={actual_count}, names={fav_names} [+25]"
            )
        else:
            feedback_parts.append("No favorites found in favorites table [+0]")

        # --- Criterion 4: Coordinate accuracy (25 pts total) ---
        # 4a: Home coordinates (12.5 pts)
        if home is not None and home != "null":
            home_lat = home.get("latitude")
            home_lon = home.get("longitude")
            if _coords_within_tolerance(home_lat, home_lon,
                                         EXPECTED_HOME_LAT, EXPECTED_HOME_LON,
                                         COORD_TOLERANCE):
                score += 12.5
                feedback_parts.append(
                    f"Home coords within {COORD_TOLERANCE} deg of expected "
                    f"({EXPECTED_HOME_LAT}, {EXPECTED_HOME_LON}) [+12.5]"
                )
            else:
                feedback_parts.append(
                    f"Home coords ({home_lat}, {home_lon}) NOT within {COORD_TOLERANCE} deg "
                    f"of expected ({EXPECTED_HOME_LAT}, {EXPECTED_HOME_LON}) [+0]"
                )
        else:
            feedback_parts.append("Home coords: N/A (no Home entry) [+0]")

        # 4b: Work coordinates (12.5 pts)
        if work is not None and work != "null":
            work_lat = work.get("latitude")
            work_lon = work.get("longitude")
            if _coords_within_tolerance(work_lat, work_lon,
                                         EXPECTED_WORK_LAT, EXPECTED_WORK_LON,
                                         COORD_TOLERANCE):
                score += 12.5
                feedback_parts.append(
                    f"Work coords within {COORD_TOLERANCE} deg of expected "
                    f"({EXPECTED_WORK_LAT}, {EXPECTED_WORK_LON}) [+12.5]"
                )
            else:
                feedback_parts.append(
                    f"Work coords ({work_lat}, {work_lon}) NOT within {COORD_TOLERANCE} deg "
                    f"of expected ({EXPECTED_WORK_LAT}, {EXPECTED_WORK_LON}) [+0]"
                )
        else:
            feedback_parts.append("Work coords: N/A (no Work entry) [+0]")

        # Final score (convert to int for clean output)
        score = int(score)
        passed = score >= PASS_THRESHOLD

        feedback = " | ".join(feedback_parts)

        return {
            "passed": passed,
            "score": score,
            "feedback": feedback
        }

    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found"
        }
    except json.JSONDecodeError as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Result file is not valid JSON: {e}"
        }
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verifier error: {str(e)}"
        }
