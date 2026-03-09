#!/usr/bin/env python3
"""
Verifier for Chrome Developer Tools Element Inspection Task
Task: Use DevTools to inspect button and change background color to green

Verification Strategy:
1. Screenshot analysis - detect green button in image (primary, most robust)
2. CDP computed style check - if available from export script
3. Visual verification - ensure button region contains green color
4. Color accuracy - green should be close to target #28a745 = RGB(40, 167, 69)
"""

import logging
import sys
import os
import json
import tempfile
import re
from pathlib import Path

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Try to import image processing libraries
try:
    from PIL import Image
    import numpy as np
    HAS_PIL = True
except ImportError:
    HAS_PIL = False
    logger.warning("PIL/Pillow not available, screenshot analysis will be limited")


def verify_task(traj, env_info, task_info):
    """
    Main verification function for inspect_and_modify_dom@1 task.
    
    Verifies that the agent successfully:
    1. Opened Chrome Developer Tools
    2. Inspected the button element
    3. Modified background-color from blue to green (#28a745)
    
    Args:
        traj: Trajectory data (not used for this verification)
        env_info: Environment information including copy_from_env function
        task_info: Task configuration information
        
    Returns:
        Dict with passed (bool), score (int 0-100), and feedback (str)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "copy_from_env function not available in environment"
        }
    
    try:
        # Criterion 1: Screenshot shows green button (primary verification)
        screenshot_result = verify_screenshot_green_button(copy_from_env)
        
        # Criterion 2: CDP computed style verification (if available)
        cdp_result = verify_cdp_button_color(copy_from_env)
        
        # Criterion 3: Page URL verification (should still be on test page)
        url_result = verify_page_url(copy_from_env)
        
        # Calculate overall score and feedback
        final_result = calculate_final_score(screenshot_result, cdp_result, url_result)
        
        return final_result
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }


def verify_screenshot_green_button(copy_from_env):
    """
    Verify that screenshot shows a green button.
    
    Strategy:
    - Analyze screenshot for presence of green color matching target #28a745
    - Target green: RGB(40, 167, 69)
    - Look for sufficient green pixels that form a button-sized region
    
    Returns:
        Dict with passed, score, feedback, and details
    """
    if not HAS_PIL:
        return {
            "passed": False,
            "score": 0,
            "feedback": "PIL library not available for screenshot analysis",
            "details": {"method": "screenshot", "available": False}
        }
    
    temp_file = None
    try:
        # Copy screenshot from container
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        temp_file.close()
        
        screenshot_paths = [
            "/tmp/devtools_verification/final_screenshot.png",
            "/tmp/final_screenshot.png"
        ]
        
        screenshot_copied = False
        for path in screenshot_paths:
            try:
                logger.info(f"Trying to copy screenshot from: {path}")
                copy_from_env(path, temp_file.name)
                if os.path.exists(temp_file.name) and os.path.getsize(temp_file.name) > 0:
                    screenshot_copied = True
                    logger.info(f"✓ Screenshot copied from: {path}")
                    break
            except Exception as e:
                logger.debug(f"Failed to copy from {path}: {e}")
        
        if not screenshot_copied:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Could not copy screenshot from container",
                "details": {"method": "screenshot", "error": "copy_failed"}
            }
        
        # Analyze screenshot for green button
        img = Image.open(temp_file.name)
        img_array = np.array(img.convert('RGB'))
        
        # Target green color: #28a745 = RGB(40, 167, 69)
        target_green = np.array([40, 167, 69])
        
        # Define tolerance for color matching (allow some variation)
        tolerance = 25
        
        # Find pixels that match green color within tolerance
        # Calculate Euclidean distance in RGB space
        diff = np.abs(img_array - target_green)
        green_mask = np.all(diff < tolerance, axis=2)
        green_pixel_count = np.sum(green_mask)
        
        total_pixels = img_array.shape[0] * img_array.shape[1]
        green_percentage = (green_pixel_count / total_pixels) * 100
        
        logger.info(f"Green pixel analysis:")
        logger.info(f"  Total pixels: {total_pixels}")
        logger.info(f"  Green pixels: {green_pixel_count}")
        logger.info(f"  Green percentage: {green_percentage:.2f}%")
        
        # Button should occupy at least 1000 pixels (reasonable button size)
        # This is roughly 50x20 pixels which is a small button
        min_button_pixels = 1000
        
        # Also check for broader green range (in case color is slightly off)
        broad_green_mask = (img_array[:,:,1] > img_array[:,:,0] + 20) & \
                          (img_array[:,:,1] > img_array[:,:,2] + 20) & \
                          (img_array[:,:,1] > 100)
        broad_green_count = np.sum(broad_green_mask)
        
        logger.info(f"  Broad green pixels (G > R+20, G > B+20, G > 100): {broad_green_count}")
        
        # Check if original blue button is still visible (failure case)
        blue_color = np.array([0, 123, 255])  # #007bff
        blue_diff = np.abs(img_array - blue_color)
        blue_mask = np.all(blue_diff < tolerance, axis=2)
        blue_pixel_count = np.sum(blue_mask)
        
        logger.info(f"  Blue pixels (original color): {blue_pixel_count}")
        
        # Scoring logic
        if green_pixel_count >= min_button_pixels:
            # Excellent - exact green color detected
            score = 100
            feedback = f"✓ Screenshot shows green button ({green_pixel_count} green pixels detected, target color #28a745)"
            passed = True
        elif broad_green_count >= min_button_pixels:
            # Good - greenish color detected
            score = 85
            feedback = f"✓ Screenshot shows greenish button ({broad_green_count} green-ish pixels), color may be slightly off from target #28a745"
            passed = True
        elif blue_pixel_count >= min_button_pixels:
            # Failure - button is still blue
            score = 0
            feedback = f"✗ Button still appears blue in screenshot ({blue_pixel_count} blue pixels detected)"
            passed = False
        else:
            # Unclear - not enough evidence
            score = 25
            feedback = f"⚠ Insufficient green color detected in screenshot (only {green_pixel_count} pixels)"
            passed = False
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "details": {
                "method": "screenshot",
                "green_pixels": int(green_pixel_count),
                "broad_green_pixels": int(broad_green_count),
                "blue_pixels": int(blue_pixel_count),
                "green_percentage": float(green_percentage)
            }
        }
        
    except Exception as e:
        logger.error(f"Screenshot analysis error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Screenshot analysis failed: {str(e)}",
            "details": {"method": "screenshot", "error": str(e)}
        }
    finally:
        if temp_file and os.path.exists(temp_file.name):
            try:
                os.unlink(temp_file.name)
            except:
                pass


def verify_cdp_button_color(copy_from_env):
    """
    Verify button color via CDP computed style (if available).
    
    Returns:
        Dict with passed, score, feedback, and details
    """
    temp_file = None
    try:
        # Try to get CDP captured button color
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.txt', mode='w+')
        temp_file.close()
        
        cdp_paths = [
            "/tmp/devtools_verification/button_computed_color.txt",
            "/tmp/button_computed_color.txt"
        ]
        
        color_value = None
        for path in cdp_paths:
            try:
                copy_from_env(path, temp_file.name)
                with open(temp_file.name, 'r') as f:
                    color_value = f.read().strip()
                if color_value:
                    break
            except Exception as e:
                logger.debug(f"Failed to copy CDP color from {path}: {e}")
        
        if not color_value or color_value in ['cdp-unavailable', 'cdp-failed', 'cdp-script-failed', 'button-not-found']:
            return {
                "passed": None,  # Neutral - CDP not available
                "score": 0,
                "feedback": "⚠ CDP computed style not available (library missing or script failed)",
                "details": {"method": "cdp", "available": False, "value": color_value}
            }
        
        logger.info(f"CDP button color: {color_value}")
        
        # Parse color value
        # Expected formats: "rgb(40, 167, 69)" or "rgba(40, 167, 69, 1)"
        rgb_match = re.search(r'rgba?\s*\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)', color_value)
        
        if rgb_match:
            r, g, b = int(rgb_match.group(1)), int(rgb_match.group(2)), int(rgb_match.group(3))
            logger.info(f"Parsed RGB: ({r}, {g}, {b})")
            
            # Target green: RGB(40, 167, 69)
            target = (40, 167, 69)
            tolerance = 25
            
            # Check if close to target
            color_match = all(abs(actual - expected) < tolerance for actual, expected in zip((r, g, b), target))
            
            if color_match:
                return {
                    "passed": True,
                    "score": 100,
                    "feedback": f"✓ CDP confirms green button (computed style: rgb({r}, {g}, {b}))",
                    "details": {"method": "cdp", "rgb": (r, g, b), "matches_target": True}
                }
            else:
                return {
                    "passed": False,
                    "score": 0,
                    "feedback": f"✗ CDP shows wrong color (rgb({r}, {g}, {b}), expected ~rgb(40, 167, 69))",
                    "details": {"method": "cdp", "rgb": (r, g, b), "matches_target": False}
                }
        else:
            return {
                "passed": None,
                "score": 0,
                "feedback": f"⚠ CDP color value could not be parsed: {color_value}",
                "details": {"method": "cdp", "parse_error": True, "value": color_value}
            }
        
    except Exception as e:
        logger.error(f"CDP verification error: {e}", exc_info=True)
        return {
            "passed": None,
            "score": 0,
            "feedback": f"⚠ CDP verification error: {str(e)}",
            "details": {"method": "cdp", "error": str(e)}
        }
    finally:
        if temp_file and os.path.exists(temp_file.name):
            try:
                os.unlink(temp_file.name)
            except:
                pass


def verify_page_url(copy_from_env):
    """
    Verify that Chrome is still on the test page.
    
    Returns:
        Dict with passed, score, feedback, and details
    """
    temp_file = None
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.txt', mode='w+')
        temp_file.close()
        
        url_paths = [
            "/tmp/devtools_verification/active_url.txt",
            "/tmp/active_url.txt"
        ]
        
        url_value = None
        for path in url_paths:
            try:
                copy_from_env(path, temp_file.name)
                with open(temp_file.name, 'r') as f:
                    url_value = f.read().strip()
                if url_value:
                    break
            except Exception as e:
                logger.debug(f"Failed to copy URL from {path}: {e}")
        
        if not url_value:
            return {
                "passed": None,
                "score": 0,
                "feedback": "⚠ Could not verify page URL",
                "details": {"method": "url_check", "available": False}
            }
        
        logger.info(f"Active page URL: {url_value}")
        
        # Check if on test page (file:///tmp/devtools_test_page.html)
        is_test_page = "devtools_test_page.html" in url_value or url_value.startswith("file:///tmp/")
        
        if is_test_page:
            return {
                "passed": True,
                "score": 10,
                "feedback": f"✓ On test page: {url_value}",
                "details": {"method": "url_check", "url": url_value, "correct_page": True}
            }
        else:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"⚠ Not on test page (current: {url_value})",
                "details": {"method": "url_check", "url": url_value, "correct_page": False}
            }
        
    except Exception as e:
        logger.error(f"URL verification error: {e}", exc_info=True)
        return {
            "passed": None,
            "score": 0,
            "feedback": "⚠ URL verification error",
            "details": {"method": "url_check", "error": str(e)}
        }
    finally:
        if temp_file and os.path.exists(temp_file.name):
            try:
                os.unlink(temp_file.name)
            except:
                pass


def calculate_final_score(screenshot_result, cdp_result, url_result):
    """
    Calculate final score and feedback from all verification methods.
    
    Scoring weights:
    - Screenshot: 70% (primary, most reliable)
    - CDP: 20% (secondary, may not be available)
    - URL: 10% (tertiary, just confirming context)
    
    Pass threshold: 75% (needs at least screenshot verification to pass)
    """
    total_score = 0
    max_score = 100
    feedback_parts = []
    
    # Screenshot verification (70% weight)
    screenshot_passed = screenshot_result.get("passed", False)
    screenshot_score = screenshot_result.get("score", 0)
    screenshot_feedback = screenshot_result.get("feedback", "")
    
    weighted_screenshot = (screenshot_score / 100) * 70
    total_score += weighted_screenshot
    feedback_parts.append(f"Screenshot Analysis (70%): {screenshot_feedback}")
    
    # CDP verification (20% weight) - optional
    cdp_passed = cdp_result.get("passed", None)
    cdp_score = cdp_result.get("score", 0)
    cdp_feedback = cdp_result.get("feedback", "")
    
    if cdp_passed is True:
        weighted_cdp = (cdp_score / 100) * 20
        total_score += weighted_cdp
    elif cdp_passed is False:
        # CDP says it's wrong - penalize
        total_score -= 10
    # If cdp_passed is None (unavailable), no change to score
    
    feedback_parts.append(f"CDP Verification (20%): {cdp_feedback}")
    
    # URL verification (10% weight) - optional
    url_passed = url_result.get("passed", None)
    url_score = url_result.get("score", 0)
    url_feedback = url_result.get("feedback", "")
    
    if url_passed is True:
        weighted_url = (url_score / 100) * 10
        total_score += weighted_url
    
    feedback_parts.append(f"Page URL Check (10%): {url_feedback}")
    
    # Ensure score is in valid range
    final_score = max(0, min(100, int(total_score)))
    passed = final_score >= 75
    
    # Build final feedback
    feedback_parts.append("")
    feedback_parts.append("="*60)
    feedback_parts.append(f"Final Score: {final_score}/100")
    feedback_parts.append(f"Result: {'✅ PASSED' if passed else '❌ FAILED'}")
    
    if passed:
        feedback_parts.append("")
        feedback_parts.append("Task completed successfully! The button background color")
        feedback_parts.append("was changed from blue to green using Chrome DevTools.")
    else:
        feedback_parts.append("")
        feedback_parts.append("Task incomplete. The button should be green (#28a745).")
        if not screenshot_passed:
            feedback_parts.append("Screenshot does not show sufficient green color.")
    
    feedback = "\n".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": final_score,
        "feedback": feedback,
        "details": {
            "screenshot": screenshot_result.get("details", {}),
            "cdp": cdp_result.get("details", {}),
            "url": url_result.get("details", {})
        }
    }
