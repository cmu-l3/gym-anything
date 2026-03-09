#!/usr/bin/env python3
"""
Verifier for Chrome Find in Page Task: find_in_page@1
Task: Use Find in Page (Ctrl+F) to search for 'climate' and navigate through matches

Verification Strategy:
1. Analyze trajectory for Ctrl+F key press and search term typing
2. Check screenshot for find bar UI elements and yellow highlighting
3. Verify navigation through matches via Enter key presses
4. Validate that the correct page was loaded with searchable content
"""

import logging
import sys
import os
import json
import tempfile
from pathlib import Path
from typing import Dict, List, Any, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Try to import image processing libraries
try:
    from PIL import Image
    import numpy as np
    HAS_PIL = True
except ImportError:
    HAS_PIL = False
    logger.warning("PIL/numpy not available, image analysis will be limited")


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for find_in_page@1 task.
    
    Verifies:
    1. Find in Page was activated (Ctrl+F pressed)
    2. Search term 'climate' was typed
    3. Evidence of matches being found
    4. Navigation through matches occurred (Enter pressed multiple times)
    5. Visual evidence from screenshot (find bar, highlighting)
    
    Scoring:
    - 100%: All 5 criteria met (perfect execution)
    - 80-99%: 4/5 criteria met (very good, passing)
    - 60-79%: 3/5 criteria met (adequate, passing)
    - 40-59%: 2/5 criteria met (incomplete)
    - 0-39%: 0-1 criteria met (failed)
    
    Pass threshold: 70% (requires 3-4 out of 5 criteria)
    
    Args:
        traj: Trajectory data with action history
        env_info: Environment information including copy_from_env function
        task_info: Task configuration information
        
    Returns:
        Dict with 'passed', 'score', and 'feedback' keys
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available - cannot verify task"
        }

    try:
        # Expected parameters
        expected_search_term = "climate"
        
        # Initialize criteria tracking
        criteria_met = 0
        total_criteria = 5
        feedback_parts = []
        
        # Criterion 1: Check trajectory for Ctrl+F activation
        logger.info("Checking Criterion 1: Find in Page activation (Ctrl+F)...")
        find_activated = check_find_activation(traj)
        if find_activated:
            criteria_met += 1
            feedback_parts.append("✓ Criterion 1: Find in Page activated (Ctrl+F detected)")
        else:
            feedback_parts.append("✗ Criterion 1: No evidence of Ctrl+F activation")
        
        # Criterion 2: Check trajectory for search term typing
        logger.info("Checking Criterion 2: Search term entry...")
        search_term_entered = check_search_term_typed(traj, expected_search_term)
        if search_term_entered:
            criteria_met += 1
            feedback_parts.append(f"✓ Criterion 2: Search term '{expected_search_term}' typed")
        else:
            feedback_parts.append(f"✗ Criterion 2: Search term '{expected_search_term}' not detected in actions")
        
        # Criterion 3: Check for Enter key presses (navigation through matches)
        logger.info("Checking Criterion 3: Match navigation...")
        navigation_count = check_navigation_through_matches(traj)
        if navigation_count >= 2:
            criteria_met += 1
            feedback_parts.append(f"✓ Criterion 3: Navigated through matches ({navigation_count} Enter presses)")
        elif navigation_count == 1:
            criteria_met += 0.5
            feedback_parts.append(f"⚠ Criterion 3: Minimal navigation (only {navigation_count} Enter press)")
        else:
            feedback_parts.append("✗ Criterion 3: No evidence of match navigation")
        
        # Criterion 4: Check screenshot for find bar presence
        logger.info("Checking Criterion 4: Visual evidence of find bar...")
        find_bar_detected = check_find_bar_in_screenshot(copy_from_env)
        if find_bar_detected:
            criteria_met += 1
            feedback_parts.append("✓ Criterion 4: Find bar visible in screenshot")
        else:
            feedback_parts.append("✗ Criterion 4: Find bar not clearly visible in screenshot")
        
        # Criterion 5: Check screenshot for text highlighting
        logger.info("Checking Criterion 5: Visual evidence of highlighting...")
        highlighting_detected = check_text_highlighting(copy_from_env)
        if highlighting_detected:
            criteria_met += 1
            feedback_parts.append("✓ Criterion 5: Text highlighting detected in screenshot")
        else:
            feedback_parts.append("✗ Criterion 5: No clear text highlighting detected")
        
        # Calculate score
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 70
        
        # Build final feedback
        feedback = f"Find in Page Task Verification\n{'='*50}\n"
        feedback += f"Criteria met: {criteria_met}/{total_criteria}\n\n"
        feedback += "\n".join(feedback_parts)
        feedback += f"\n\n{'='*50}\n"
        feedback += f"Final Score: {score}%\n"
        feedback += f"Result: {'PASSED ✓' if passed else 'FAILED ✗'}"
        
        if not HAS_PIL:
            feedback += "\n\n⚠ Note: Image analysis libraries not available, some checks had limited functionality"
        
        logger.info(f"Verification complete: passed={passed}, score={score}, criteria={criteria_met}/{total_criteria}")
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "details": {
                "criteria_met": criteria_met,
                "total_criteria": total_criteria,
                "find_activated": find_activated,
                "search_term_entered": search_term_entered,
                "navigation_count": navigation_count,
                "find_bar_detected": find_bar_detected,
                "highlighting_detected": highlighting_detected
            }
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }


def check_find_activation(traj) -> bool:
    """
    Check if Ctrl+F was pressed in the trajectory.
    
    Args:
        traj: Trajectory data
        
    Returns:
        True if Ctrl+F was detected
    """
    if not traj:
        logger.warning("No trajectory data available")
        return False
    
    try:
        # Look for Ctrl+F key combination
        for step in traj:
            action = step.get('action', {})
            
            # Check for key action
            if action.get('type') == 'key':
                key = action.get('key', '').lower()
                modifiers = action.get('modifiers', [])
                
                # Check for 'f' key with ctrl modifier
                if key in ['f', 'F'] and ('ctrl' in modifiers or 'control' in modifiers):
                    logger.info("Found Ctrl+F key press in trajectory")
                    return True
            
            # Alternative: check for string representation
            action_str = str(action).lower()
            if 'ctrl' in action_str and 'f' in action_str:
                logger.info("Found Ctrl+F in action string")
                return True
        
        logger.warning("Ctrl+F not found in trajectory")
        return False
        
    except Exception as e:
        logger.error(f"Error checking find activation: {e}")
        return False


def check_search_term_typed(traj, search_term: str) -> bool:
    """
    Check if the search term was typed in the trajectory.
    
    Args:
        traj: Trajectory data
        search_term: Expected search term (e.g., "climate")
        
    Returns:
        True if search term was typed
    """
    if not traj:
        return False
    
    try:
        # Collect all typed text from trajectory
        typed_text = []
        
        for step in traj:
            action = step.get('action', {})
            
            # Check for type action
            if action.get('type') == 'type':
                text = action.get('text', '')
                if text:
                    typed_text.append(text.lower())
            
            # Check for individual key presses that might form the word
            if action.get('type') == 'key':
                key = action.get('key', '')
                if len(key) == 1:  # Single character
                    typed_text.append(key.lower())
        
        # Join all typed text and check for search term
        full_text = ''.join(typed_text)
        
        if search_term.lower() in full_text:
            logger.info(f"Found search term '{search_term}' in typed text")
            return True
        
        # Also check each individual typed segment
        for text in typed_text:
            if search_term.lower() in text:
                logger.info(f"Found search term '{search_term}' in typed segment")
                return True
        
        logger.warning(f"Search term '{search_term}' not found in trajectory")
        return False
        
    except Exception as e:
        logger.error(f"Error checking search term: {e}")
        return False


def check_navigation_through_matches(traj) -> int:
    """
    Check how many times Enter was pressed (indicating navigation through matches).
    
    Args:
        traj: Trajectory data
        
    Returns:
        Count of Enter key presses
    """
    if not traj:
        return 0
    
    try:
        enter_count = 0
        
        for step in traj:
            action = step.get('action', {})
            
            if action.get('type') == 'key':
                key = action.get('key', '').lower()
                
                # Check for Enter/Return key
                if key in ['enter', 'return', '\n', '\r']:
                    enter_count += 1
        
        logger.info(f"Found {enter_count} Enter key presses in trajectory")
        return enter_count
        
    except Exception as e:
        logger.error(f"Error checking navigation: {e}")
        return 0


def check_find_bar_in_screenshot(copy_from_env) -> bool:
    """
    Check if find bar is visible in the screenshot.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        True if find bar is detected
    """
    if not HAS_PIL:
        logger.warning("PIL not available, skipping screenshot analysis")
        return False
    
    temp_file = None
    try:
        # Copy screenshot from container
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        temp_file.close()
        
        # Try multiple possible screenshot locations
        screenshot_paths = [
            "/tmp/find_screenshot.png",
            "/tmp/find_page_verification/find_screenshot.png",
            "/tmp/final_screenshot.png"
        ]
        
        screenshot_copied = False
        for path in screenshot_paths:
            try:
                copy_from_env(path, temp_file.name)
                if os.path.exists(temp_file.name) and os.path.getsize(temp_file.name) > 0:
                    screenshot_copied = True
                    logger.info(f"Successfully copied screenshot from {path}")
                    break
            except Exception as e:
                logger.debug(f"Could not copy from {path}: {e}")
                continue
        
        if not screenshot_copied:
            logger.warning("Could not copy screenshot from container")
            return False
        
        # Open and analyze image
        img = Image.open(temp_file.name)
        img_array = np.array(img.convert('RGB'))
        
        height, width, _ = img_array.shape
        
        # Find bar typically appears in top-right corner
        # Check region: top-right 400x100 pixels
        if width > 400 and height > 100:
            top_right_region = img_array[0:100, width-400:width]
            
            # Find bar has characteristic appearance:
            # - White or light gray background
            # - Usually has input field and buttons
            # - Appears as a distinct UI element at top-right
            
            # Check for light colored region (find bar background)
            avg_brightness = np.mean(top_right_region)
            
            # Find bar area is typically bright (200-255 range)
            if avg_brightness > 180:
                logger.info(f"Detected bright region in top-right (avg brightness: {avg_brightness:.1f})")
                
                # Additional check: look for vertical edges (find bar borders)
                # Calculate horizontal gradient
                gray_region = np.mean(top_right_region, axis=2)
                horizontal_diff = np.abs(np.diff(gray_region, axis=1))
                edge_strength = np.mean(horizontal_diff)
                
                if edge_strength > 5:
                    logger.info(f"Detected UI edges in top-right region (edge strength: {edge_strength:.1f})")
                    return True
        
        logger.warning("Find bar not clearly detected in screenshot")
        return False
        
    except Exception as e:
        logger.error(f"Error checking find bar: {e}")
        return False
    finally:
        if temp_file and os.path.exists(temp_file.name):
            try:
                os.unlink(temp_file.name)
            except:
                pass


def check_text_highlighting(copy_from_env) -> bool:
    """
    Check if yellow/orange text highlighting is present in screenshot.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        True if highlighting is detected
    """
    if not HAS_PIL:
        logger.warning("PIL not available, skipping highlighting detection")
        return False
    
    temp_file = None
    try:
        # Copy screenshot
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        temp_file.close()
        
        screenshot_paths = [
            "/tmp/find_screenshot.png",
            "/tmp/find_page_verification/find_screenshot.png",
            "/tmp/final_screenshot.png"
        ]
        
        screenshot_copied = False
        for path in screenshot_paths:
            try:
                copy_from_env(path, temp_file.name)
                if os.path.exists(temp_file.name) and os.path.getsize(temp_file.name) > 0:
                    screenshot_copied = True
                    break
            except Exception as e:
                logger.debug(f"Could not copy from {path}: {e}")
                continue
        
        if not screenshot_copied:
            return False
        
        # Open and analyze image
        img = Image.open(temp_file.name)
        img_array = np.array(img.convert('RGB'))
        
        # Chrome's find highlights are yellow (approximately RGB: 255, 255, 0)
        # or orange for current match (approximately RGB: 255, 150, 50)
        # Look for pixels with high R and G, low B
        
        r_channel = img_array[:, :, 0]
        g_channel = img_array[:, :, 1]
        b_channel = img_array[:, :, 2]
        
        # Yellow highlights: R > 200, G > 200, B < 120
        yellow_mask = (r_channel > 200) & (g_channel > 200) & (b_channel < 120)
        yellow_pixels = np.sum(yellow_mask)
        
        # Orange highlights: R > 200, G > 120, B < 100
        orange_mask = (r_channel > 200) & (g_channel > 120) & (b_channel < 100)
        orange_pixels = np.sum(orange_mask)
        
        total_highlight_pixels = yellow_pixels + orange_pixels
        
        logger.info(f"Detected {yellow_pixels} yellow pixels and {orange_pixels} orange pixels")
        
        # If we have a significant number of yellow/orange pixels, highlighting is present
        # Threshold: at least 500 pixels (reasonable for multiple highlighted words)
        if total_highlight_pixels > 500:
            logger.info(f"Text highlighting detected ({total_highlight_pixels} highlight pixels)")
            return True
        
        logger.warning(f"Insufficient highlighting detected ({total_highlight_pixels} pixels)")
        return False
        
    except Exception as e:
        logger.error(f"Error checking highlighting: {e}")
        return False
    finally:
        if temp_file and os.path.exists(temp_file.name):
            try:
                os.unlink(temp_file.name)
            except:
                pass
