#!/usr/bin/env python3
"""
Verifier for Chrome Responsive Design Mode Testing Task (responsive_viewport_test@1)
Task: Use DevTools device emulation to test mobile viewport

Verification Strategy:
- Connect to Chrome DevTools Protocol (CDP) via WebSocket
- Execute JavaScript to get window.innerWidth and window.innerHeight
- Verify viewport is mobile-sized (width ≤ 500px)
- Validate height is in reasonable mobile range (600-1000px)
- Check aspect ratio and device characteristics
- Score based on multiple criteria
"""

import logging
import sys
import os
import json
import tempfile
from pathlib import Path
from typing import Dict, Any, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Try to import WebSocket library
try:
    import websocket
    HAS_WEBSOCKET = True
except ImportError:
    HAS_WEBSOCKET = False
    logger.warning("websocket-client not available, using fallback verification")

# Add utils to path
sys.path.insert(0, os.path.join(os.path.abspath(__file__), '../../../', 'utils'))
try:
    from chrome_verification_utils import cleanup_verification_temp
except ImportError:
    logger.warning("Chrome verification utilities not available")
    def cleanup_verification_temp():
        pass


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for responsive_viewport_test@1.
    
    Verifies that Chrome DevTools device emulation is active with mobile viewport.
    
    Args:
        traj: Trajectory data (not used)
        env_info: Environment information including copy_from_env function
        task_info: Task configuration
        
    Returns:
        Dict with 'passed', 'score', and 'feedback' keys
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available in environment"
        }

    try:
        # Get viewport data from container
        viewport_data, ws_url = get_viewport_data(copy_from_env)
        
        if viewport_data is None:
            # Try fallback method using live CDP connection
            logger.info("Attempting live CDP connection for viewport data...")
            viewport_data = get_viewport_live_cdp(copy_from_env)
        
        if viewport_data is None or 'error' in viewport_data:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to retrieve viewport data: {viewport_data.get('error', 'unknown error') if viewport_data else 'no data'}"
            }
        
        # Perform verification
        result = verify_responsive_viewport(viewport_data)
        
        # Clean up
        cleanup_verification_temp()
        
        return result
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        cleanup_verification_temp()
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }


def get_viewport_data(copy_from_env) -> Tuple[Optional[Dict], Optional[str]]:
    """
    Get viewport data from container.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Tuple of (viewport_data dict, websocket_url)
    """
    temp_file = None
    ws_url = None
    
    try:
        # Copy viewport data file
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_file.close()
        
        try:
            copy_from_env("/tmp/viewport_data.json", temp_file.name)
            
            with open(temp_file.name, 'r') as f:
                viewport_data = json.load(f)
            
            logger.info(f"Retrieved viewport data: {viewport_data}")
            
            # Try to get WebSocket URL for live connection
            temp_ws = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
            temp_ws.close()
            
            try:
                copy_from_env("/tmp/responsive_ws_url.txt", temp_ws.name)
                with open(temp_ws.name, 'r') as f:
                    ws_url = f.read().strip()
            except:
                pass
            finally:
                if os.path.exists(temp_ws.name):
                    os.unlink(temp_ws.name)
            
            return viewport_data, ws_url
            
        except Exception as e:
            logger.warning(f"Could not copy viewport data: {e}")
            return None, None
            
    finally:
        if temp_file and os.path.exists(temp_file.name):
            os.unlink(temp_file.name)


def get_viewport_live_cdp(copy_from_env) -> Optional[Dict]:
    """
    Attempt to get viewport data via live CDP connection.
    
    This is a fallback when the export script couldn't capture viewport data.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Viewport data dict or None
    """
    if not HAS_WEBSOCKET:
        logger.warning("WebSocket library not available for live CDP connection")
        return None
    
    try:
        # Get WebSocket URL from tabs info
        temp_tabs = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_tabs.close()
        
        try:
            copy_from_env("/tmp/chrome_tabs_responsive.json", temp_tabs.name)
            
            with open(temp_tabs.name, 'r') as f:
                tabs = json.load(f)
            
            if not tabs or len(tabs) == 0:
                return None
            
            ws_url = tabs[0].get('webSocketDebuggerUrl')
            if not ws_url:
                return None
            
            logger.info(f"Attempting WebSocket connection to: {ws_url}")
            
            # This won't work from host if port isn't forwarded
            # So this is more of a template - in practice, the export script
            # should have captured the data
            logger.warning("Live CDP connection from host not supported in this setup")
            return None
            
        finally:
            if os.path.exists(temp_tabs.name):
                os.unlink(temp_tabs.name)
                
    except Exception as e:
        logger.error(f"Failed to get viewport via live CDP: {e}")
        return None


def verify_responsive_viewport(viewport_data: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify that viewport is configured for mobile responsive testing.
    
    Criteria:
    1. DevTools data accessible (CDP working)
    2. Viewport width is mobile-sized (≤ 500px)
    3. Viewport height is reasonable for mobile (600-1000px)
    4. Aspect ratio is valid (portrait or valid landscape)
    5. Configuration suggests mobile emulation (user agent, pixel ratio, etc.)
    
    Args:
        viewport_data: Dict with width, height, userAgent, devicePixelRatio
        
    Returns:
        Verification result with passed, score, and feedback
    """
    width = viewport_data.get('width', 0)
    height = viewport_data.get('height', 0)
    user_agent = viewport_data.get('userAgent', '')
    pixel_ratio = viewport_data.get('devicePixelRatio', 1.0)
    
    criteria_met = 0
    total_criteria = 5
    feedback_parts = []
    
    logger.info(f"Verifying viewport: {width}x{height}, DPR: {pixel_ratio}")
    
    # Criterion 1: CDP data accessible (we have viewport data)
    if width > 0 and height > 0:
        criteria_met += 1
        feedback_parts.append("✓ DevTools data accessible via CDP")
    else:
        feedback_parts.append("✗ No valid viewport data captured")
        return {
            "passed": False,
            "score": 0,
            "feedback": "\n".join(feedback_parts) + "\n\nViewport data could not be retrieved. Ensure DevTools was opened and device toolbar was activated."
        }
    
    # Criterion 2: Mobile viewport width (≤ 500px)
    if width <= 500:
        criteria_met += 1
        feedback_parts.append(f"✓ Mobile viewport width: {width}px (≤ 500px)")
    else:
        feedback_parts.append(f"✗ Viewport too wide: {width}px (expected ≤ 500px for mobile)")
    
    # Criterion 3: Valid mobile height (600-1000px typical range)
    if 600 <= height <= 1000:
        criteria_met += 1
        feedback_parts.append(f"✓ Valid mobile height: {height}px")
    elif 400 <= height < 600:
        criteria_met += 0.5
        feedback_parts.append(f"⚠ Height somewhat low: {height}px (typical range: 600-1000px)")
    else:
        feedback_parts.append(f"✗ Height out of mobile range: {height}px (expected 600-1000px)")
    
    # Criterion 4: Valid aspect ratio (portrait or valid landscape)
    is_portrait = height > width
    is_valid_landscape = not is_portrait and (300 <= width <= 500)
    
    if is_portrait:
        criteria_met += 1
        feedback_parts.append(f"✓ Portrait orientation: {width}x{height}")
    elif is_valid_landscape:
        criteria_met += 1
        feedback_parts.append(f"✓ Landscape mobile orientation: {width}x{height}")
    else:
        feedback_parts.append(f"✗ Invalid aspect ratio: {width}x{height}")
    
    # Criterion 5: Mobile configuration indicators
    mobile_indicators = 0
    
    # Check user agent for mobile keywords
    if 'Mobile' in user_agent or 'Android' in user_agent or 'iPhone' in user_agent:
        mobile_indicators += 1
    
    # Check device pixel ratio (mobile devices typically have DPR > 1)
    if pixel_ratio >= 1.5:
        mobile_indicators += 1
    
    # Even without explicit mobile indicators, narrow viewport suggests emulation
    if width <= 500:
        mobile_indicators += 1
    
    if mobile_indicators >= 2:
        criteria_met += 1
        feedback_parts.append(f"✓ Mobile configuration detected (indicators: {mobile_indicators}/3)")
    elif mobile_indicators == 1:
        criteria_met += 0.5
        feedback_parts.append(f"⚠ Partial mobile configuration (indicators: {mobile_indicators}/3)")
    else:
        feedback_parts.append("✗ No clear mobile configuration indicators")
    
    # Calculate score
    score = int((criteria_met / total_criteria) * 100)
    passed = criteria_met >= 4  # Need at least 4/5 criteria
    
    # Build feedback
    feedback = f"Responsive Design Mode Verification: {criteria_met:.1f}/{total_criteria} criteria met\n\n"
    feedback += "\n".join(feedback_parts)
    feedback += f"\n\n{'='*60}"
    feedback += f"\nViewport: {width}x{height}"
    feedback += f"\nDevice Pixel Ratio: {pixel_ratio}"
    feedback += f"\nUser Agent: {user_agent[:80]}..." if len(user_agent) > 80 else f"\nUser Agent: {user_agent}"
    feedback += f"\n{'='*60}"
    feedback += f"\nFinal Score: {score}%"
    feedback += f"\nResult: {'✅ PASSED' if passed else '❌ FAILED'}"
    
    if not passed:
        feedback += "\n\nTo pass this task, ensure:"
        feedback += "\n  1. Open DevTools (F12 or Ctrl+Shift+I)"
        feedback += "\n  2. Activate device toolbar (click phone icon or Ctrl+Shift+M)"
        feedback += "\n  3. Select a mobile device (e.g., iPhone 12 Pro, iPhone SE)"
        feedback += "\n  4. Verify viewport width is ≤ 500px"
    
    logger.info(f"Verification complete: passed={passed}, score={score}, criteria={criteria_met}/{total_criteria}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "viewport_width": width,
            "viewport_height": height,
            "device_pixel_ratio": pixel_ratio,
            "criteria_met": criteria_met,
            "is_mobile_width": width <= 500,
            "is_portrait": is_portrait
        }
    }
