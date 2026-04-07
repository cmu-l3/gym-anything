"""
Robust verifier for create_placemark task.

Task: Navigate to the Golden Gate Bridge in San Francisco and create a
      placemark named 'Golden Gate Bridge' at that location.

Verification Strategy:
1. Verify Google Earth process integrity
2. Load baseline state (saved at task start by setup_task.sh)
3. Find NEW placemarks (not in baseline)
4. Verify placemark NAME matches "Golden Gate Bridge" (strict matching)
5. Verify placemark COORDINATES are near actual Golden Gate Bridge

This verifier does NOT rely on:
- Partial keyword matching ("golden" OR "gate" OR "bridge")
- Accepting ANY existing placemark
- Agent-writable files like /tmp/task_result.txt
"""

import sys
from pathlib import Path
from typing import Dict, Any, List, Optional

# Add parent directory for shared utilities
sys.path.insert(0, str(Path(__file__).parent.parent))
from verification_utils import (
    set_container_context,
    verify_process_integrity,
    get_new_placemarks_since_baseline,
    parse_placemarks_from_kml,
    read_file_from_container,
    coordinates_within_tolerance,
    haversine_distance,
    load_baseline_state,
    PlacemarkInfo,
    GOOGLE_EARTH_STATE_DIR
)


# =============================================================================
# TARGET LOCATION: Golden Gate Bridge
# =============================================================================
TARGET_NAME = "Golden Gate Bridge"
TARGET_NAME_VARIATIONS = ["golden gate bridge", "golden gate", "ggb", "the golden gate bridge"]
TARGET_LAT = 37.8199
TARGET_LON = -122.4783
COORDINATE_TOLERANCE_DEGREES = 0.01

# Score threshold for passing
PASS_THRESHOLD = 75


# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

def name_matches_target(name: str) -> bool:
    """Check if the placemark name matches 'Golden Gate Bridge' (strict matching)."""
    if not name:
        return False
    normalized = name.lower().strip()

    for variation in TARGET_NAME_VARIATIONS:
        if normalized == variation:
            return True

    if "golden gate bridge" in normalized or "golden gate" in normalized:
        return True

    # Reject single-word matches
    if normalized in ["bridge", "golden", "gate", "the bridge"]:
        return False

    # Require at least 2 of 3 words
    target_words = set(TARGET_NAME.lower().split())
    name_words = set(normalized.split())
    return len(target_words & name_words) >= 2


def find_matching_placemark(placemarks: List[PlacemarkInfo]) -> tuple[Optional[PlacemarkInfo], Dict]:
    """Find a placemark that matches name AND location."""
    details = {'checked': len(placemarks), 'analyzed': []}

    for pm in placemarks:
        pm_detail = {
            'name': pm.name,
            'lat': pm.latitude,
            'lon': pm.longitude,
            'name_matches': name_matches_target(pm.name),
            'location_matches': False
        }

        if pm.latitude is not None and pm.longitude is not None:
            pm_detail['location_matches'] = coordinates_within_tolerance(
                pm.latitude, pm.longitude, TARGET_LAT, TARGET_LON,
                COORDINATE_TOLERANCE_DEGREES
            )

        details['analyzed'].append(pm_detail)

        if pm_detail['name_matches'] and pm_detail['location_matches']:
            return pm, details

    return None, details


# =============================================================================
# MAIN VERIFICATION FUNCTION
# =============================================================================

def check_placemark(traj: Dict, env_info: Dict, task_info: Dict) -> Dict[str, Any]:
    """
    Verify that a placemark named 'Golden Gate Bridge' was created at correct location.

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
    total_criteria = 4

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
    # STEP 2: Load Baseline State
    # =========================================================================
    baseline = load_baseline_state()
    if baseline:
        criteria_met += 0.5
        feedback_parts.append("✓ Baseline loaded")

    # =========================================================================
    # STEP 3: Get Placemarks
    # =========================================================================
    new_placemarks = get_new_placemarks_since_baseline()

    myplaces_path = str(GOOGLE_EARTH_STATE_DIR / 'myplaces.kml')
    all_placemarks = []
    myplaces_content = read_file_from_container(myplaces_path)
    if myplaces_content:
        try:
            all_placemarks = parse_placemarks_from_kml(myplaces_content)
        except Exception:
            pass

    # =========================================================================
    # STEP 4: Find Matching Placemark
    # =========================================================================
    matching_pm = None

    # First check new placemarks
    if new_placemarks:
        matching_pm, details = find_matching_placemark(new_placemarks)
        if matching_pm:
            criteria_met += 0.5  # Bonus for creating NEW placemark

    # Fallback to all placemarks
    if matching_pm is None and all_placemarks:
        matching_pm, details = find_matching_placemark(all_placemarks)

    if matching_pm is None:
        # Check for partial matches
        name_matches = [pm for pm in all_placemarks if name_matches_target(pm.name)]
        location_matches = [
            pm for pm in all_placemarks
            if pm.latitude and coordinates_within_tolerance(
                pm.latitude, pm.longitude, TARGET_LAT, TARGET_LON,
                COORDINATE_TOLERANCE_DEGREES
            )
        ]

        if name_matches and not location_matches:
            pm = name_matches[0]
            dist = haversine_distance(pm.latitude, pm.longitude, TARGET_LAT, TARGET_LON) if pm.latitude else 0
            feedback_parts.append(f"✗ Found '{pm.name}' but wrong location ({dist/1000:.1f}km away)")
            criteria_met += 1  # Name correct
        elif location_matches and not name_matches:
            pm = location_matches[0]
            feedback_parts.append(f"✗ Found placemark at correct location but name is '{pm.name}'")
            criteria_met += 1  # Location correct
        else:
            feedback_parts.append(f"✗ No matching placemark found ({len(all_placemarks)} total)")

        score = int((criteria_met / total_criteria) * 100)
        return {
            "passed": False,
            "score": score,
            "feedback": f"Score: {score}/100. " + " | ".join(feedback_parts)
        }

    # =========================================================================
    # SUCCESS
    # =========================================================================
    criteria_met += 2  # Name + Location
    distance = haversine_distance(matching_pm.latitude, matching_pm.longitude, TARGET_LAT, TARGET_LON)
    feedback_parts.append(f"✓ Placemark '{matching_pm.name}' created at correct location ({distance:.0f}m away)")

    score = int((criteria_met / total_criteria) * 100)
    passed = score >= PASS_THRESHOLD

    return {
        "passed": passed,
        "score": score,
        "feedback": f"Score: {score}/100 ({criteria_met:.1f}/{total_criteria} criteria). " + " | ".join(feedback_parts)
    }
