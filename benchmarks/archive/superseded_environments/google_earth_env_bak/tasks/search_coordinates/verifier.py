"""
Robust verifier for search_coordinates task.

Task: Search for and navigate to specific GPS coordinates (40.7128, -74.0060)
      which is New York City.

Verification Strategy:
1. Verify Google Earth process integrity
2. Extract current view coordinates via multiple methods
3. Verify coordinates match NYC within tolerance
4. Verify appropriate zoom level

This verifier does NOT rely on:
- Keyword matching ("NYC", "manhattan", etc.)
- Agent-writable files like /tmp/task_result.txt
- Loose regex patterns that match false positives
"""

import sys
from pathlib import Path
from typing import Dict, Any

# Add parent directory for shared utilities
sys.path.insert(0, str(Path(__file__).parent.parent))
from verification_utils import (
    set_container_context,
    verify_process_integrity,
    extract_coordinates_multiple_methods,
    coordinates_within_tolerance,
    haversine_distance,
)


# =============================================================================
# TARGET LOCATION: New York City (as specified in task)
# =============================================================================
TARGET_NAME = "New York City"
TARGET_LAT = 40.7128
TARGET_LON = -74.0060

# Tolerance in degrees (~1.1 km)
# The task asks for specific coordinates, so we use a reasonable tolerance
COORDINATE_TOLERANCE_DEGREES = 0.01

# Maximum camera altitude in meters
MAX_VIEW_ALTITUDE_METERS = 15000


# Score threshold for passing
PASS_THRESHOLD = 75


# =============================================================================
# MAIN VERIFICATION FUNCTION
# =============================================================================

def check_coordinates(traj: Dict, env_info: Dict, task_info: Dict) -> Dict[str, Any]:
    """
    Verify that Google Earth has navigated to the target coordinates (NYC).

    Args:
        traj: Trajectory dict with 'steps' and 'episode_dir'
        env_info: Dict with 'env_id', 'episode_dir', 'copy_from_env', 'copy_to_env', 'container'
        task_info: Dict with 'task_id'

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
    # STEP 2: Extract Current View Coordinates
    # =========================================================================
    best_view, all_extractions = extract_coordinates_multiple_methods()

    if best_view is None:
        return {
            "passed": False,
            "score": 25,
            "feedback": "Could not extract coordinates. " + " | ".join(feedback_parts)
        }

    criteria_met += 1
    feedback_parts.append(f"✓ Coordinates via {best_view.source}")

    # =========================================================================
    # STEP 3: Verify Coordinates Match Target
    # =========================================================================
    distance_meters = haversine_distance(
        best_view.latitude, best_view.longitude,
        TARGET_LAT, TARGET_LON
    )

    coordinates_match = coordinates_within_tolerance(
        best_view.latitude, best_view.longitude,
        TARGET_LAT, TARGET_LON,
        COORDINATE_TOLERANCE_DEGREES
    )

    if coordinates_match:
        criteria_met += 1
        feedback_parts.append(f"✓ Location correct ({distance_meters:.0f}m from target)")
    else:
        feedback_parts.append(
            f"✗ Wrong location: ({best_view.latitude:.4f}, {best_view.longitude:.4f}), "
            f"expected ({TARGET_LAT:.4f}, {TARGET_LON:.4f}), {distance_meters/1000:.1f}km away"
        )

    # =========================================================================
    # STEP 4: Verify Zoom Level
    # =========================================================================
    if best_view.altitude is not None:
        if best_view.altitude <= MAX_VIEW_ALTITUDE_METERS:
            criteria_met += 1
            feedback_parts.append(f"✓ Zoom OK ({best_view.altitude:.0f}m)")
        else:
            feedback_parts.append(f"✗ Too zoomed out ({best_view.altitude:.0f}m)")
    else:
        criteria_met += 0.5
        feedback_parts.append("? Zoom not verified")

    # =========================================================================
    # Calculate Score
    # =========================================================================
    score = int((criteria_met / total_criteria) * 100)

    if not coordinates_match:
        score = min(50, score)

    passed = score >= PASS_THRESHOLD
    feedback = f"Score: {score}/100 ({criteria_met:.1f}/{total_criteria} criteria). " + " | ".join(feedback_parts)

    return {"passed": passed, "score": score, "feedback": feedback}
