#!/usr/bin/env python3
"""Verifier for plan_property_tour_route task.

Scoring (100 points total, 8 criteria):
  Criterion 1:  Home address set (place table type=0)                          — 15 pts
  Criterion 2:  Home coordinates within tolerance of 1600 Penn Ave, DC         — 10 pts
  Criterion 3:  Work address set (place table type=1)                          — 15 pts
  Criterion 4:  Work coordinates within tolerance of Empire State Building     — 10 pts
  Criterion 5:  At least one favorite added                                    — 15 pts
  Criterion 6:  Route compute set to Shortest ("0")                            — 12 pts
  Criterion 7:  Arrive-in-direction enabled (true)                             — 12 pts
  Criterion 8:  Color scheme set to Night ("2")                                — 11 pts
                                                                      TOTAL   = 100 pts

Pass threshold: 70 points.

Gate: If no Home, no Work, no Favorites, AND route_compute and color_scheme
      unchanged from baseline => score 0.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

# Real coordinates — 1600 Pennsylvania Ave NW, Washington DC
EXPECTED_HOME_LAT = 38.8977
EXPECTED_HOME_LON = -77.0365

# Real coordinates — Empire State Building, NYC
EXPECTED_WORK_LAT = 40.7484
EXPECTED_WORK_LON = -73.9857

COORD_TOLERANCE = 0.15  # ~16 km — generous for search-based address entry

PASS_THRESHOLD = 70


def _coords_within_tolerance(actual_lat, actual_lon, expected_lat, expected_lon, tol):
    if actual_lat is None or actual_lon is None:
        return False
    try:
        return (abs(float(actual_lat) - expected_lat) <= tol
                and abs(float(actual_lon) - expected_lon) <= tol)
    except (ValueError, TypeError):
        return False


def verify_plan_property_tour_route(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env(
                "/data/local/tmp/plan_property_tour_route_result.json",
                temp_file.name
            )
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_file.name)

        if result.get("error"):
            return {"passed": False, "score": 0,
                    "feedback": f"Export error: {result['error']}"}

        home = result.get("home")
        work = result.get("work")
        favorites = result.get("favorites", [])
        favorites_count = int(result.get("favorites_count", 0))
        route_compute = result.get("route_compute", "").strip()
        color_scheme = result.get("color_scheme", "").strip()
        baseline_rc = result.get("baseline_route_compute", "1").strip()
        baseline_cs = result.get("baseline_color_scheme", "0").strip()

        # ========== GATE: Do-nothing check ==========
        no_places = (home is None and work is None
                     and favorites_count == 0 and len(favorites) == 0)
        no_prefs_change = (route_compute == baseline_rc
                           and color_scheme == baseline_cs)

        if no_places and no_prefs_change:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Gate: No places set, no favorites, no settings changed."
            }

        score = 0
        feedback_parts = []

        # ========== Criterion 1: Home address set (15 pts) ==========
        if home is not None and home != "null":
            score += 15
            feedback_parts.append(
                f"Home set: '{home.get('title', '')}' (+15)"
            )
        else:
            feedback_parts.append("Home not set (+0)")

        # ========== Criterion 2: Home coords near 1600 Penn Ave (10 pts) ==========
        if home is not None and home != "null":
            h_lat = home.get("latitude")
            h_lon = home.get("longitude")
            if _coords_within_tolerance(h_lat, h_lon,
                                        EXPECTED_HOME_LAT, EXPECTED_HOME_LON,
                                        COORD_TOLERANCE):
                score += 10
                feedback_parts.append(f"Home coords accurate ({h_lat}, {h_lon}) (+10)")
            else:
                feedback_parts.append(
                    f"Home coords ({h_lat}, {h_lon}) not near "
                    f"({EXPECTED_HOME_LAT}, {EXPECTED_HOME_LON}) (+0)"
                )
        else:
            feedback_parts.append("Home coords: N/A (+0)")

        # ========== Criterion 3: Work address set (15 pts) ==========
        if work is not None and work != "null":
            score += 15
            feedback_parts.append(
                f"Work set: '{work.get('title', '')}' (+15)"
            )
        else:
            feedback_parts.append("Work not set (+0)")

        # ========== Criterion 4: Work coords near Empire State Building (10 pts) ==========
        if work is not None and work != "null":
            w_lat = work.get("latitude")
            w_lon = work.get("longitude")
            if _coords_within_tolerance(w_lat, w_lon,
                                        EXPECTED_WORK_LAT, EXPECTED_WORK_LON,
                                        COORD_TOLERANCE):
                score += 10
                feedback_parts.append(f"Work coords accurate ({w_lat}, {w_lon}) (+10)")
            else:
                feedback_parts.append(
                    f"Work coords ({w_lat}, {w_lon}) not near "
                    f"({EXPECTED_WORK_LAT}, {EXPECTED_WORK_LON}) (+0)"
                )
        else:
            feedback_parts.append("Work coords: N/A (+0)")

        # ========== Criterion 5: At least one favorite (15 pts) ==========
        actual_fav = max(favorites_count, len(favorites))
        if actual_fav > 0:
            score += 15
            fav_names = [f.get("title", "?") for f in favorites] if favorites else []
            feedback_parts.append(f"Favorites: count={actual_fav}, names={fav_names} (+15)")
        else:
            feedback_parts.append("No favorites found (+0)")

        # ========== Criterion 6: Route compute = Shortest "0" (12 pts) ==========
        if route_compute == '0':
            score += 12
            feedback_parts.append("Route compute set to Shortest (+12)")
        else:
            feedback_parts.append(
                f"Route compute='{route_compute}', expected '0' (Shortest) (+0)"
            )

        # ========== Criterion 7: Arrive-in-direction = true (12 pts) ==========
        arrive_dir = result.get("arrive_in_direction", "").strip().lower()
        if arrive_dir == 'true':
            score += 12
            feedback_parts.append("Arrive in direction enabled (+12)")
        else:
            feedback_parts.append(
                f"Arrive in direction='{arrive_dir}', expected 'true' (+0)"
            )

        # ========== Criterion 8: Color scheme = Night "2" (11 pts) ==========
        if color_scheme == '2':
            score += 11
            feedback_parts.append("Color scheme set to Night mode (+11)")
        else:
            feedback_parts.append(
                f"Color scheme='{color_scheme}', expected '2' (Night) (+0)"
            )

        passed = score >= PASS_THRESHOLD

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts) or "No criteria evaluated"
        }

    except FileNotFoundError:
        return {"passed": False, "score": 0,
                "feedback": "Result file not found"}
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0,
                "feedback": f"Result JSON malformed: {e}"}
    except Exception as e:
        return {"passed": False, "score": 0,
                "feedback": f"Verifier error: {str(e)}"}
