#!/usr/bin/env python3
"""
Verifier for Chrome DevTools LocalStorage Management Task (devtools_localstorage_edit@1)
Task: Edit localStorage via DevTools Application tab

Verification Strategy:
- Connect to Chrome via CDP (Chrome DevTools Protocol)
- Inject JavaScript to read localStorage state
- Verify specific operations: edit, add, delete, preserve
- Multi-criteria scoring based on 4 operations
"""

import logging
import sys
import os
import json
import time
import tempfile
from pathlib import Path
from typing import Dict, Any, Optional, Tuple

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Try to import requests for CDP communication
try:
    import requests
    HAS_REQUESTS = True
except ImportError:
    HAS_REQUESTS = False
    logger.warning("requests library not available, will attempt to install")


def ensure_requests():
    """Ensure requests library is available"""
    global HAS_REQUESTS, requests
    if not HAS_REQUESTS:
        try:
            import subprocess
            subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "requests"])
            import requests
            HAS_REQUESTS = True
        except Exception as e:
            logger.error(f"Failed to install requests: {e}")
            return False
    return True


def get_localstorage_via_cdp(cdp_url="http://localhost:9222"):
    """
    Query localStorage using Chrome DevTools Protocol
    
    Args:
        cdp_url: Chrome DevTools Protocol endpoint URL
        
    Returns:
        Dict with localStorage key-value pairs, or None on error
    """
    if not ensure_requests():
        logger.error("Cannot query CDP without requests library")
        return None
    
    try:
        # Get list of tabs
        response = requests.get(f"{cdp_url}/json", timeout=5)
        tabs = response.json()
        
        # Find the page tab containing our test page
        target_tab = None
        for tab in tabs:
            if tab.get('type') == 'page':
                url = tab.get('url', '')
                if 'storage_test.html' in url or url.startswith('file://'):
                    target_tab = tab
                    break
        
        if not target_tab:
            # If no storage_test.html, just use first page tab
            for tab in tabs:
                if tab.get('type') == 'page':
                    target_tab = tab
                    break
        
        if not target_tab:
            logger.error("No page tab found in Chrome")
            return None
        
        # Get the devtools frontend URL (we'll use HTTP API instead of WebSocket)
        tab_id = target_tab.get('id')
        
        # Use a simpler approach: execute JavaScript via CDP HTTP endpoint
        # Note: This requires using the tab's webSocketDebuggerUrl, but we can also
        # use a workaround by creating a temporary extension or using the HTTP API
        
        # For this implementation, we'll use a Python-based CDP client approach
        # Create a session to the specific tab
        ws_url = target_tab.get('webSocketDebuggerUrl', '')
        
        if not ws_url:
            logger.warning("No WebSocket URL available, trying alternative method")
            return None
        
        # Since we can't easily use WebSocket in this context, we'll use a fallback
        # The export script should have captured what it could
        
        # Alternative: Use requests with CDP JSON API (limited functionality)
        # But for localStorage, we need to execute JavaScript, which requires WebSocket
        
        # Let's try a different approach: use the /json/new endpoint which isn't ideal
        # but might work for simple evaluation
        
        logger.info(f"Target tab: {target_tab.get('title', 'Unknown')}")
        logger.info(f"Target URL: {target_tab.get('url', 'Unknown')}")
        
        # As a workaround, return a marker that we need WebSocket
        return {"_needs_websocket": True, "tab_info": target_tab}
        
    except Exception as e:
        logger.error(f"Error querying CDP: {e}", exc_info=True)
        return None


def get_localstorage_via_websocket(ws_url):
    """
    Get localStorage via WebSocket CDP connection
    
    This is the proper way to interact with CDP for JavaScript execution
    """
    try:
        # Try to import websocket library
        try:
            import websocket
        except ImportError:
            import subprocess
            subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "websocket-client"])
            import websocket
        
        # Connect to WebSocket
        ws = websocket.create_connection(ws_url, timeout=5)
        
        # Execute JavaScript to read localStorage
        js_code = """
        (function() {
            const result = {};
            try {
                for (let i = 0; i < localStorage.length; i++) {
                    const key = localStorage.key(i);
                    if (key !== '_initialized') {
                        result[key] = localStorage.getItem(key);
                    }
                }
                return result;
            } catch (e) {
                return {error: e.toString()};
            }
        })()
        """
        
        # Send Runtime.evaluate command
        command = {
            "id": 1,
            "method": "Runtime.evaluate",
            "params": {
                "expression": js_code,
                "returnByValue": True
            }
        }
        
        ws.send(json.dumps(command))
        
        # Receive response
        response = ws.recv()
        result = json.loads(response)
        
        ws.close()
        
        # Extract localStorage data from result
        if 'result' in result and 'result' in result['result']:
            storage_data = result['result']['result'].get('value', {})
            return storage_data
        
        return None
        
    except Exception as e:
        logger.error(f"Error using WebSocket CDP: {e}", exc_info=True)
        return None


def verify_localstorage_changes(storage_data):
    """
    Verify that localStorage was correctly modified
    
    Expected changes:
    1. theme: "light" → "dark" (edit)
    2. notifications: "enabled" (add)
    3. fontSize: deleted (delete)
    4. username: "testuser" (preserve)
    
    Args:
        storage_data: Dict with current localStorage state
        
    Returns:
        Dict with verification results
    """
    if not storage_data:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Could not retrieve localStorage data",
            "criteria": {}
        }
    
    # Check for error in storage data
    if "error" in storage_data:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Error reading localStorage: {storage_data['error']}",
            "criteria": {}
        }
    
    logger.info(f"Current localStorage state: {json.dumps(storage_data, indent=2)}")
    
    # Criterion 1: theme edited to "dark"
    theme_correct = storage_data.get('theme') == 'dark'
    
    # Criterion 2: notifications added with value "enabled"
    notifications_correct = storage_data.get('notifications') == 'enabled'
    
    # Criterion 3: fontSize deleted (should not exist)
    fontsize_deleted = 'fontSize' not in storage_data
    
    # Criterion 4: username preserved as "testuser"
    username_preserved = storage_data.get('username') == 'testuser'
    
    # Calculate score
    criteria = {
        "theme_edited": theme_correct,
        "notifications_added": notifications_correct,
        "fontSize_deleted": fontsize_deleted,
        "username_preserved": username_preserved
    }
    
    criteria_met = sum(criteria.values())
    score = (criteria_met / 4) * 100
    passed = score >= 75  # Need at least 3 out of 4 criteria
    
    # Generate detailed feedback
    feedback_parts = []
    feedback_parts.append(f"LocalStorage Verification: {criteria_met}/4 criteria met\n")
    
    if theme_correct:
        feedback_parts.append("✓ 'theme' correctly edited to 'dark'")
    else:
        current_theme = storage_data.get('theme', '(not found)')
        feedback_parts.append(f"✗ 'theme' is '{current_theme}' (expected 'dark')")
    
    if notifications_correct:
        feedback_parts.append("✓ 'notifications' correctly added with value 'enabled'")
    else:
        current_notif = storage_data.get('notifications', '(not found)')
        feedback_parts.append(f"✗ 'notifications' is '{current_notif}' (expected 'enabled')")
    
    if fontsize_deleted:
        feedback_parts.append("✓ 'fontSize' correctly deleted")
    else:
        current_fontsize = storage_data.get('fontSize', '')
        feedback_parts.append(f"✗ 'fontSize' still exists with value '{current_fontsize}' (should be deleted)")
    
    if username_preserved:
        feedback_parts.append("✓ 'username' correctly preserved as 'testuser'")
    else:
        current_username = storage_data.get('username', '(not found)')
        feedback_parts.append(f"✗ 'username' is '{current_username}' (expected 'testuser')")
    
    feedback_parts.append(f"\nFinal Score: {int(score)}%")
    feedback_parts.append(f"Result: {'PASSED ✓' if passed else 'FAILED ✗'}")
    
    feedback = "\n".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": int(score),
        "feedback": feedback,
        "criteria": criteria,
        "storage_state": storage_data
    }


def verify_task(traj, env_info, task_info):
    """
    Main verification function for devtools_localstorage_edit@1
    
    Args:
        traj: Trajectory data (unused)
        env_info: Environment information
        task_info: Task configuration
        
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
    
    try:
        # Try to get CDP info that was captured
        cdp_info = None
        try:
            temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
            temp_file.close()
            copy_from_env("/tmp/cdp_info.json", temp_file.name)
            
            with open(temp_file.name, 'r') as f:
                cdp_info = json.load(f)
            
            os.unlink(temp_file.name)
        except Exception as e:
            logger.warning(f"Could not get CDP info from export: {e}")
        
        # Try to query localStorage via CDP
        logger.info("Attempting to query localStorage via Chrome DevTools Protocol...")
        
        storage_data = get_localstorage_via_cdp()
        
        # If we got the WebSocket marker, try WebSocket connection
        if storage_data and storage_data.get('_needs_websocket'):
            tab_info = storage_data.get('tab_info', {})
            ws_url = tab_info.get('webSocketDebuggerUrl')
            
            if ws_url:
                logger.info(f"Using WebSocket to query localStorage...")
                storage_data = get_localstorage_via_websocket(ws_url)
            else:
                logger.warning("No WebSocket URL available")
                storage_data = None
        
        # If CDP query didn't work, return failure with helpful message
        if storage_data is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Could not access localStorage via Chrome DevTools Protocol. This may indicate:\n"
                           "- DevTools was not used to modify localStorage\n"
                           "- Chrome is not running or CDP is not accessible\n"
                           "- The test page is not loaded\n\n"
                           "Please ensure you opened DevTools (F12) and used the Application tab to modify localStorage."
            }
        
        # Verify the changes
        result = verify_localstorage_changes(storage_data)
        
        return result
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }
