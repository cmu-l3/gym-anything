#!/usr/bin/env python3
"""
Verifier for Chrome Bookmarklet Creation and Execution Task
Task: Create a bookmarklet that changes page background to red and execute it

Verification Strategy:
1. Parse Chrome Bookmarks JSON for javascript: URLs
2. Verify bookmarklet contains correct code pattern (backgroundColor, #FF0000)
3. Verify bookmarklet has descriptive name (contains "red" or "background")
4. Analyze screenshot for red background pixels
5. Validate execution success through visual confirmation

Scoring:
- 100%: All 5 criteria met (bookmarklet created, correct code, good name, executed, visual confirmation)
- 80%: 4/5 criteria met
- 60%: 3/5 criteria met
- <60%: Task failed

Pass threshold: 80% (4 out of 5 criteria)
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
    HAS_IMAGE_LIBS = True
except ImportError:
    HAS_IMAGE_LIBS = False
    logger.warning("PIL/numpy not available, visual verification will be limited")

# Add utils to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '../../../', 'utils'))
try:
    from chrome_verification_utils import cleanup_verification_temp
except ImportError:
    logger.warning("Chrome verification utilities not available, using fallback")
    def cleanup_verification_temp():
        pass


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for bookmarklet_create_execute@1 task.
    
    Verifies:
    1. Bookmarklet created in Chrome bookmarks
    2. Bookmarklet contains correct JavaScript code pattern
    3. Bookmarklet has appropriate name
    4. Bookmarklet was executed (optional via visual)
    5. Visual confirmation of red background
    
    Args:
        traj: Trajectory data (not used)
        env_info: Environment information including copy_from_env function
        task_info: Task configuration information
        
    Returns:
        Dict with passed, score, and feedback
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "copy_from_env function not available"
        }
    
    criteria_met = {
        'bookmarklet_created': False,
        'correct_code_pattern': False,
        'proper_naming': False,
        'visual_confirmation': False,
        'no_errors': True
    }
    
    feedback_parts = []
    
    try:
        # Criterion 1 & 2 & 3: Check bookmarks file for javascript: URL with correct code
        logger.info("Checking bookmarks file for bookmarklet...")
        bookmarklet_data = check_bookmarklet_in_bookmarks(copy_from_env)
        
        if bookmarklet_data['found']:
            criteria_met['bookmarklet_created'] = True
            feedback_parts.append(f"✓ Bookmarklet created: {bookmarklet_data['name']}")
            
            if bookmarklet_data['correct_code']:
                criteria_met['correct_code_pattern'] = True
                feedback_parts.append(f"✓ Correct code pattern detected (backgroundColor with red color)")
            else:
                feedback_parts.append(f"✗ Code pattern incorrect or incomplete")
            
            if bookmarklet_data['good_name']:
                criteria_met['proper_naming'] = True
                feedback_parts.append(f"✓ Good descriptive name: '{bookmarklet_data['name']}'")
            else:
                feedback_parts.append(f"⚠ Name could be more descriptive: '{bookmarklet_data['name']}'")
        else:
            feedback_parts.append(f"✗ No bookmarklet found in bookmarks")
            feedback_parts.append(f"  Expected: javascript: URL with backgroundColor code")
        
        # Criterion 4: Visual confirmation via screenshot analysis
        logger.info("Checking visual confirmation...")
        visual_result = check_visual_confirmation(copy_from_env)
        
        if visual_result['confirmed']:
            criteria_met['visual_confirmation'] = True
            feedback_parts.append(f"✓ Visual confirmation: {visual_result['feedback']}")
        else:
            feedback_parts.append(f"✗ Visual confirmation failed: {visual_result['feedback']}")
        
        # Calculate score
        total_criteria = 5
        met_count = sum(criteria_met.values())
        score = int((met_count / total_criteria) * 100)
        passed = score >= 80  # Need 4/5 criteria
        
        # Build final feedback
        feedback = "\n".join(feedback_parts)
        feedback += f"\n\n{'='*60}"
        feedback += f"\nCriteria met: {met_count}/{total_criteria}"
        feedback += f"\nScore: {score}%"
        feedback += f"\nResult: {'✅ PASSED' if passed else '❌ FAILED'}"
        
        if not HAS_IMAGE_LIBS:
            feedback += "\n\n⚠ Note: Image analysis libraries not available, visual verification limited"
        
        logger.info(f"Verification complete: passed={passed}, score={score}")
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "criteria": criteria_met
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }


def check_bookmarklet_in_bookmarks(copy_from_env) -> Dict[str, Any]:
    """
    Check Chrome bookmarks for javascript: bookmarklet.
    
    Returns:
        Dict with found, name, correct_code, good_name fields
    """
    result = {
        'found': False,
        'name': '',
        'url': '',
        'correct_code': False,
        'good_name': False
    }
    
    temp_file = None
    try:
        # Copy bookmarks file
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json', mode='w+')
        temp_file.close()
        
        # Try multiple possible locations
        locations = [
            "/tmp/bookmarklet_verification/bookmarks.json",
            "/tmp/bookmarks.json",
            "/home/ga/.config/google-chrome-cdp/Default/Bookmarks",
            "/home/ga/.config/google-chrome/Default/Bookmarks"
        ]
        
        bookmarks_data = None
        for location in locations:
            try:
                logger.info(f"Trying to copy bookmarks from: {location}")
                copy_from_env(location, temp_file.name)
                
                if os.path.exists(temp_file.name) and os.path.getsize(temp_file.name) > 0:
                    with open(temp_file.name, 'r', encoding='utf-8') as f:
                        bookmarks_data = json.load(f)
                    logger.info(f"✓ Successfully loaded bookmarks from: {location}")
                    break
            except Exception as e:
                logger.debug(f"Failed to copy from {location}: {e}")
                continue
        
        if not bookmarks_data:
            logger.warning("Could not load bookmarks from any location")
            return result
        
        # Search for javascript: bookmarks recursively
        javascript_bookmarks = find_javascript_bookmarks(bookmarks_data)
        
        if not javascript_bookmarks:
            logger.info("No javascript: bookmarks found")
            return result
        
        # Find the most relevant bookmarklet (containing backgroundColor and red)
        for bm in javascript_bookmarks:
            url = bm.get('url', '')
            name = bm.get('name', '')
            
            # Check if this is our red background bookmarklet
            url_lower = url.lower()
            if 'backgroundcolor' in url_lower or 'background-color' in url_lower:
                result['found'] = True
                result['name'] = name
                result['url'] = url
                
                # Check for correct code pattern
                if any(red in url_lower for red in ['#ff0000', '#f00', 'red', 'rgb(255,0,0)', 'rgb(255, 0, 0)']):
                    result['correct_code'] = True
                
                # Check for good naming
                name_lower = name.lower()
                if any(kw in name_lower for kw in ['red', 'background', 'color']):
                    result['good_name'] = True
                
                logger.info(f"Found bookmarklet: {name} | {url[:80]}...")
                break
        
        return result
        
    except Exception as e:
        logger.error(f"Error checking bookmarks: {e}", exc_info=True)
        return result
    finally:
        if temp_file and os.path.exists(temp_file.name):
            try:
                os.unlink(temp_file.name)
            except:
                pass


def find_javascript_bookmarks(bookmarks_data: Dict) -> List[Dict]:
    """
    Recursively search for javascript: bookmarks in bookmarks tree.
    
    Args:
        bookmarks_data: Parsed bookmarks JSON
        
    Returns:
        List of bookmark dictionaries with javascript: URLs
    """
    results = []
    
    def traverse(node):
        if isinstance(node, dict):
            # Check if this is a javascript: bookmark
            if node.get('type') == 'url':
                url = node.get('url', '')
                if url.startswith('javascript:'):
                    results.append(node)
            
            # Recurse into children
            if 'children' in node:
                for child in node['children']:
                    traverse(child)
            
            # Recurse into other dict values
            for value in node.values():
                if isinstance(value, (dict, list)):
                    traverse(value)
        
        elif isinstance(node, list):
            for item in node:
                traverse(item)
    
    traverse(bookmarks_data)
    return results


def check_visual_confirmation(copy_from_env) -> Dict[str, Any]:
    """
    Check screenshot for red background pixels.
    
    Returns:
        Dict with confirmed (bool) and feedback (str)
    """
    if not HAS_IMAGE_LIBS:
        return {
            'confirmed': False,
            'feedback': "Image analysis libraries not available"
        }
    
    temp_file = None
    try:
        # Copy screenshot
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        temp_file.close()
        
        locations = [
            "/tmp/bookmarklet_verification/page_screenshot.png",
            "/tmp/page_screenshot.png",
            "/tmp/final_screenshot.png"
        ]
        
        screenshot_loaded = False
        for location in locations:
            try:
                logger.info(f"Trying to copy screenshot from: {location}")
                copy_from_env(location, temp_file.name)
                
                if os.path.exists(temp_file.name) and os.path.getsize(temp_file.name) > 100:
                    screenshot_loaded = True
                    logger.info(f"✓ Screenshot loaded from: {location}")
                    break
            except Exception as e:
                logger.debug(f"Failed to copy from {location}: {e}")
                continue
        
        if not screenshot_loaded:
            return {
                'confirmed': False,
                'feedback': "Could not load screenshot"
            }
        
        # Analyze screenshot for red pixels
        red_percentage = analyze_red_coverage(temp_file.name)
        
        logger.info(f"Red pixel coverage: {red_percentage:.1%}")
        
        # Consider confirmed if >50% of image is bright red
        if red_percentage >= 0.50:
            return {
                'confirmed': True,
                'feedback': f"Page background is red ({red_percentage:.1%} coverage)"
            }
        elif red_percentage >= 0.30:
            return {
                'confirmed': True,
                'feedback': f"Partial red background detected ({red_percentage:.1%} coverage)"
            }
        else:
            return {
                'confirmed': False,
                'feedback': f"Insufficient red background ({red_percentage:.1%} coverage, need >50%)"
            }
        
    except Exception as e:
        logger.error(f"Error in visual confirmation: {e}", exc_info=True)
        return {
            'confirmed': False,
            'feedback': f"Visual analysis error: {str(e)}"
        }
    finally:
        if temp_file and os.path.exists(temp_file.name):
            try:
                os.unlink(temp_file.name)
            except:
                pass


def analyze_red_coverage(screenshot_path: str) -> float:
    """
    Calculate percentage of image that is bright red.
    
    Args:
        screenshot_path: Path to screenshot PNG
        
    Returns:
        Float between 0 and 1 representing red pixel percentage
    """
    try:
        img = Image.open(screenshot_path).convert('RGB')
        img_array = np.array(img)
        
        # Define red threshold
        # Red channel high (>240), Green channel low (<30), Blue channel low (<30)
        red_mask = (
            (img_array[:,:,0] >= 240) &  # Red channel
            (img_array[:,:,1] <= 30) &    # Green channel
            (img_array[:,:,2] <= 30)      # Blue channel
        )
        
        red_pixel_count = np.sum(red_mask)
        total_pixels = img_array.shape[0] * img_array.shape[1]
        
        return red_pixel_count / total_pixels
        
    except Exception as e:
        logger.error(f"Error analyzing red coverage: {e}")
        return 0.0
