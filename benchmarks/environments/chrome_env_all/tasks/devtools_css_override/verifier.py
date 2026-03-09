#!/usr/bin/env python3
"""
Verifier for Chrome DevTools CSS Override Task (devtools_css_override@1)
Task: Use DevTools Elements panel to modify heading CSS styles

Verification Strategy:
1. Screenshot-based color analysis (primary method)
2. Before/after comparison to detect changes
3. Specific color detection (gold background, dark blue text)
4. Region-based analysis focused on heading area
5. Multi-criteria scoring for robustness
"""

import logging
import sys
import os
import tempfile
from pathlib import Path
from typing import Dict, Any, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Try to import image processing libraries
try:
    from PIL import Image
    import numpy as np
    HAS_PIL = True
except ImportError:
    HAS_PIL = False
    logger.warning("PIL/Pillow not available, verification will be limited")


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for devtools_css_override@1 task.
    
    Verifies that:
    1. Heading background color changed to gold/yellow
    2. Heading text color changed to dark blue
    3. Changes are visible in screenshot
    4. Element was correctly targeted
    5. Visual changes are substantial
    
    Args:
        traj: Trajectory data (unused)
        env_info: Environment information including copy_from_env
        task_info: Task configuration
        
    Returns:
        Dict with passed (bool), score (int 0-100), and feedback (str)
    """
    if not HAS_PIL:
        return {
            "passed": False,
            "score": 0,
            "feedback": "PIL/Pillow library not available - cannot perform visual verification"
        }
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "copy_from_env function not available"
        }
    
    try:
        # Retrieve screenshots from container
        before_img, after_img, error = get_screenshots(copy_from_env)
        
        if before_img is None or after_img is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to retrieve screenshots: {error}"
            }
        
        # Perform multi-criteria verification
        result = verify_css_changes(before_img, after_img)
        
        # Cleanup temporary files
        cleanup_temp_files()
        
        return result
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        cleanup_temp_files()
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }


def get_screenshots(copy_from_env) -> Tuple[Optional[Image.Image], Optional[Image.Image], str]:
    """
    Retrieve before and after screenshots from container.
    
    Returns:
        Tuple of (before_image, after_image, error_message)
    """
    before_img = None
    after_img = None
    
    # Try to get before screenshot
    before_paths = [
        "/tmp/devtools_verification/devtools_before.png",
        "/tmp/devtools_before.png"
    ]
    
    for path in before_paths:
        try:
            temp_before = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
            temp_before.close()
            
            logger.info(f"Attempting to copy before screenshot from: {path}")
            copy_from_env(path, temp_before.name)
            
            if os.path.exists(temp_before.name) and os.path.getsize(temp_before.name) > 0:
                before_img = Image.open(temp_before.name)
                logger.info(f"✓ Loaded before screenshot from {path}")
                break
            else:
                os.unlink(temp_before.name)
        except Exception as e:
            logger.debug(f"Could not load from {path}: {e}")
            if os.path.exists(temp_before.name):
                os.unlink(temp_before.name)
    
    # Try to get after screenshot
    after_paths = [
        "/tmp/devtools_verification/devtools_after.png",
        "/tmp/devtools_after.png"
    ]
    
    for path in after_paths:
        try:
            temp_after = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
            temp_after.close()
            
            logger.info(f"Attempting to copy after screenshot from: {path}")
            copy_from_env(path, temp_after.name)
            
            if os.path.exists(temp_after.name) and os.path.getsize(temp_after.name) > 0:
                after_img = Image.open(temp_after.name)
                logger.info(f"✓ Loaded after screenshot from {path}")
                break
            else:
                os.unlink(temp_after.name)
        except Exception as e:
            logger.debug(f"Could not load from {path}: {e}")
            if os.path.exists(temp_after.name):
                os.unlink(temp_after.name)
    
    if before_img is None:
        return None, None, "Could not load before screenshot"
    if after_img is None:
        return None, None, "Could not load after screenshot"
    
    return before_img, after_img, ""


def verify_css_changes(before_img: Image.Image, after_img: Image.Image) -> Dict[str, Any]:
    """
    Verify CSS changes using image analysis.
    
    Criteria:
    1. Substantial changes detected between before/after
    2. Gold/yellow background color present in after image
    3. Dark blue text color present in after image
    4. Changes are in expected heading region
    5. No gold/blue colors in before image (ensuring change, not pre-existing)
    
    Args:
        before_img: PIL Image before changes
        after_img: PIL Image after changes
        
    Returns:
        Verification result dictionary
    """
    # Convert images to RGB arrays
    before_array = np.array(before_img.convert('RGB'))
    after_array = np.array(after_img.convert('RGB'))
    
    # Ensure images are same size
    if before_array.shape != after_array.shape:
        logger.warning(f"Image size mismatch: before {before_array.shape}, after {after_array.shape}")
        # Resize after to match before
        after_img_resized = after_img.resize((before_img.width, before_img.height))
        after_array = np.array(after_img_resized.convert('RGB'))
    
    height, width = before_array.shape[:2]
    
    # Define heading region (center area, upper portion)
    # Assuming heading is in center-top area
    heading_y_start = int(height * 0.3)
    heading_y_end = int(height * 0.6)
    heading_x_start = int(width * 0.2)
    heading_x_end = int(width * 0.8)
    
    before_heading = before_array[heading_y_start:heading_y_end, heading_x_start:heading_x_end]
    after_heading = after_array[heading_y_start:heading_y_end, heading_x_start:heading_x_end]
    
    # Criterion 1: Detect substantial changes
    changes_detected, change_percentage = detect_changes(before_heading, after_heading)
    logger.info(f"✓ Change detection: {change_percentage:.1f}% of pixels changed")
    
    # Criterion 2: Detect gold/yellow background in after image
    gold_present_after, gold_percentage_after = detect_gold_color(after_heading)
    logger.info(f"✓ Gold color in after: {gold_percentage_after:.1f}% of heading region")
    
    # Criterion 3: Detect dark blue text in after image
    blue_present_after, blue_percentage_after = detect_dark_blue_color(after_heading)
    logger.info(f"✓ Dark blue color in after: {blue_percentage_after:.1f}% of heading region")
    
    # Criterion 4: Verify colors NOT present in before (ensures change, not pre-existing)
    gold_present_before, gold_percentage_before = detect_gold_color(before_heading)
    blue_present_before, blue_percentage_before = detect_dark_blue_color(before_heading)
    logger.info(f"✓ Gold in before: {gold_percentage_before:.1f}%, Blue in before: {blue_percentage_before:.1f}%")
    
    # Criterion 5: Visual quality check
    visual_quality_ok = check_visual_quality(after_heading, gold_percentage_after, blue_percentage_after)
    
    # Evaluate criteria
    criteria_results = {
        "substantial_changes": changes_detected and change_percentage >= 5.0,
        "gold_background_added": gold_present_after and gold_percentage_after >= 30.0,
        "blue_text_added": blue_present_after and blue_percentage_after >= 2.0,
        "colors_not_preexisting": gold_percentage_before < 10.0 and blue_percentage_before < 10.0,
        "visual_quality": visual_quality_ok
    }
    
    criteria_met = sum(criteria_results.values())
    score = int((criteria_met / 5.0) * 100)
    passed = score >= 70  # Need at least 3.5/5 criteria
    
    # Generate detailed feedback
    feedback_parts = []
    feedback_parts.append(f"CSS Override Verification Results: {criteria_met}/5 criteria met")
    feedback_parts.append(f"")
    feedback_parts.append(f"1. Substantial changes detected: {'✓' if criteria_results['substantial_changes'] else '✗'} ({change_percentage:.1f}% pixels changed)")
    feedback_parts.append(f"2. Gold background present: {'✓' if criteria_results['gold_background_added'] else '✗'} ({gold_percentage_after:.1f}% of region)")
    feedback_parts.append(f"3. Dark blue text present: {'✓' if criteria_results['blue_text_added'] else '✗'} ({blue_percentage_after:.1f}% of region)")
    feedback_parts.append(f"4. Colors are new (not pre-existing): {'✓' if criteria_results['colors_not_preexisting'] else '✗'}")
    feedback_parts.append(f"5. Visual quality acceptable: {'✓' if criteria_results['visual_quality'] else '✗'}")
    feedback_parts.append(f"")
    
    if passed:
        if score == 100:
            feedback_parts.append("✅ Excellent! CSS styles modified perfectly using DevTools.")
        else:
            feedback_parts.append("✅ Task completed successfully with minor issues.")
    else:
        feedback_parts.append("❌ Task incomplete - CSS styles not properly modified.")
        if not criteria_results['substantial_changes']:
            feedback_parts.append("   • No significant visual changes detected")
        if not criteria_results['gold_background_added']:
            feedback_parts.append("   • Gold background color not detected (use background-color: #FFD700)")
        if not criteria_results['blue_text_added']:
            feedback_parts.append("   • Dark blue text color not detected (use color: #1A1A4D)")
    
    feedback = "\n".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "criteria_met": criteria_met,
            "criteria_results": criteria_results,
            "change_percentage": change_percentage,
            "gold_after": gold_percentage_after,
            "blue_after": blue_percentage_after,
            "gold_before": gold_percentage_before,
            "blue_before": blue_percentage_before
        }
    }


def detect_changes(before: np.ndarray, after: np.ndarray, threshold: float = 30.0) -> Tuple[bool, float]:
    """
    Detect if substantial changes occurred between before and after.
    
    Returns:
        Tuple of (changes_detected, percentage_changed)
    """
    diff = np.abs(before.astype(np.float32) - after.astype(np.float32))
    magnitude = np.sqrt(np.sum(diff ** 2, axis=2))
    changed_pixels = np.sum(magnitude > threshold)
    total_pixels = magnitude.shape[0] * magnitude.shape[1]
    percentage = (changed_pixels / total_pixels) * 100
    
    return percentage >= 5.0, percentage


def detect_gold_color(img_region: np.ndarray) -> Tuple[bool, float]:
    """
    Detect presence of gold/yellow color (RGB ~255, 215, 0).
    
    Returns:
        Tuple of (color_present, percentage_of_region)
    """
    # Gold/yellow color range
    # R: 240-255, G: 200-230, B: 0-50
    r_mask = (img_region[:,:,0] >= 240) & (img_region[:,:,0] <= 255)
    g_mask = (img_region[:,:,1] >= 200) & (img_region[:,:,1] <= 235)
    b_mask = (img_region[:,:,2] >= 0) & (img_region[:,:,2] <= 50)
    
    gold_mask = r_mask & g_mask & b_mask
    gold_pixels = np.sum(gold_mask)
    total_pixels = img_region.shape[0] * img_region.shape[1]
    percentage = (gold_pixels / total_pixels) * 100
    
    # Also check for more lenient yellow/gold range
    r_mask_lenient = (img_region[:,:,0] >= 230)
    g_mask_lenient = (img_region[:,:,1] >= 190)
    b_mask_lenient = (img_region[:,:,2] <= 70)
    rg_diff = img_region[:,:,0].astype(np.int32) - img_region[:,:,1].astype(np.int32)
    rg_similar = np.abs(rg_diff) <= 40
    
    yellow_mask = r_mask_lenient & g_mask_lenient & b_mask_lenient & rg_similar
    yellow_pixels = np.sum(yellow_mask)
    yellow_percentage = (yellow_pixels / total_pixels) * 100
    
    # Use the higher percentage
    final_percentage = max(percentage, yellow_percentage)
    
    return final_percentage >= 30.0, final_percentage


def detect_dark_blue_color(img_region: np.ndarray) -> Tuple[bool, float]:
    """
    Detect presence of dark blue color (RGB ~26, 26, 77 or similar navy blue).
    
    Returns:
        Tuple of (color_present, percentage_of_region)
    """
    # Dark blue color range
    # R: 0-50, G: 0-50, B: 50-120
    # B should be significantly higher than R and G
    r_mask = (img_region[:,:,0] >= 0) & (img_region[:,:,0] <= 50)
    g_mask = (img_region[:,:,1] >= 0) & (img_region[:,:,1] <= 50)
    b_mask = (img_region[:,:,2] >= 50) & (img_region[:,:,2] <= 120)
    
    # Blue channel should be dominant
    b_dominant = (img_region[:,:,2] > img_region[:,:,0] + 20) & \
                 (img_region[:,:,2] > img_region[:,:,1] + 20)
    
    blue_mask = r_mask & g_mask & b_mask & b_dominant
    blue_pixels = np.sum(blue_mask)
    total_pixels = img_region.shape[0] * img_region.shape[1]
    percentage = (blue_pixels / total_pixels) * 100
    
    return percentage >= 2.0, percentage


def check_visual_quality(img_region: np.ndarray, gold_pct: float, blue_pct: float) -> bool:
    """
    Check that visual quality is acceptable (colors are balanced, not overwhelming).
    
    Returns:
        bool indicating if quality is acceptable
    """
    # Gold should be substantial (background) but not entire image
    if gold_pct < 20.0 or gold_pct > 95.0:
        return False
    
    # Blue should be present (text) but not dominant
    if blue_pct < 1.0 or blue_pct > 30.0:
        return False
    
    # Gold should be more than blue (background > text)
    if gold_pct <= blue_pct:
        return False
    
    return True


def cleanup_temp_files():
    """Clean up temporary files created during verification."""
    try:
        temp_dir = Path(tempfile.gettempdir())
        for temp_file in temp_dir.glob("tmp*.png"):
            try:
                temp_file.unlink()
            except:
                pass
    except Exception as e:
        logger.debug(f"Could not cleanup temp files: {e}")
