"""
Verifier for take_screenshot task.

Task: "Capture and save a screenshot of a geographic location using Google Earth's
       built-in screenshot/image save feature. Navigate to Mount Everest and save
       a high-quality image of the view to the Desktop."

What this actually means:
- Agent should navigate to Mount Everest area
- Agent should save an image file to the Desktop
- Image should show mountain terrain (Mount Everest / Himalayas)
- "High-quality" means reasonable resolution, not a tiny thumbnail

Verification Strategy:
- Setup script cleans Desktop of images first
- Check for NEW image files on Desktop
- Check image dimensions (high-quality = reasonable size)
- VLM: Verify image shows mountain terrain / Himalayan area
"""

import os
import sys
import logging
from pathlib import Path
from datetime import datetime, timedelta
from typing import Dict, Any, List, Optional, Tuple

from gym_anything.vlm import get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# =============================================================================
# CONSTANTS
# =============================================================================

# Directories to search for saved images
IMAGE_SEARCH_DIRS = [
    '/home/ga/Desktop',
    '/home/ga/Pictures',
    '/home/ga/Documents',
    '/home/ga',
]

# Image extensions to look for
IMAGE_EXTENSIONS = ['.jpg', '.jpeg', '.png', '.bmp', '.tiff', '.tif']

# Minimum dimensions for "high-quality" image
MIN_IMAGE_WIDTH = 800
MIN_IMAGE_HEIGHT = 600

# Maximum age of valid image files (seconds since task started)
MAX_IMAGE_AGE_SECONDS = 300


# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

def find_new_images(search_dirs: List[str], max_age_seconds: int = 300) -> List[Dict[str, Any]]:
    """
    Find image files created recently (likely during the task).
    Returns list of dicts with file info.
    """
    images = []
    now = datetime.now()
    cutoff = now - timedelta(seconds=max_age_seconds)

    for search_dir in search_dirs:
        if not os.path.exists(search_dir):
            continue

        try:
            for filename in os.listdir(search_dir):
                filepath = os.path.join(search_dir, filename)

                # Skip directories
                if os.path.isdir(filepath):
                    continue

                # Check extension
                _, ext = os.path.splitext(filename)
                if ext.lower() not in IMAGE_EXTENSIONS:
                    continue

                # Check modification time
                try:
                    mtime = datetime.fromtimestamp(os.path.getmtime(filepath))
                    if mtime < cutoff:
                        continue
                except OSError:
                    continue

                # Get file info
                image_info = {
                    'filepath': filepath,
                    'filename': filename,
                    'directory': search_dir,
                    'extension': ext.lower(),
                    'mtime': mtime,
                    'size_bytes': os.path.getsize(filepath),
                    'width': None,
                    'height': None,
                }

                # Try to get dimensions
                try:
                    from PIL import Image
                    with Image.open(filepath) as img:
                        image_info['width'] = img.width
                        image_info['height'] = img.height
                except ImportError:
                    # PIL not available, try to get dimensions another way
                    pass
                except Exception as e:
                    logger.warning(f"Could not get dimensions for {filepath}: {e}")

                images.append(image_info)

        except PermissionError:
            continue

    # Sort by modification time, newest first
    images.sort(key=lambda x: x['mtime'], reverse=True)
    return images


def is_high_quality_image(image_info: Dict[str, Any]) -> Tuple[bool, str]:
    """
    Check if an image meets "high-quality" criteria.
    Returns (is_high_quality, reason).
    """
    width = image_info.get('width')
    height = image_info.get('height')
    size_bytes = image_info.get('size_bytes', 0)

    # If we have dimensions, check them
    if width is not None and height is not None:
        if width >= MIN_IMAGE_WIDTH and height >= MIN_IMAGE_HEIGHT:
            return True, f"{width}x{height} meets quality threshold"
        else:
            return False, f"{width}x{height} is below {MIN_IMAGE_WIDTH}x{MIN_IMAGE_HEIGHT} threshold"

    # Fall back to file size heuristic (>50KB suggests reasonable quality)
    if size_bytes > 50000:
        return True, f"{size_bytes/1024:.0f}KB file size suggests reasonable quality"
    else:
        return False, f"{size_bytes/1024:.0f}KB file size seems too small"


# =============================================================================
# VLM PROMPT
# =============================================================================

VERIFICATION_PROMPT = """You are verifying if a computer agent completed a screenshot task in Google Earth.

TASK: Navigate to Mount Everest and save a screenshot of the view.

Look at this screenshot and determine:

1. Is this Google Earth (satellite/aerial imagery application)?

2. Does this show the Mount Everest / Himalayan mountain region? Look for:
   - High mountain peaks with snow/ice
   - Rugged terrain typical of the Himalayas
   - The general area of the Nepal/Tibet border
   - Any view that could reasonably be Mount Everest or surrounding peaks

3. Is this a reasonable quality image?
   - Clear view of terrain (not obscured by menus/dialogs)
   - Actual satellite/terrain imagery visible (not just UI elements)

Note: The task doesn't require a specific zoom level or angle. A wide view showing the Himalayan range OR a close-up of Everest area are both acceptable.

Respond in JSON format:
{
    "is_google_earth": true/false,
    "shows_mountain_terrain": true/false,
    "appears_to_be_himalayas": true/false,
    "clear_view_of_terrain": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation of what you see"
}
"""


# =============================================================================
# MAIN VERIFICATION FUNCTION
# =============================================================================

def check_screenshot(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify that a screenshot of Mount Everest was saved to the Desktop.

    Uses hybrid verification:
    - Programmatic: Find new image files on Desktop with reasonable quality
    - VLM: Verify image shows Mount Everest / Himalayan area

    Args:
        traj: Trajectory data with frames, steps, episode_dir
        env_info: Environment info
        task_info: Task info with task_id

    Returns:
        dict with 'passed' (bool), 'score' (int 0-100), 'feedback' (str)
    """
    feedback_parts = []
    result_details = {}

    # =========================================================================
    # PROGRAMMATIC CHECK: Find new image files
    # =========================================================================

    new_images = find_new_images(IMAGE_SEARCH_DIRS, MAX_IMAGE_AGE_SECONDS)
    result_details['images_found'] = len(new_images)
    result_details['image_details'] = [
        {
            'filepath': img['filepath'],
            'dimensions': f"{img['width']}x{img['height']}" if img['width'] else 'unknown',
            'size_kb': img['size_bytes'] / 1024,
        }
        for img in new_images[:5]  # Limit to first 5
    ]

    # Find images on Desktop specifically (primary target)
    desktop_images = [img for img in new_images if '/Desktop' in img['filepath']]
    other_images = [img for img in new_images if '/Desktop' not in img['filepath']]

    # Check for high-quality images
    best_image = None
    image_quality_ok = False

    # Prefer Desktop images
    for img in desktop_images + other_images:
        is_hq, reason = is_high_quality_image(img)
        if is_hq:
            best_image = img
            image_quality_ok = True
            break

    # If no high-quality image, take any image
    if not best_image and (desktop_images or other_images):
        best_image = desktop_images[0] if desktop_images else other_images[0]

    file_check_passed = False
    file_check_partial = False

    if best_image:
        is_on_desktop = '/Desktop' in best_image['filepath']
        is_hq, quality_reason = is_high_quality_image(best_image)

        result_details['best_image'] = {
            'filepath': best_image['filepath'],
            'on_desktop': is_on_desktop,
            'is_high_quality': is_hq,
            'quality_reason': quality_reason,
        }

        if is_on_desktop and is_hq:
            file_check_passed = True
            dims = f"{best_image['width']}x{best_image['height']}" if best_image['width'] else f"{best_image['size_bytes']/1024:.0f}KB"
            feedback_parts.append(f"✅ High-quality image saved to Desktop: {best_image['filename']} ({dims})")
        elif is_on_desktop:
            file_check_partial = True
            feedback_parts.append(f"⚠️ Image saved to Desktop but quality questionable: {best_image['filename']}")
        elif is_hq:
            file_check_partial = True
            feedback_parts.append(f"⚠️ High-quality image saved but not to Desktop: {best_image['filepath']}")
        else:
            file_check_partial = True
            feedback_parts.append(f"⚠️ Image found but not on Desktop and quality unclear")
    else:
        feedback_parts.append("❌ No new image files found")

    # =========================================================================
    # VLM CHECK: Verify view shows Mount Everest area
    # =========================================================================

    vlm_passed = False
    vlm_partial = False

    query_vlm = env_info.get('query_vlm')

    # First, try to use the saved image for VLM verification if available
    vlm_image = None
    if best_image:
        vlm_image = best_image['filepath']
    else:
        # Fall back to final screenshot from trajectory
        vlm_image = get_final_screenshot(traj)

    result_details['vlm_image'] = vlm_image

    if query_vlm and vlm_image:
        vlm_result = query_vlm(
            prompt=VERIFICATION_PROMPT,
            image=vlm_image,
        )
        result_details['vlm_result'] = vlm_result

        if vlm_result.get("success"):
            parsed = vlm_result.get("parsed", {})

            is_google_earth = parsed.get("is_google_earth", False)
            shows_mountains = parsed.get("shows_mountain_terrain", False)
            is_himalayas = parsed.get("appears_to_be_himalayas", False)
            clear_view = parsed.get("clear_view_of_terrain", False)
            confidence = parsed.get("confidence", "low")
            reasoning = parsed.get("reasoning", "")

            if is_google_earth and shows_mountains and is_himalayas:
                if clear_view:
                    vlm_passed = True
                    feedback_parts.append(f"✅ Mount Everest/Himalayas visible in image ({confidence})")
                else:
                    vlm_partial = True
                    feedback_parts.append(f"✅ Himalayas visible but view partially obscured ({confidence})")
            elif is_google_earth and shows_mountains:
                vlm_partial = True
                feedback_parts.append(f"⚠️ Mountain terrain visible but uncertain if Himalayas ({confidence})")
            elif is_google_earth:
                feedback_parts.append(f"❌ Google Earth visible but no mountain terrain ({confidence})")
            else:
                feedback_parts.append("❌ Image doesn't appear to be from Google Earth")

            if reasoning:
                result_details['vlm_reasoning'] = reasoning
        else:
            feedback_parts.append(f"⚠️ VLM check failed: {vlm_result.get('error', 'Unknown')}")
    else:
        feedback_parts.append("⚠️ No image available for VLM verification")

    # =========================================================================
    # CALCULATE FINAL RESULT
    # =========================================================================

    # Scoring:
    # - File check passed (desktop + high-quality): 50 points
    # - File check partial: 25 points
    # - VLM check passed (mountains + himalayas): 50 points
    # - VLM check partial: 25 points

    score = 0
    if file_check_passed:
        score += 50
    elif file_check_partial:
        score += 25

    if vlm_passed:
        score += 50
    elif vlm_partial:
        score += 25

    # Pass if:
    # - Both file and VLM checks at least partially pass (score >= 50)
    # - OR file check fully passed and VLM unavailable
    passed = score >= 50

    # Summary
    if passed and score >= 80:
        feedback_parts.append("🎉 Successfully saved screenshot of Mount Everest!")
    elif passed:
        feedback_parts.append("✅ Screenshot task verified")
    else:
        feedback_parts.append("❌ Screenshot of Mount Everest not confirmed")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": result_details,
    }
