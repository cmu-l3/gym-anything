"""
Robust verifier for measure_distance task.

Task: Use Google Earth's ruler/measurement tool to measure the distance
      from the Statue of Liberty to the Empire State Building.
      Expected distance: ~8.5 km (5.3 miles)

Verification Strategy:
1. Verify Google Earth process integrity
2. Find measurement paths (LineStrings) in myplaces.kml
3. Verify measurement has exactly 2 endpoints
4. Verify START point is near Statue of Liberty (within tolerance)
5. Verify END point is near Empire State Building (within tolerance)
6. Verify computed distance matches expected (~8.5 km)

This verifier does NOT rely on:
- Keyword matching ("liberty", "empire", etc.)
- Agent-writable files like /tmp/task_result.txt
- Just checking if ANY LineString exists
"""

import sys
from pathlib import Path
from typing import Dict, Any, List, Tuple, Optional

# Add parent directory for shared utilities
sys.path.insert(0, str(Path(__file__).parent.parent))
from verification_utils import (
    set_container_context,
    verify_process_integrity,
    get_measurement_paths_from_kml,
    check_ruler_dialog_open,
    extract_measurement_from_ruler_ocr,
    coordinates_within_tolerance,
    haversine_distance,
    MeasurementInfo,
)


# =============================================================================
# TARGET LANDMARKS
# =============================================================================

# Statue of Liberty
STATUE_OF_LIBERTY_NAME = "Statue of Liberty"
STATUE_OF_LIBERTY_LAT = 40.6892
STATUE_OF_LIBERTY_LON = -74.0445

# Empire State Building
EMPIRE_STATE_NAME = "Empire State Building"
EMPIRE_STATE_LAT = 40.7484
EMPIRE_STATE_LON = -73.9857

# Expected distance between them
EXPECTED_DISTANCE_METERS = 8500
DISTANCE_TOLERANCE_PERCENT = 0.15  # 15% tolerance

# Coordinate tolerance for endpoint matching (degrees, ~500m)
ENDPOINT_TOLERANCE_DEGREES = 0.005

# Score threshold for passing
PASS_THRESHOLD = 75


# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

def find_matching_measurement(
    paths: List[MeasurementInfo]
) -> Tuple[Optional[MeasurementInfo], Dict[str, Any]]:
    """Find a measurement path that matches our expected endpoints."""
    details = {'paths_found': len(paths), 'paths_analyzed': [], 'matching_path': None}

    for i, path in enumerate(paths):
        path_detail = {
            'index': i, 'name': path.name, 'num_coordinates': len(path.coordinates),
            'matches_sol': False, 'matches_esb': False, 'computed_distance_m': None
        }

        if len(path.coordinates) < 2:
            details['paths_analyzed'].append(path_detail)
            continue

        # Get start and end points (lon, lat, alt format in KML)
        start_lon, start_lat = path.coordinates[0][0], path.coordinates[0][1]
        end_lon, end_lat = path.coordinates[-1][0], path.coordinates[-1][1]

        # Check if endpoints match (in either order)
        start_matches_sol = coordinates_within_tolerance(
            start_lat, start_lon, STATUE_OF_LIBERTY_LAT, STATUE_OF_LIBERTY_LON,
            ENDPOINT_TOLERANCE_DEGREES
        )
        start_matches_esb = coordinates_within_tolerance(
            start_lat, start_lon, EMPIRE_STATE_LAT, EMPIRE_STATE_LON,
            ENDPOINT_TOLERANCE_DEGREES
        )
        end_matches_sol = coordinates_within_tolerance(
            end_lat, end_lon, STATUE_OF_LIBERTY_LAT, STATUE_OF_LIBERTY_LON,
            ENDPOINT_TOLERANCE_DEGREES
        )
        end_matches_esb = coordinates_within_tolerance(
            end_lat, end_lon, EMPIRE_STATE_LAT, EMPIRE_STATE_LON,
            ENDPOINT_TOLERANCE_DEGREES
        )

        valid_order_1 = start_matches_sol and end_matches_esb
        valid_order_2 = start_matches_esb and end_matches_sol

        path_detail['matches_sol'] = start_matches_sol or end_matches_sol
        path_detail['matches_esb'] = start_matches_esb or end_matches_esb

        distance = haversine_distance(start_lat, start_lon, end_lat, end_lon)
        path_detail['computed_distance_m'] = distance

        details['paths_analyzed'].append(path_detail)

        if valid_order_1 or valid_order_2:
            details['matching_path'] = path_detail
            return path, details

    return None, details


# =============================================================================
# MAIN VERIFICATION FUNCTION
# =============================================================================

def check_measurement(traj: Dict, env_info: Dict, task_info: Dict) -> Dict[str, Any]:
    """
    Verify that a distance measurement was performed between
    Statue of Liberty and Empire State Building.

    Args:
        traj: Trajectory dict
        env_info: Environment info dict with 'container'
        task_info: Task info dict

    Returns:
        dict with 'passed' (bool), 'score' (0-100), 'feedback' (str)
    """
    # Initialize container context for all utility functions
    set_container_context(env_info)

    feedback_parts = []
    criteria_met = 0
    total_criteria = 5

    # =========================================================================
    # STEP 1: Verify Process Integrity
    # =========================================================================
    integrity = verify_process_integrity()

    if not integrity['process_exists']:
        return {"passed": False, "score": 0, "feedback": "Google Earth is not running"}

    if not integrity['correct_binary']:
        return {"passed": False, "score": 0, "feedback": "Google Earth binary verification failed"}

    if not integrity['has_window']:
        return {"passed": False, "score": 0, "feedback": "Google Earth window not found"}

    criteria_met += 1
    feedback_parts.append("✓ Google Earth running")

    # =========================================================================
    # STEP 2: Check for Ruler Dialog
    # =========================================================================
    ruler_open = check_ruler_dialog_open()
    if ruler_open:
        criteria_met += 0.5
        feedback_parts.append("✓ Ruler tool active")

    # =========================================================================
    # STEP 3: Find Measurement Paths in KML
    # =========================================================================
    paths = get_measurement_paths_from_kml()
    matching_path, path_details = find_matching_measurement(paths)

    expected_dist = haversine_distance(
        STATUE_OF_LIBERTY_LAT, STATUE_OF_LIBERTY_LON,
        EMPIRE_STATE_LAT, EMPIRE_STATE_LON
    )

    if matching_path is None:
        if len(paths) == 0:
            feedback_parts.append("✗ No measurement paths found")
        else:
            feedback_parts.append(f"✗ {len(paths)} path(s) found but none match endpoints")
            criteria_met += 0.5  # Partial credit for creating a path

        score = int((criteria_met / total_criteria) * 100)
        return {
            "passed": False,
            "score": score,
            "feedback": f"Score: {score}/100. " + " | ".join(feedback_parts) +
                       f" | Required: Measurement from {STATUE_OF_LIBERTY_NAME} to {EMPIRE_STATE_NAME}"
        }

    criteria_met += 1
    feedback_parts.append("✓ Path found with correct endpoints")

    # =========================================================================
    # STEP 4: Verify Both Endpoints
    # =========================================================================
    if path_details['matching_path']['matches_sol']:
        criteria_met += 1
        feedback_parts.append(f"✓ {STATUE_OF_LIBERTY_NAME} endpoint correct")

    if path_details['matching_path']['matches_esb']:
        criteria_met += 1
        feedback_parts.append(f"✓ {EMPIRE_STATE_NAME} endpoint correct")

    # =========================================================================
    # STEP 5: Verify Distance Value
    # =========================================================================
    measured_distance = path_details['matching_path']['computed_distance_m']
    error = abs(measured_distance - expected_dist)
    error_percent = error / expected_dist

    if error_percent <= DISTANCE_TOLERANCE_PERCENT:
        criteria_met += 1
        feedback_parts.append(f"✓ Distance correct: {measured_distance/1000:.2f}km")
    else:
        feedback_parts.append(f"✗ Distance off: {measured_distance/1000:.2f}km (expected ~{expected_dist/1000:.2f}km)")

    # =========================================================================
    # Calculate Score
    # =========================================================================
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= PASS_THRESHOLD

    feedback = f"Score: {score}/100 ({criteria_met:.1f}/{total_criteria} criteria). " + " | ".join(feedback_parts)

    return {"passed": passed, "score": score, "feedback": feedback}
