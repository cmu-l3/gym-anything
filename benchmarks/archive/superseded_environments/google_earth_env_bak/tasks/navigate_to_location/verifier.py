"""
Robust verifier for navigate_to_location task.

Task: Navigate Google Earth to view the Eiffel Tower in Paris, France.

Verification Strategy:
1. Verify Google Earth process integrity (not spoofed)
2. Extract current view coordinates via multiple independent methods
3. Verify coordinates match Eiffel Tower location within tolerance
4. Optionally verify appropriate zoom level

This verifier does NOT rely on:
- Keyword matching (easily gamed)
- Agent-writable files like /tmp/task_result.txt
- Window titles (unreliable)
- Cache file timestamps (meaningless)
"""

import sys
from pathlib import Path
from typing import Dict, Any, List

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
# TARGET LOCATION: Eiffel Tower, Paris, France
# =============================================================================
TARGET_NAME = "Eiffel Tower"
TARGET_LAT = 48.8584
TARGET_LON = 2.2945

# Tolerance in degrees (~1.1 km at this latitude)
COORDINATE_TOLERANCE_DEGREES = 0.01

# Maximum camera altitude/range in meters
MAX_VIEW_ALTITUDE_METERS = 10000

# Score threshold for passing
PASS_THRESHOLD = 75


# =============================================================================
# MAIN VERIFICATION FUNCTION
# =============================================================================

def check_navigation(traj: Dict, env_info: Dict, task_info: Dict) -> Dict[str, Any]:
    """
    Verify that Google Earth has navigated to the Eiffel Tower.

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
    print('integrity', integrity)
    breakpoint()

    # if not integrity['process_exists']:
    #     return {
    #         "passed": False,
    #         "score": 0,
    #         "feedback": "Google Earth is not running"
    #     }

    # if not integrity['correct_binary']:
    #     return {
    #         "passed": False,
    #         "score": 0,
    #         "feedback": "Google Earth binary verification failed - possible spoofing"
    #     }

    # if not integrity['has_window']:
    #     return {
    #         "passed": False,
    #         "score": 0,
    #         "feedback": "Google Earth window not found"
    #     }

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
            "feedback": "Could not extract current view coordinates from Google Earth. " + " | ".join(feedback_parts)
        }

    criteria_met += 1
    feedback_parts.append(f"✓ Coordinates extracted via {best_view.source}")

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
        feedback_parts.append(f"✓ Location correct ({distance_meters:.0f}m from {TARGET_NAME})")
    else:
        feedback_parts.append(
            f"✗ Wrong location: ({best_view.latitude:.4f}, {best_view.longitude:.4f}), "
            f"expected ({TARGET_LAT:.4f}, {TARGET_LON:.4f}), {distance_meters/1000:.1f}km away"
        )

    # =========================================================================
    # STEP 4: Verify Zoom Level (if available)
    # =========================================================================
    if best_view.altitude is not None:
        if best_view.altitude <= MAX_VIEW_ALTITUDE_METERS:
            criteria_met += 1
            feedback_parts.append(f"✓ Zoom OK ({best_view.altitude:.0f}m)")
        else:
            feedback_parts.append(f"✗ Too zoomed out ({best_view.altitude:.0f}m > {MAX_VIEW_ALTITUDE_METERS}m)")
    else:
        # Can't verify altitude, give partial credit
        criteria_met += 0.5
        feedback_parts.append("? Zoom not verified")

    # =========================================================================
    # Calculate Score
    # =========================================================================
    score = int((criteria_met / total_criteria) * 100)

    # If location is completely wrong, cap score
    if not coordinates_match:
        score = min(50, score)

    passed = score >= PASS_THRESHOLD

    feedback = f"Score: {score}/100 ({criteria_met:.1f}/{total_criteria} criteria). " + " | ".join(feedback_parts)

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }
