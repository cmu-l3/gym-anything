#!/usr/bin/env python3
"""
Verifier for Chrome DevTools Console DOM Manipulation Task (console_dom_manipulation@1)
Task: Use DevTools Console to execute JavaScript that modifies the DOM

Verification Strategy:
- Uses Chrome DevTools Protocol (CDP) via WebSocket to inspect live DOM
- Executes JavaScript queries to check:
  1. Body background color is #2196F3 (blue)
  2. H1 element text is "DevTools Console Success!"
  3. Paragraph font size is 24px
- Calculates score based on criteria met (need 2/3 to pass)
"""

import logging
import sys
import os
import json
import tempfile
import time
from pathlib import Path
from typing import Dict, Any, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Try to import websocket for CDP communication
try:
    import websocket
    HAS_WEBSOCKET = True
except ImportError:
    HAS_WEBSOCKET = False
    logger.warning("websocket-client not available, will use HTTP-only verification")

# Try to import requests for HTTP fallback
try:
    import requests
    HAS_REQUESTS = True
except ImportError:
    HAS_REQUESTS = False
    logger.warning("requests not available")


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for console_dom_manipulation@1 task.
    
    Verifies that JavaScript commands were executed in DevTools Console to:
    1. Change body background color to #2196F3
    2. Change h1 text to "DevTools Console Success!"
    3. Change paragraph font size to 24px
    
    Args:
        traj: Trajectory data (unused for this task)
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

    # Give Chrome a moment to stabilize after agent actions
    time.sleep(2)

    try:
        # Get WebSocket URL from exported data
        ws_url = get_websocket_url(copy_from_env)
        
        if not ws_url:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Could not find test page WebSocket URL. Ensure the test page is open in Chrome."
            }
        
        # Verify DOM modifications via CDP
        verification_result = verify_dom_modifications_via_cdp(ws_url)
        
        return verification_result

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }


def get_websocket_url(copy_from_env) -> Optional[str]:
    """
    Retrieve WebSocket debugger URL for the test page from container.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        WebSocket URL string or None if not found
    """
    try:
        # Copy the WebSocket URL file
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.txt', mode='w+')
        temp_path = temp_file.name
        temp_file.close()
        
        copy_from_env("/tmp/ws_debugger_url.txt", temp_path)
        
        with open(temp_path, 'r') as f:
            ws_url = f.read().strip()
        
        os.unlink(temp_path)
        
        if ws_url and ws_url != "null" and ws_url != "":
            logger.info(f"Retrieved WebSocket URL: {ws_url[:50]}...")
            return ws_url
        else:
            logger.warning("WebSocket URL is empty or null")
            return None
            
    except Exception as e:
        logger.error(f"Failed to get WebSocket URL: {e}")
        return None


def verify_dom_modifications_via_cdp(ws_url: str) -> Dict[str, Any]:
    """
    Verify DOM modifications by executing JavaScript via CDP WebSocket.
    
    Checks:
    1. Background color is #2196F3 or rgb(33, 150, 243)
    2. H1 text is "DevTools Console Success!"
    3. Paragraph font size is 24px
    
    Args:
        ws_url: WebSocket debugger URL for CDP connection
        
    Returns:
        Verification result dictionary
    """
    if not HAS_WEBSOCKET:
        return {
            "passed": False,
            "score": 0,
            "feedback": "websocket-client library not available for CDP verification"
        }
    
    ws = None
    try:
        # Connect to Chrome via WebSocket
        logger.info("Connecting to Chrome via CDP WebSocket...")
        ws = websocket.create_connection(ws_url, timeout=10)
        logger.info("✓ Connected to Chrome DevTools Protocol")
        
        modifications_passed = 0
        total_modifications = 3
        feedback_items = []
        
        # Criterion 1: Background color
        logger.info("Checking background color...")
        bg_color_result = check_background_color(ws)
        if bg_color_result["passed"]:
            modifications_passed += 1
            feedback_items.append("✓ Background color changed to blue (#2196F3)")
        else:
            feedback_items.append(f"✗ {bg_color_result['feedback']}")
        
        # Criterion 2: Heading text
        logger.info("Checking heading text...")
        heading_result = check_heading_text(ws)
        if heading_result["passed"]:
            modifications_passed += 1
            feedback_items.append("✓ Heading text changed to 'DevTools Console Success!'")
        else:
            feedback_items.append(f"✗ {heading_result['feedback']}")
        
        # Criterion 3: Paragraph font size
        logger.info("Checking paragraph font size...")
        font_size_result = check_paragraph_font_size(ws)
        if font_size_result["passed"]:
            modifications_passed += 1
            feedback_items.append("✓ Paragraph font size increased to 24px")
        else:
            feedback_items.append(f"✗ {font_size_result['feedback']}")
        
        # Close WebSocket connection
        ws.close()
        
        # Calculate score
        score = int((modifications_passed / total_modifications) * 100)
        passed = score >= 67  # Need at least 2 out of 3 (67%)
        
        # Build feedback
        feedback = f"DOM Modifications: {modifications_passed}/{total_modifications} completed\n"
        feedback += "\n".join(feedback_items)
        feedback += f"\n\nScore: {score}%"
        
        if passed:
            feedback += "\n✅ Task completed successfully!"
        else:
            feedback += "\n❌ Task incomplete - more DOM modifications needed"
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "details": {
                "background_color": bg_color_result,
                "heading_text": heading_result,
                "font_size": font_size_result,
                "modifications_passed": modifications_passed
            }
        }
        
    except Exception as e:
        logger.error(f"CDP verification error: {e}", exc_info=True)
        if ws:
            ws.close()
        return {
            "passed": False,
            "score": 0,
            "feedback": f"CDP communication error: {str(e)}"
        }


def execute_js_via_cdp(ws, expression: str) -> Tuple[bool, Any, str]:
    """
    Execute JavaScript expression via CDP and return result.
    
    Args:
        ws: WebSocket connection
        expression: JavaScript expression to execute
        
    Returns:
        Tuple of (success, result_value, error_message)
    """
    try:
        msg_id = int(time.time() * 1000000) % 1000000
        
        message = json.dumps({
            "id": msg_id,
            "method": "Runtime.evaluate",
            "params": {
                "expression": expression,
                "returnByValue": True
            }
        })
        
        ws.send(message)
        
        # Read response (may need to read multiple messages)
        max_attempts = 5
        for _ in range(max_attempts):
            response_str = ws.recv()
            response = json.loads(response_str)
            
            # Check if this is the response to our message
            if response.get("id") == msg_id:
                if "result" in response:
                    result = response["result"].get("result", {})
                    if "value" in result:
                        return True, result["value"], ""
                    elif "description" in result:
                        return True, result["description"], ""
                    else:
                        return False, None, "No value in result"
                elif "error" in response:
                    return False, None, f"CDP error: {response['error']}"
                else:
                    return False, None, "Unexpected response format"
        
        return False, None, "Timeout waiting for response"
        
    except Exception as e:
        logger.error(f"Error executing JS via CDP: {e}")
        return False, None, str(e)


def check_background_color(ws) -> Dict[str, Any]:
    """
    Check if body background color is #2196F3 (blue).
    
    Returns:
        Dict with passed status, value, and feedback
    """
    expression = "document.body.style.backgroundColor"
    success, value, error = execute_js_via_cdp(ws, expression)
    
    if not success:
        return {
            "passed": False,
            "value": None,
            "feedback": f"Could not retrieve background color: {error}"
        }
    
    # Normalize the color value
    value_lower = str(value).lower().replace(" ", "")
    
    # Check for multiple valid representations
    is_blue = (
        "#2196f3" in value_lower or
        "rgb(33,150,243)" in value_lower or
        "rgb(33, 150, 243)" in value_lower
    )
    
    if is_blue:
        return {
            "passed": True,
            "value": value,
            "feedback": f"Background color is blue: {value}"
        }
    else:
        return {
            "passed": False,
            "value": value,
            "feedback": f"Background color not changed (found: {value}, expected: #2196F3)"
        }


def check_heading_text(ws) -> Dict[str, Any]:
    """
    Check if h1 element text is "DevTools Console Success!".
    
    Returns:
        Dict with passed status, value, and feedback
    """
    expression = "document.querySelector('h1').textContent"
    success, value, error = execute_js_via_cdp(ws, expression)
    
    if not success:
        return {
            "passed": False,
            "value": None,
            "feedback": f"Could not retrieve heading text: {error}"
        }
    
    expected_text = "DevTools Console Success!"
    
    if str(value) == expected_text:
        return {
            "passed": True,
            "value": value,
            "feedback": f"Heading text is correct: '{value}'"
        }
    else:
        return {
            "passed": False,
            "value": value,
            "feedback": f"Heading text not changed (found: '{value}', expected: '{expected_text}')"
        }


def check_paragraph_font_size(ws) -> Dict[str, Any]:
    """
    Check if paragraph font size is 24px.
    
    Returns:
        Dict with passed status, value, and feedback
    """
    expression = "window.getComputedStyle(document.querySelector('p')).fontSize"
    success, value, error = execute_js_via_cdp(ws, expression)
    
    if not success:
        return {
            "passed": False,
            "value": None,
            "feedback": f"Could not retrieve font size: {error}"
        }
    
    # Font size should be "24px"
    if "24px" in str(value):
        return {
            "passed": True,
            "value": value,
            "feedback": f"Paragraph font size is 24px: {value}"
        }
    else:
        return {
            "passed": False,
            "value": value,
            "feedback": f"Paragraph font size not changed (found: {value}, expected: 24px)"
        }
