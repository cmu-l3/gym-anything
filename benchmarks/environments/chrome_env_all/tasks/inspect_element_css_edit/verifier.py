#!/usr/bin/env python3
"""
Verifier for Chrome DevTools CSS Editing Task: inspect_element_css_edit@1
Task: Use DevTools to inspect element and change its background color to red

Verification Strategy:
- Uses Chrome DevTools Protocol (CDP) to query DOM and computed styles
- Locates target element by ID (#main-heading)
- Retrieves computed background-color style
- Normalizes color values (handles red, #FF0000, #ff0000, rgb(255,0,0), etc.)
- Validates that background color was successfully changed to red
"""

import logging
import sys
import os
import json
import re
import requests
from typing import Dict, Any, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Try to import websocket for CDP
try:
    import websocket
    HAS_WEBSOCKET = True
except ImportError:
    HAS_WEBSOCKET = False
    logger.warning("websocket-client not available, will use HTTP-only CDP queries")


def normalize_color_to_rgb(color_value: str) -> Optional[Tuple[int, int, int]]:
    """
    Normalize color value to RGB tuple for consistent comparison.
    
    Handles:
    - Keywords: red, blue, green, etc.
    - Hex: #FF0000, #ff0000, #F00, #f00
    - RGB: rgb(255, 0, 0), rgb(255,0,0)
    - RGBA: rgba(255, 0, 0, 1), rgba(255,0,0,1)
    
    Args:
        color_value: Color string in any supported format
        
    Returns:
        Tuple of (r, g, b) as integers 0-255, or None if unparseable
    """
    if not color_value:
        return None
    
    color_value = color_value.strip().lower()
    
    # CSS color keywords
    color_keywords = {
        'red': (255, 0, 0),
        'blue': (0, 0, 255),
        'green': (0, 128, 0),
        'lime': (0, 255, 0),
        'yellow': (255, 255, 0),
        'cyan': (0, 255, 255),
        'magenta': (255, 0, 255),
        'black': (0, 0, 0),
        'white': (255, 255, 255),
        'gray': (128, 128, 128),
        'grey': (128, 128, 128),
        'lightblue': (173, 216, 230),
        'darkred': (139, 0, 0),
        'darkblue': (0, 0, 139),
        'orange': (255, 165, 0),
        'purple': (128, 0, 128),
    }
    
    # Check keyword match
    if color_value in color_keywords:
        return color_keywords[color_value]
    
    # Hex format (#FF0000 or #F00)
    hex_match = re.match(r'^#([0-9a-f]{3}|[0-9a-f]{6})$', color_value)
    if hex_match:
        hex_value = hex_match.group(1)
        if len(hex_value) == 3:
            # Expand shorthand #F00 -> #FF0000
            hex_value = ''.join([c*2 for c in hex_value])
        r = int(hex_value[0:2], 16)
        g = int(hex_value[2:4], 16)
        b = int(hex_value[4:6], 16)
        return (r, g, b)
    
    # RGB/RGBA format
    rgb_match = re.match(r'rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)', color_value)
    if rgb_match:
        r, g, b = map(int, rgb_match.groups())
        return (r, g, b)
    
    logger.warning(f"Could not parse color value: {color_value}")
    return None


def colors_match(color1: str, color2: str, tolerance: int = 5) -> bool:
    """
    Check if two colors match within tolerance.
    
    Args:
        color1: First color in any format
        color2: Second color in any format
        tolerance: Maximum difference per RGB channel (0-255)
        
    Returns:
        True if colors match within tolerance
    """
    rgb1 = normalize_color_to_rgb(color1)
    rgb2 = normalize_color_to_rgb(color2)
    
    if rgb1 is None or rgb2 is None:
        logger.warning(f"Could not compare colors: {color1} vs {color2}")
        return False
    
    # Check each channel within tolerance
    match = all(abs(a - b) <= tolerance for a, b in zip(rgb1, rgb2))
    
    logger.info(f"Color comparison: {color1} -> {rgb1} vs {color2} -> {rgb2} = {match}")
    return match


def is_red_color(color_value: str, tolerance: int = 5) -> bool:
    """
    Check if a color value represents red.
    
    Args:
        color_value: Color in any format
        tolerance: Tolerance for R channel deviation from 255
        
    Returns:
        True if color is red (R≈255, G≈0, B≈0)
    """
    rgb = normalize_color_to_rgb(color_value)
    if rgb is None:
        return False
    
    r, g, b = rgb
    
    # Red should have:
    # - R channel near 255 (within tolerance)
    # - G and B channels near 0 (within tolerance)
    is_red = (
        (255 - tolerance <= r <= 255) and
        (0 <= g <= tolerance) and
        (0 <= b <= tolerance)
    )
    
    logger.info(f"Is red check: {color_value} -> RGB{rgb} = {is_red}")
    return is_red


def get_cdp_websocket_url() -> Optional[str]:
    """
    Get CDP WebSocket URL for the active tab.
    
    Returns:
        WebSocket debugger URL or None if unavailable
    """
    try:
        response = requests.get('http://localhost:9222/json', timeout=5)
        tabs = response.json()
        
        # Find the first page-type tab
        for tab in tabs:
            if tab.get('type') == 'page':
                ws_url = tab.get('webSocketDebuggerUrl')
                if ws_url:
                    return ws_url
        
        logger.warning("No page tab found with webSocketDebuggerUrl")
        return None
        
    except Exception as e:
        logger.error(f"Failed to get CDP WebSocket URL: {e}")
        return None


def get_element_computed_style_via_cdp(element_selector: str, property_name: str) -> Optional[str]:
    """
    Get computed style property for an element using CDP.
    
    Args:
        element_selector: CSS selector for target element (e.g., "#main-heading")
        property_name: CSS property name (e.g., "background-color")
        
    Returns:
        Property value as string, or None if failed
    """
    if not HAS_WEBSOCKET:
        logger.error("websocket-client not available, cannot query CDP via WebSocket")
        return None
    
    ws_url = get_cdp_websocket_url()
    if not ws_url:
        logger.error("Could not get CDP WebSocket URL")
        return None
    
    ws = None
    try:
        # Connect to CDP via WebSocket
        ws = websocket.create_connection(ws_url, timeout=10)
        logger.info(f"Connected to CDP via WebSocket: {ws_url}")
        
        # Enable DOM domain
        ws.send(json.dumps({"id": 1, "method": "DOM.enable"}))
        response = ws.recv()
        logger.debug(f"DOM.enable response: {response}")
        
        # Enable CSS domain
        ws.send(json.dumps({"id": 2, "method": "CSS.enable"}))
        response = ws.recv()
        logger.debug(f"CSS.enable response: {response}")
        
        # Get document root
        ws.send(json.dumps({"id": 3, "method": "DOM.getDocument", "params": {"depth": -1}}))
        response = json.loads(ws.recv())
        if 'error' in response:
            logger.error(f"Error getting document: {response['error']}")
            return None
        root_node_id = response['result']['root']['nodeId']
        logger.info(f"Got document root node ID: {root_node_id}")
        
        # Query for target element
        ws.send(json.dumps({
            "id": 4,
            "method": "DOM.querySelector",
            "params": {
                "nodeId": root_node_id,
                "selector": element_selector
            }
        }))
        response = json.loads(ws.recv())
        
        if 'error' in response:
            logger.error(f"Error querying element '{element_selector}': {response['error']}")
            return None
        
        element_node_id = response['result'].get('nodeId', 0)
        if element_node_id == 0:
            logger.error(f"Element '{element_selector}' not found")
            return None
        
        logger.info(f"Found element '{element_selector}' with node ID: {element_node_id}")
        
        # Get computed styles for the element
        ws.send(json.dumps({
            "id": 5,
            "method": "CSS.getComputedStyleForNode",
            "params": {
                "nodeId": element_node_id
            }
        }))
        response = json.loads(ws.recv())
        
        if 'error' in response:
            logger.error(f"Error getting computed styles: {response['error']}")
            return None
        
        computed_styles = response['result']['computedStyle']
        
        # Find the requested property
        for style in computed_styles:
            if style['name'] == property_name:
                value = style['value']
                logger.info(f"Found {property_name}: {value}")
                return value
        
        logger.warning(f"Property '{property_name}' not found in computed styles")
        return None
        
    except websocket.WebSocketException as e:
        logger.error(f"WebSocket error: {e}")
        return None
    except Exception as e:
        logger.error(f"Error querying CDP: {e}", exc_info=True)
        return None
    finally:
        if ws:
            try:
                ws.close()
            except:
                pass


def verify_css_modification() -> Dict[str, Any]:
    """
    Verify that the CSS background color was changed to red.
    
    Returns:
        Verification result dict with passed, score, and feedback
    """
    element_selector = "#main-heading"
    property_name = "background-color"
    expected_color = "red"
    
    # Get the current computed style
    actual_color = get_element_computed_style_via_cdp(element_selector, property_name)
    
    if actual_color is None:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to retrieve computed style for element '{element_selector}'. "
                       f"Ensure DevTools was used to modify the element's CSS."
        }
    
    logger.info(f"Retrieved background-color: {actual_color}")
    
    # Check if the color is red
    if is_red_color(actual_color, tolerance=10):
        # Perfect success
        normalized = normalize_color_to_rgb(actual_color)
        return {
            "passed": True,
            "score": 100,
            "feedback": f"✅ Success! Background color successfully changed to red.\n"
                       f"Computed style: {actual_color} → RGB{normalized}",
            "details": {
                "element": element_selector,
                "property": property_name,
                "expected": "red (RGB: 255, 0, 0)",
                "actual": f"{actual_color} (RGB: {normalized})"
            }
        }
    
    # Check if it's still the original color (lightblue)
    if "173" in actual_color or "216" in actual_color or "230" in actual_color or "lightblue" in actual_color.lower():
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Background color unchanged. Still appears to be lightblue.\n"
                       f"Computed style: {actual_color}\n"
                       f"Please use DevTools to change it to red.",
            "details": {
                "element": element_selector,
                "property": property_name,
                "expected": "red (RGB: 255, 0, 0)",
                "actual": actual_color,
                "issue": "Color not modified"
            }
        }
    
    # Color was changed but not to red
    normalized = normalize_color_to_rgb(actual_color)
    return {
        "passed": False,
        "score": 50,
        "feedback": f"⚠ Background color was modified but not to red.\n"
                   f"Computed style: {actual_color} → RGB{normalized}\n"
                   f"Expected: red → RGB(255, 0, 0)\n"
                   f"Please change the background-color to red (not {actual_color}).",
        "details": {
            "element": element_selector,
            "property": property_name,
            "expected": "red (RGB: 255, 0, 0)",
            "actual": f"{actual_color} (RGB: {normalized})",
            "issue": "Wrong color"
        }
    }


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for inspect_element_css_edit@1.
    
    Args:
        traj: Trajectory data (not used)
        env_info: Environment information
        task_info: Task configuration
        
    Returns:
        Dict with passed, score, and feedback
    """
    try:
        # Check if CDP is accessible
        try:
            response = requests.get('http://localhost:9222/json', timeout=5)
            if response.status_code != 200:
                return {
                    "passed": False,
                    "score": 0,
                    "feedback": "Chrome DevTools Protocol (CDP) not accessible. "
                               "Ensure Chrome is running with remote debugging enabled."
                }
        except Exception as e:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Cannot connect to Chrome CDP: {str(e)}"
            }
        
        # Check if websocket library is available
        if not HAS_WEBSOCKET:
            return {
                "passed": False,
                "score": 0,
                "feedback": "websocket-client library not available. "
                           "Cannot perform CDP-based verification."
            }
        
        # Perform the CSS modification verification
        result = verify_css_modification()
        
        return result
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }
