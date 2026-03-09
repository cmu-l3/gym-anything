#!/usr/bin/env python3
"""
Verifier for Chrome Local Storage Manipulation Task (local_storage_edit@1)
Task: Use DevTools Application panel to modify localStorage: add 'theme':'dark' and change 'language' to 'es'

Verification Strategy:
- Uses Chrome DevTools Protocol (CDP) Runtime.evaluate to inspect localStorage
- Connects via WebSocket to execute JavaScript in browser context
- Verifies: new key added, value correct, existing key modified, pre-existing data intact
"""

import logging
import sys
import os
import json
import tempfile
import time
from pathlib import Path
from typing import Dict, Any, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Try importing required libraries
try:
    import websocket
    HAS_WEBSOCKET = True
except ImportError:
    logger.warning("websocket-client not available, attempting install...")
    try:
        import subprocess
        subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "websocket-client"], 
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        import websocket
        HAS_WEBSOCKET = True
    except:
        HAS_WEBSOCKET = False

try:
    import requests
    HAS_REQUESTS = True
except ImportError:
    logger.warning("requests not available")
    try:
        import subprocess
        subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "requests"],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        import requests
        HAS_REQUESTS = True
    except:
        HAS_REQUESTS = False


def get_localstorage_via_cdp(cdp_url="http://localhost:9222", timeout=10):
    """
    Connect to Chrome via CDP and retrieve localStorage contents.
    
    Args:
        cdp_url: Base URL for Chrome DevTools Protocol
        timeout: Timeout in seconds for operations
        
    Returns:
        Dict of localStorage key-value pairs, or None on failure
    """
    if not HAS_REQUESTS or not HAS_WEBSOCKET:
        logger.error("Required libraries not available (requests, websocket-client)")
        return None
    
    try:
        # Get list of targets/tabs
        logger.info(f"Connecting to CDP at {cdp_url}")
        response = requests.get(f"{cdp_url}/json", timeout=timeout)
        targets = response.json()
        
        logger.info(f"Found {len(targets)} CDP targets")
        
        # Find the test page target (prefer file:// with localstorage_test)
        test_page_target = None
        for target in targets:
            if target.get('type') == 'page':
                url = target.get('url', '')
                logger.debug(f"Checking target: {url[:80]}")
                if 'localstorage_test.html' in url:
                    test_page_target = target
                    logger.info(f"✓ Found test page: {url}")
                    break
        
        # Fallback: use first file:// page
        if not test_page_target:
            for target in targets:
                if target.get('type') == 'page':
                    url = target.get('url', '')
                    if url.startswith('file://'):
                        test_page_target = target
                        logger.info(f"Using file:// page: {url}")
                        break
        
        # Last resort: use any page
        if not test_page_target:
            for target in targets:
                if target.get('type') == 'page':
                    test_page_target = target
                    logger.warning(f"Using fallback target: {target.get('url', 'unknown')[:80]}")
                    break
        
        if not test_page_target:
            logger.error("No suitable page targets found")
            return None
        
        # Connect to WebSocket debugger
        ws_url = test_page_target.get('webSocketDebuggerUrl')
        if not ws_url:
            logger.error("No WebSocket URL in target")
            return None
        
        logger.info(f"Connecting to WebSocket: {ws_url[:70]}...")
        ws = websocket.create_connection(ws_url, timeout=timeout)
        
        # Execute JavaScript to read localStorage
        command = {
            "id": 1,
            "method": "Runtime.evaluate",
            "params": {
                "expression": """
                    (function() {
                        let storage = {};
                        try {
                            for (let i = 0; i < localStorage.length; i++) {
                                let key = localStorage.key(i);
                                storage[key] = localStorage.getItem(key);
                            }
                            return JSON.stringify(storage);
                        } catch (e) {
                            return JSON.stringify({_error: e.toString()});
                        }
                    })()
                """,
                "returnByValue": True
            }
        }
        
        ws.send(json.dumps(command))
        response_raw = ws.recv()
        response = json.loads(response_raw)
        ws.close()
        
        # Parse result
        if 'result' in response and 'result' in response['result']:
            storage_json = response['result']['result'].get('value', '{}')
            storage_dict = json.loads(storage_json)
            
            if '_error' in storage_dict:
                logger.error(f"JavaScript error: {storage_dict['_error']}")
                return None
            
            logger.info(f"✓ Successfully retrieved localStorage: {storage_dict}")
            return storage_dict
        else:
            logger.error(f"Unexpected CDP response: {response}")
            return None
        
    except requests.exceptions.RequestException as e:
        logger.error(f"HTTP request failed: {e}")
        return None
    except websocket.WebSocketException as e:
        logger.error(f"WebSocket error: {e}")
        return None
    except Exception as e:
        logger.error(f"Error retrieving localStorage via CDP: {e}", exc_info=True)
        return None


def verify_task(traj, env_info, task_info):
    """
    Main verification function for local_storage_edit@1.
    
    Verifies:
    1. New key "theme" added with value "dark"
    2. New key has correct value "dark"
    3. Existing key "language" modified from "en" to "es"
    4. Pre-existing key "initialized" remains "true"
    5. No unexpected extra keys
    
    Scoring:
    - 100%: All 5 criteria met (perfect)
    - 75-99%: 4/5 criteria met (minor issues, passing)
    - 50-74%: 3/5 criteria met (partial)
    - 25-49%: 2/5 criteria met (incomplete)
    - 0-24%: 0-1 criteria met (failed)
    
    Pass threshold: 75% (need 4+ out of 5)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "copy_from_env function not available"
        }
    
    # Give Chrome a moment to stabilize after task
    time.sleep(2)
    
    # Retrieve localStorage via CDP
    logger.info("Retrieving localStorage via CDP...")
    storage_data = get_localstorage_via_cdp()
    
    if storage_data is None:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Failed to retrieve localStorage via CDP. Ensure Chrome is running with remote debugging enabled on port 9222."
        }
    
    # Define verification criteria
    criteria_met = 0
    total_criteria = 5
    feedback_parts = []
    
    # Criterion 1: New key "theme" exists
    if "theme" in storage_data:
        criteria_met += 1
        feedback_parts.append("✓ 'theme' key added to localStorage")
    else:
        feedback_parts.append("✗ 'theme' key NOT found in localStorage")
    
    # Criterion 2: "theme" has correct value "dark"
    theme_value = storage_data.get("theme", "")
    if theme_value == "dark":
        criteria_met += 1
        feedback_parts.append("✓ 'theme' value is 'dark' ✓")
    elif "theme" in storage_data:
        feedback_parts.append(f"✗ 'theme' has wrong value: '{theme_value}' (expected: 'dark')")
    else:
        feedback_parts.append("✗ 'theme' key missing (cannot check value)")
    
    # Criterion 3: "language" was modified to "es"
    language_value = storage_data.get("language", "")
    if language_value == "es":
        criteria_met += 1
        feedback_parts.append("✓ 'language' successfully changed to 'es' ✓")
    elif language_value == "en":
        feedback_parts.append("✗ 'language' NOT modified (still 'en', expected: 'es')")
    else:
        feedback_parts.append(f"✗ 'language' has unexpected value: '{language_value}' (expected: 'es')")
    
    # Criterion 4: "initialized" remained unchanged
    initialized_value = storage_data.get("initialized", "")
    if initialized_value == "true":
        criteria_met += 1
        feedback_parts.append("✓ Pre-existing 'initialized' intact ('true')")
    else:
        feedback_parts.append(f"✗ Pre-existing data corrupted: 'initialized'='{initialized_value}' (expected: 'true')")
    
    # Criterion 5: No unexpected keys
    expected_keys = {"theme", "language", "initialized"}
    actual_keys = set(storage_data.keys())
    extra_keys = actual_keys - expected_keys
    missing_keys = expected_keys - actual_keys
    
    if actual_keys == expected_keys:
        criteria_met += 1
        feedback_parts.append("✓ No extra keys (exactly 3 keys: theme, language, initialized)")
    else:
        if extra_keys:
            feedback_parts.append(f"⚠ Extra keys present: {sorted(extra_keys)}")
            criteria_met += 0.5  # Partial credit
        if missing_keys:
            feedback_parts.append(f"✗ Missing expected keys: {sorted(missing_keys)}")
    
    # Calculate score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 75
    
    # Build feedback
    feedback = "\n".join(feedback_parts)
    feedback += f"\n\n{'='*60}"
    feedback += f"\nCriteria met: {criteria_met:.1f}/{total_criteria}"
    feedback += f"\nFinal score: {score}%"
    feedback += f"\nResult: {'✅ PASSED' if passed else '❌ FAILED'}"
    
    # Add actual storage state
    feedback += f"\n\n📊 Actual localStorage state:"
    if storage_data:
        for key in sorted(storage_data.keys()):
            feedback += f"\n  • {key}: '{storage_data[key]}'"
    else:
        feedback += "\n  (empty)"
    
    logger.info(f"Verification complete: passed={passed}, score={score}, criteria={criteria_met}/{total_criteria}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "storage_data": storage_data,
            "criteria_met": criteria_met,
            "total_criteria": total_criteria
        }
    }
