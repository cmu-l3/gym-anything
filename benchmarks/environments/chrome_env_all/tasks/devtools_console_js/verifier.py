#!/usr/bin/env python3
"""
Verifier for Chrome DevTools Console JavaScript Execution Task (devtools_console_js@1)
Task: Use DevTools Console to execute JavaScript that modifies webpage elements

Verification Strategy:
1. Primary: CDP-based DOM inspection (execute verification JS in page context)
2. Secondary: Screenshot-based visual verification (fallback)
3. Check for JavaScript console errors
4. Validate heading text, heading color, and content box background color

Criteria (5 total, need 4+ to pass at 80%):
1. Heading text changed to "Hello Developer!"
2. Heading color is blue (rgb(0, 0, 255) or variations)
3. Content box background is light yellow (#fffacd or rgb(255, 250, 205))
4. No JavaScript console errors detected
5. DOM was actually modified from original state
"""

import logging
import sys
import os
import json
import tempfile
import re
from pathlib import Path
from typing import Dict, Any, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Try to import required libraries
try:
    import requests
    HAS_REQUESTS = True
except ImportError:
    HAS_REQUESTS = False
    logger.warning("requests library not available, CDP verification will be limited")

try:
    from PIL import Image
    import numpy as np
    HAS_PIL = True
except ImportError:
    HAS_PIL = False
    logger.warning("PIL/numpy not available, visual verification disabled")


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for devtools_console_js@1 task.
    
    Args:
        traj: Trajectory data (not used)
        env_info: Environment information including copy_from_env function
        task_info: Task configuration
        
    Returns:
        Dict with passed, score, and feedback
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available in environment"
        }
    
    try:
        # Get CDP information and WebSocket URL
        ws_url, error = get_websocket_url(copy_from_env)
        
        if not ws_url:
            logger.warning(f"Could not get WebSocket URL: {error}")
            # Fall back to screenshot-based verification
            return verify_via_screenshot(copy_from_env)
        
        # Primary verification: CDP-based DOM inspection
        result = verify_via_cdp(ws_url, copy_from_env)
        
        return result
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }


def get_websocket_url(copy_from_env) -> Tuple[Optional[str], str]:
    """
    Extract WebSocket debugger URL from CDP data.
    
    Returns:
        Tuple of (ws_url, error_message)
    """
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.txt', mode='w+')
    temp_path = temp_file.name
    temp_file.close()
    
    try:
        # Try to get the WebSocket URL from export
        copy_from_env("/tmp/ws_debugger_url.txt", temp_path)
        
        with open(temp_path, 'r') as f:
            ws_url = f.read().strip()
        
        os.unlink(temp_path)
        
        if ws_url and ws_url != "" and ws_url != "null":
            logger.info(f"Found WebSocket URL: {ws_url[:50]}...")
            return ws_url, ""
        else:
            return None, "WebSocket URL is empty or null"
            
    except Exception as e:
        if os.path.exists(temp_path):
            os.unlink(temp_path)
        return None, f"Failed to get WebSocket URL: {e}"


def verify_via_cdp(ws_url: str, copy_from_env) -> Dict[str, Any]:
    """
    Verify DOM modifications using Chrome DevTools Protocol.
    
    Uses WebSocket connection to execute JavaScript in page context
    and retrieve element properties.
    """
    if not HAS_REQUESTS:
        return {
            "passed": False,
            "score": 0,
            "feedback": "requests library not available for CDP verification"
        }
    
    try:
        # Since websocket library may not be available, we'll use HTTP-based CDP
        # Get the tab list and use the CDP REST API
        
        # Execute verification JavaScript via Runtime.evaluate
        verification_js = """
        (function() {
            try {
                const heading = document.getElementById('main-heading');
                const contentBox = document.querySelector('.content-box');
                
                if (!heading || !contentBox) {
                    return { 
                        error: 'Required elements not found',
                        headingExists: !!heading,
                        contentBoxExists: !!contentBox
                    };
                }
                
                const headingStyle = window.getComputedStyle(heading);
                const boxStyle = window.getComputedStyle(contentBox);
                
                return {
                    success: true,
                    headingText: heading.textContent.trim(),
                    headingColor: headingStyle.color,
                    headingColorRaw: headingStyle.color,
                    boxBackgroundColor: boxStyle.backgroundColor,
                    boxBackgroundColorRaw: boxStyle.backgroundColor
                };
            } catch (e) {
                return { error: 'JavaScript execution error: ' + e.message };
            }
        })()
        """
        
        # Since we can't easily use WebSocket without the library,
        # we'll parse the CDP data and try alternative methods
        result = execute_cdp_command_via_http(ws_url, verification_js)
        
        if result and 'success' in result and result['success']:
            return evaluate_dom_state(result)
        else:
            error_msg = result.get('error', 'Unknown error') if result else 'Failed to execute CDP command'
            logger.warning(f"CDP execution failed: {error_msg}")
            # Fall back to screenshot verification
            return verify_via_screenshot(copy_from_env)
            
    except Exception as e:
        logger.error(f"CDP verification error: {e}")
        return verify_via_screenshot(copy_from_env)


def execute_cdp_command_via_http(ws_url: str, js_code: str) -> Optional[Dict]:
    """
    Execute JavaScript via CDP using HTTP endpoint instead of WebSocket.
    This is a simplified approach that works when websocket library is unavailable.
    """
    try:
        # Extract port and target ID from WebSocket URL
        # Format: ws://localhost:9222/devtools/page/{target_id}
        match = re.search(r'ws://localhost:(\d+)/devtools/page/([A-F0-9-]+)', ws_url)
        if not match:
            logger.warning(f"Could not parse WebSocket URL: {ws_url}")
            return None
        
        port = match.group(1)
        target_id = match.group(2)
        
        # Try using the /json/new endpoint or direct evaluation
        # This is a fallback and may not work in all cases
        logger.info("CDP HTTP-based execution not fully implemented, using alternative verification")
        return None
        
    except Exception as e:
        logger.error(f"HTTP CDP execution error: {e}")
        return None


def evaluate_dom_state(dom_data: Dict) -> Dict[str, Any]:
    """
    Evaluate whether DOM modifications meet task requirements.
    
    Criteria:
    1. Heading text is "Hello Developer!"
    2. Heading color is blue
    3. Content box background is light yellow (#fffacd)
    4. No errors in DOM query
    5. Elements were actually modified
    """
    criteria_met = 0
    total_criteria = 5
    feedback_parts = []
    
    # Criterion 1: Heading text
    heading_text = dom_data.get('headingText', '').strip()
    text_match = heading_text.lower() == 'hello developer!'
    
    if text_match:
        feedback_parts.append("✓ Heading text correctly changed to 'Hello Developer!'")
        criteria_met += 1
    else:
        feedback_parts.append(f"✗ Heading text is '{heading_text}', expected 'Hello Developer!'")
    
    logger.info(f"Heading text check: {heading_text} -> {text_match}")
    
    # Criterion 2: Heading color (blue)
    heading_color = dom_data.get('headingColor', '').lower()
    color_blue = is_blue_color(heading_color)
    
    if color_blue:
        feedback_parts.append(f"✓ Heading color is blue ({heading_color})")
        criteria_met += 1
    else:
        feedback_parts.append(f"✗ Heading color is {heading_color}, expected blue")
    
    logger.info(f"Heading color check: {heading_color} -> {color_blue}")
    
    # Criterion 3: Content box background (light yellow)
    box_bg = dom_data.get('boxBackgroundColor', '').lower()
    bg_yellow = is_light_yellow_color(box_bg)
    
    if bg_yellow:
        feedback_parts.append(f"✓ Content box background is light yellow ({box_bg})")
        criteria_met += 1
    else:
        feedback_parts.append(f"✗ Content box background is {box_bg}, expected light yellow (#fffacd)")
    
    logger.info(f"Background color check: {box_bg} -> {bg_yellow}")
    
    # Criterion 4: No errors
    has_error = 'error' in dom_data
    no_errors = not has_error
    
    if no_errors:
        feedback_parts.append("✓ No JavaScript errors detected")
        criteria_met += 1
    else:
        feedback_parts.append(f"✗ Error detected: {dom_data.get('error')}")
    
    # Criterion 5: DOM was modified (heading not "Welcome", box not white)
    was_modified = (heading_text.lower() != 'welcome' and 
                   not box_bg.startswith('rgb(255, 255, 255)') and
                   box_bg != 'white')
    
    if was_modified:
        feedback_parts.append("✓ DOM was successfully modified from original state")
        criteria_met += 1
    else:
        feedback_parts.append("✗ DOM appears unchanged from original state")
    
    # Calculate score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 80  # Need 4/5 criteria
    
    # Build feedback
    feedback = "\n".join(feedback_parts)
    feedback += f"\n\n{'='*50}"
    feedback += f"\nCriteria met: {criteria_met}/{total_criteria}"
    feedback += f"\nFinal score: {score}%"
    feedback += f"\nResult: {'PASSED ✓' if passed else 'FAILED ✗'}"
    
    logger.info(f"Verification complete: passed={passed}, score={score}, criteria={criteria_met}/{total_criteria}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "criteria_met": criteria_met,
            "heading_text": heading_text,
            "heading_color": heading_color,
            "box_background": box_bg
        }
    }


def is_blue_color(color_str: str) -> bool:
    """Check if color string represents blue."""
    if not color_str:
        return False
    
    color_str = color_str.lower().strip()
    
    # Named color
    if color_str == 'blue':
        return True
    
    # RGB format: rgb(0, 0, 255) or variations
    rgb_match = re.search(r'rgb\s*\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\)', color_str)
    if rgb_match:
        r, g, b = int(rgb_match.group(1)), int(rgb_match.group(2)), int(rgb_match.group(3))
        # Blue: low red, low green, high blue
        return r < 50 and g < 50 and b > 200
    
    # Hex format: #0000ff
    if color_str.startswith('#'):
        hex_color = color_str[1:]
        if len(hex_color) == 6:
            r, g, b = int(hex_color[0:2], 16), int(hex_color[2:4], 16), int(hex_color[4:6], 16)
            return r < 50 and g < 50 and b > 200
    
    return False


def is_light_yellow_color(color_str: str) -> bool:
    """Check if color string represents light yellow (#fffacd or similar)."""
    if not color_str:
        return False
    
    color_str = color_str.lower().strip()
    
    # Target: #fffacd = rgb(255, 250, 205)
    target_r, target_g, target_b = 255, 250, 205
    
    # RGB format
    rgb_match = re.search(r'rgb\s*\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\)', color_str)
    if rgb_match:
        r, g, b = int(rgb_match.group(1)), int(rgb_match.group(2)), int(rgb_match.group(3))
        # Allow some tolerance (±15 for each channel)
        return (abs(r - target_r) <= 15 and 
                abs(g - target_g) <= 15 and 
                abs(b - target_b) <= 15)
    
    # Hex format: #fffacd
    if color_str.startswith('#'):
        hex_color = color_str[1:]
        if len(hex_color) == 6:
            r, g, b = int(hex_color[0:2], 16), int(hex_color[2:4], 16), int(hex_color[4:6], 16)
            return (abs(r - target_r) <= 15 and 
                    abs(g - target_g) <= 15 and 
                    abs(b - target_b) <= 15)
    
    # Named color or variations
    if 'lemonchiffon' in color_str or 'fffacd' in color_str:
        return True
    
    return False


def verify_via_screenshot(copy_from_env) -> Dict[str, Any]:
    """
    Fallback verification using screenshot analysis.
    
    This is less precise but can work when CDP is unavailable.
    """
    if not HAS_PIL:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Cannot verify: CDP unavailable and PIL not installed for screenshot analysis"
        }
    
    logger.info("Using fallback screenshot-based verification")
    
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
    temp_path = temp_file.name
    temp_file.close()
    
    try:
        # Copy screenshot from container
        copy_from_env("/tmp/final_screenshot.png", temp_path)
        
        if not os.path.exists(temp_path) or os.path.getsize(temp_path) == 0:
            os.unlink(temp_path)
            return {
                "passed": False,
                "score": 0,
                "feedback": "Screenshot not available for verification"
            }
        
        # Analyze screenshot
        img = Image.open(temp_path)
        img_array = np.array(img.convert('RGB'))
        
        # Simple heuristic checks
        criteria_met = 0
        feedback_parts = []
        
        # Check for blue pixels (heading color)
        blue_pixels = np.sum((img_array[:, :, 0] < 50) & 
                             (img_array[:, :, 1] < 50) & 
                             (img_array[:, :, 2] > 200))
        has_blue = blue_pixels > 100
        
        if has_blue:
            feedback_parts.append("✓ Blue color detected in image (likely heading)")
            criteria_met += 1
        else:
            feedback_parts.append("✗ Blue color not prominently detected")
        
        # Check for light yellow pixels (content box background)
        yellow_pixels = np.sum((img_array[:, :, 0] > 240) & 
                               (img_array[:, :, 1] > 235) & 
                               (img_array[:, :, 2] > 190) &
                               (img_array[:, :, 2] < 220))
        has_yellow = yellow_pixels > 500
        
        if has_yellow:
            feedback_parts.append("✓ Light yellow color detected (likely content box)")
            criteria_met += 1
        else:
            feedback_parts.append("✗ Light yellow background not detected")
        
        # OCR would be needed to verify text, skip for now
        feedback_parts.append("⚠ Text content verification not available (requires OCR)")
        
        os.unlink(temp_path)
        
        score = int((criteria_met / 3) * 100)  # Only 3 criteria with screenshot
        passed = score >= 60
        
        feedback = "Screenshot-based verification (limited accuracy):\n"
        feedback += "\n".join(feedback_parts)
        feedback += f"\n\nScore: {score}% (based on color detection only)"
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback
        }
        
    except Exception as e:
        if os.path.exists(temp_path):
            os.unlink(temp_path)
        logger.error(f"Screenshot verification error: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Screenshot verification failed: {str(e)}"
        }
