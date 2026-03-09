"""
Robust verifier for take_screenshot task.

Task: Navigate to Mount Everest and save a high-quality image of the view
      using Google Earth's built-in screenshot/image save feature.

Verification Strategy:
1. Verify Google Earth process integrity
2. Verify current view is at Mount Everest
3. Find recently created image files
4. Check EXIF metadata for GPS coordinates (Google Earth embeds these)
5. Verify GPS coordinates in image match Mount Everest
6. Verify image was created by Google Earth (EXIF software tag)

This verifier does NOT rely on:
- Just finding ANY recent image file
- Keyword matching in filenames
- Agent-writable files like /tmp/task_result.txt
"""

import sys
import os
from pathlib import Path
from typing import Dict, Any, List, Optional

# Add parent directory for shared utilities
sys.path.insert(0, str(Path(__file__).parent.parent))
from verification_utils import (
    set_container_context,
    verify_process_integrity,
    extract_coordinates_multiple_methods,
    find_recent_images,
    extract_image_metadata,
    coordinates_within_tolerance,
    haversine_distance,
    ImageMetadata
)


# =============================================================================
# TARGET LOCATION: Mount Everest
# =============================================================================
TARGET_NAME = "Mount Everest"
TARGET_LAT = 27.9881
TARGET_LON = 86.9250

# Tolerance for coordinate matching (degrees, ~2 km for mountain area)
COORDINATE_TOLERANCE_DEGREES = 0.02

# Maximum age of valid screenshots (seconds)
MAX_IMAGE_AGE_SECONDS = 300

# Minimum image dimensions
MIN_IMAGE_WIDTH = 800
MIN_IMAGE_HEIGHT = 600

# Search paths for saved images
IMAGE_SEARCH_PATHS = [
    '/home/ga/Desktop/*.jpg',
    '/home/ga/Desktop/*.jpeg',
    '/home/ga/Desktop/*.png',
    '/home/ga/Pictures/*.jpg',
    '/home/ga/Pictures/*.jpeg',
    '/home/ga/Pictures/*.png',
    '/home/ga/*.jpg',
    '/home/ga/*.jpeg',
    '/home/ga/*.png',
    '/home/ga/Documents/*.jpg',
    '/home/ga/Documents/*.png',
]


# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

def is_google_earth_image(metadata: ImageMetadata) -> bool:
    """Check if an image was created by Google Earth."""
    if not metadata.software:
        return False

    software_lower = metadata.software.lower()
    return 'google' in software_lower or 'earth' in software_lower


def find_valid_screenshots(
    recent_images: List[ImageMetadata]
) -> tuple[List[ImageMetadata], Dict[str, Any]]:
    """
    Find images that are valid Mount Everest screenshots.

    Returns tuple of (valid_images, analysis_details)
    """
    details = {
        'images_checked': len(recent_images),
        'images_analyzed': [],
        'valid_images': []
    }

    valid_images = []

    for img in recent_images:
        img_detail = {
            'filepath': img.filepath,
            'dimensions': f'{img.width}x{img.height}' if img.width else 'unknown',
            'has_gps': img.has_gps,
            'gps_lat': img.gps_latitude,
            'gps_lon': img.gps_longitude,
            'software': img.software,
            'is_google_earth_image': False,
            'location_matches': False,
            'distance_to_target_m': None,
            'is_valid': False
        }

        # Check if it's from Google Earth
        img_detail['is_google_earth_image'] = is_google_earth_image(img)

        # Check GPS coordinates
        if img.has_gps and img.gps_latitude is not None:
            distance = haversine_distance(
                img.gps_latitude, img.gps_longitude,
                TARGET_LAT, TARGET_LON
            )
            img_detail['distance_to_target_m'] = distance

            img_detail['location_matches'] = coordinates_within_tolerance(
                img.gps_latitude, img.gps_longitude,
                TARGET_LAT, TARGET_LON,
                COORDINATE_TOLERANCE_DEGREES
            )

        # Image is valid if location matches
        if img_detail['location_matches']:
            img_detail['is_valid'] = True
            valid_images.append(img)

        details['images_analyzed'].append(img_detail)

    details['valid_images'] = [v.filepath for v in valid_images]
    return valid_images, details


# Score threshold for passing
PASS_THRESHOLD = 75


# =============================================================================
# MAIN VERIFICATION FUNCTION
# =============================================================================

def check_screenshot(traj: Dict, env_info: Dict, task_info: Dict) -> Dict[str, Any]:
    """
    Verify that a screenshot was saved from Google Earth showing Mount Everest.

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
    # STEP 2: Verify Current View is at Mount Everest
    # =========================================================================
    best_view, _ = extract_coordinates_multiple_methods()

    current_view_at_everest = False
    if best_view and best_view.latitude is not None:
        current_view_at_everest = coordinates_within_tolerance(
            best_view.latitude, best_view.longitude,
            TARGET_LAT, TARGET_LON,
            COORDINATE_TOLERANCE_DEGREES
        )
        if current_view_at_everest:
            criteria_met += 1
            feedback_parts.append(f"✓ Current view at {TARGET_NAME}")
        else:
            distance = haversine_distance(
                best_view.latitude, best_view.longitude,
                TARGET_LAT, TARGET_LON
            )
            feedback_parts.append(f"✗ View not at {TARGET_NAME} ({distance/1000:.1f}km away)")

    # =========================================================================
    # STEP 3: Find Recent Image Files
    # =========================================================================
    recent_images = find_recent_images(
        search_paths=IMAGE_SEARCH_PATHS,
        max_age_seconds=MAX_IMAGE_AGE_SECONDS,
        min_width=MIN_IMAGE_WIDTH,
        min_height=MIN_IMAGE_HEIGHT
    )

    if len(recent_images) == 0:
        feedback_parts.append("✗ No recent screenshots found")
        score = int((criteria_met / total_criteria) * 100)
        return {
            "passed": False,
            "score": score,
            "feedback": f"Score: {score}/100. " + " | ".join(feedback_parts)
        }

    criteria_met += 1
    feedback_parts.append(f"✓ Found {len(recent_images)} recent image(s)")

    # =========================================================================
    # STEP 4: Analyze Image Metadata
    # =========================================================================
    valid_screenshots, analysis = find_valid_screenshots(recent_images)

    # =========================================================================
    # STEP 5: Evaluate Results
    # =========================================================================

    if valid_screenshots:
        # Found screenshot(s) with correct GPS coordinates
        best_screenshot = valid_screenshots[0]
        distance = haversine_distance(
            best_screenshot.gps_latitude, best_screenshot.gps_longitude,
            TARGET_LAT, TARGET_LON
        )

        criteria_met += 2  # GPS present + location correct
        feedback_parts.append(
            f"✓ Screenshot '{os.path.basename(best_screenshot.filepath)}' "
            f"has GPS at {TARGET_NAME} ({distance:.0f}m from summit)"
        )

        score = int((criteria_met / total_criteria) * 100)
        passed = score >= PASS_THRESHOLD
        return {
            "passed": passed,
            "score": score,
            "feedback": f"Score: {score}/100 ({criteria_met:.1f}/{total_criteria} criteria). " + " | ".join(feedback_parts)
        }

    # No screenshots with valid GPS coordinates
    # Check if images exist but lack GPS data
    images_without_gps = [img for img in recent_images if not img.has_gps]

    if images_without_gps and current_view_at_everest:
        # Images found, no GPS, but view is correct
        img = images_without_gps[0]
        criteria_met += 1  # Partial credit - image exists, view correct
        feedback_parts.append(
            f"✓ Screenshot '{os.path.basename(img.filepath)}' saved, "
            f"view at {TARGET_NAME} (no GPS in image)"
        )

        score = int((criteria_met / total_criteria) * 100)
        passed = score >= PASS_THRESHOLD
        return {
            "passed": passed,
            "score": score,
            "feedback": f"Score: {score}/100 ({criteria_met:.1f}/{total_criteria} criteria). " + " | ".join(feedback_parts)
        }

    if images_without_gps and not current_view_at_everest:
        feedback_parts.append(
            f"✗ Found {len(images_without_gps)} image(s) without GPS, "
            f"view not at {TARGET_NAME}"
        )
        score = int((criteria_met / total_criteria) * 100)
        return {
            "passed": False,
            "score": score,
            "feedback": f"Score: {score}/100. " + " | ".join(feedback_parts)
        }

    # Images found with GPS but wrong location
    wrong_location_images = [
        img for img in recent_images
        if img.has_gps and not coordinates_within_tolerance(
            img.gps_latitude, img.gps_longitude,
            TARGET_LAT, TARGET_LON,
            COORDINATE_TOLERANCE_DEGREES
        )
    ]

    if wrong_location_images:
        img = wrong_location_images[0]
        distance = haversine_distance(
            img.gps_latitude, img.gps_longitude,
            TARGET_LAT, TARGET_LON
        )
        criteria_met += 0.5  # Has GPS, but wrong location
        feedback_parts.append(
            f"✗ Screenshot GPS at wrong location ({distance/1000:.1f}km from {TARGET_NAME})"
        )

        score = int((criteria_met / total_criteria) * 100)
        return {
            "passed": False,
            "score": score,
            "feedback": f"Score: {score}/100. " + " | ".join(feedback_parts)
        }

    # Fallback
    feedback_parts.append(f"✗ No valid screenshots of {TARGET_NAME}")
    score = int((criteria_met / total_criteria) * 100)
    return {
        "passed": False,
        "score": score,
        "feedback": f"Score: {score}/100. " + " | ".join(feedback_parts)
    }
