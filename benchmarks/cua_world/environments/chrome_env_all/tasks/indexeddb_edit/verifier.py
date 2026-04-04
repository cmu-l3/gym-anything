#!/usr/bin/env python3
"""
Verifier for Chrome IndexedDB Modification Task (indexeddb_edit@1)
Task: Use DevTools Application panel to modify IndexedDB record status

Verification Strategy:
- Uses Chrome DevTools Protocol (CDP) to query IndexedDB
- Executes JavaScript via Runtime.evaluate to access IndexedDB
- Checks if task with id=3 has status="completed"
- Validates the change was made correctly
"""

import logging
import sys
import os
import json
import tempfile
import time
from pathlib import Path

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Try to import websocket for CDP
try:
    import websocket
    HAS_WEBSOCKET = True
except ImportError:
    HAS_WEBSOCKET = False
    logger.warning("websocket-client not available, will use HTTP-only verification")

# Try to import requests
try:
    import requests
    HAS_REQUESTS = True
except ImportError:
    HAS_REQUESTS = False
    logger.warning("requests library not available")


def verify_task(traj, env_info, task_info):
    """
    Main verification function for indexeddb_edit@1.
    
    Verifies that the IndexedDB record with id=3 has been modified
    from status="pending" to status="completed".
    
    Args:
        traj: Trajectory data (not used)
        env_info: Environment information including copy_from_env
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
        # Get the task status from IndexedDB via CDP
        status, error_msg = query_indexeddb_status(copy_from_env)
        
        if status is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to query IndexedDB: {error_msg}"
            }
        
        # Verify the status change
        result = verify_status_change(status)
        
        return result
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }


def query_indexeddb_status(copy_from_env):
    """
    Query IndexedDB via CDP to get the status of task id=3.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Tuple of (status: str or None, error_msg: str)
    """
    # First, try to get WebSocket URL from exported data
    ws_url = get_websocket_url(copy_from_env)
    
    if ws_url and HAS_WEBSOCKET:
        # Use WebSocket to query IndexedDB
        status = query_via_websocket(ws_url)
        if status:
            return status, ""
    
    # Fallback: Use JavaScript execution via CDP HTTP
    if HAS_REQUESTS:
        status = query_via_javascript_execution()
        if status:
            return status, ""
    
    return None, "Could not query IndexedDB via any available method"


def get_websocket_url(copy_from_env):
    """
    Get the WebSocket debugger URL from exported data.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        WebSocket URL string or None
    """
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        temp_file.close()
        
        copy_from_env("/tmp/indexeddb_verification/websocket_url.txt", temp_file.name)
        
        with open(temp_file.name, 'r') as f:
            ws_url = f.read().strip()
        
        os.unlink(temp_file.name)
        
        if ws_url and ws_url.startswith('ws://'):
            logger.info(f"Found WebSocket URL: {ws_url[:50]}...")
            return ws_url
        
        return None
        
    except Exception as e:
        logger.warning(f"Could not get WebSocket URL: {e}")
        return None


def query_via_websocket(ws_url):
    """
    Query IndexedDB using WebSocket connection to CDP.
    
    Args:
        ws_url: WebSocket debugger URL
        
    Returns:
        Status string or None
    """
    try:
        logger.info("Connecting to CDP via WebSocket...")
        ws = websocket.create_connection(ws_url, timeout=10)
        
        # JavaScript to query IndexedDB
        js_code = """
        (function() {
            return new Promise((resolve, reject) => {
                const request = indexedDB.open('TaskManager', 1);
                request.onsuccess = (event) => {
                    const db = event.target.result;
                    const transaction = db.transaction(['tasks'], 'readonly');
                    const objectStore = transaction.objectStore('tasks');
                    const getRequest = objectStore.get(3);
                    
                    getRequest.onsuccess = () => {
                        if (getRequest.result) {
                            resolve(getRequest.result.status);
                        } else {
                            resolve('NOT_FOUND');
                        }
                    };
                    
                    getRequest.onerror = () => {
                        resolve('ERROR');
                    };
                };
                
                request.onerror = () => {
                    resolve('DB_ERROR');
                };
            });
        })()
        """
        
        # Execute JavaScript and wait for result
        msg_id = 1
        ws.send(json.dumps({
            "id": msg_id,
            "method": "Runtime.evaluate",
            "params": {
                "expression": js_code,
                "awaitPromise": True,
                "returnByValue": True
            }
        }))
        
        # Wait for response
        timeout = time.time() + 10
        while time.time() < timeout:
            try:
                response = json.loads(ws.recv())
                
                if response.get('id') == msg_id:
                    result = response.get('result', {}).get('result', {})
                    
                    if 'value' in result:
                        status = result['value']
                        logger.info(f"IndexedDB query result: {status}")
                        ws.close()
                        return status
                    
                    if 'exceptionDetails' in result:
                        logger.error(f"JavaScript execution error: {result['exceptionDetails']}")
                        ws.close()
                        return None
                        
            except websocket.WebSocketTimeoutException:
                continue
        
        ws.close()
        logger.warning("WebSocket query timed out")
        return None
        
    except Exception as e:
        logger.error(f"WebSocket query failed: {e}")
        return None


def query_via_javascript_execution():
    """
    Query IndexedDB by executing JavaScript via CDP HTTP endpoint.
    
    Returns:
        Status string or None
    """
    try:
        logger.info("Querying IndexedDB via CDP HTTP...")
        
        # Get the WebSocket URL from CDP HTTP endpoint
        response = requests.get('http://localhost:9222/json', timeout=5)
        tabs = response.json()
        
        page_tabs = [t for t in tabs if t.get('type') == 'page']
        if not page_tabs:
            logger.warning("No page tabs found")
            return None
        
        # Find the task manager tab
        task_manager_tab = None
        for tab in page_tabs:
            url = tab.get('url', '')
            if 'task_manager.html' in url:
                task_manager_tab = tab
                break
        
        if not task_manager_tab:
            # Use first page tab as fallback
            task_manager_tab = page_tabs[0]
        
        ws_url = task_manager_tab.get('webSocketDebuggerUrl')
        
        if ws_url and HAS_WEBSOCKET:
            return query_via_websocket(ws_url)
        
        logger.warning("Could not execute JavaScript query via CDP")
        return None
        
    except Exception as e:
        logger.error(f"HTTP-based query failed: {e}")
        return None


def verify_status_change(status):
    """
    Verify that the status was correctly changed.
    
    Args:
        status: Current status value from IndexedDB
        
    Returns:
        Dict with verification results
    """
    expected_status = "completed"
    initial_status = "pending"
    
    criteria_met = 0
    total_criteria = 5
    feedback_parts = []
    
    # Criterion 1: Database accessible
    if status not in ['NOT_FOUND', 'ERROR', 'DB_ERROR', None]:
        criteria_met += 1
        feedback_parts.append("✓ IndexedDB database accessible")
    else:
        feedback_parts.append("✗ IndexedDB database not accessible or query failed")
        return {
            "passed": False,
            "score": 0,
            "feedback": "\n".join(feedback_parts),
            "details": {"status": status}
        }
    
    # Criterion 2: Record with id=3 exists
    if status != 'NOT_FOUND':
        criteria_met += 1
        feedback_parts.append("✓ Task record with id=3 found in object store")
    else:
        feedback_parts.append("✗ Task record with id=3 not found")
    
    # Criterion 3: Status field has been modified
    if status != initial_status and status != 'NOT_FOUND':
        criteria_met += 1
        feedback_parts.append("✓ Status field has been modified from initial value")
    else:
        if status == initial_status:
            feedback_parts.append(f"✗ Status still '{initial_status}' - not modified")
        else:
            feedback_parts.append("✗ Status field not properly modified")
    
    # Criterion 4: Status equals expected value
    if status == expected_status:
        criteria_met += 1
        feedback_parts.append(f"✓ Status correctly set to '{expected_status}'")
    else:
        feedback_parts.append(f"✗ Status is '{status}', expected '{expected_status}'")
    
    # Criterion 5: Data integrity (status is a valid string)
    if isinstance(status, str) and len(status) > 0 and status not in ['ERROR', 'DB_ERROR']:
        criteria_met += 1
        feedback_parts.append("✓ Data integrity maintained (valid string value)")
    else:
        feedback_parts.append("⚠ Data integrity issue detected")
    
    # Calculate score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 75  # Need at least 4/5 criteria
    
    # Add summary
    feedback_parts.append("")
    feedback_parts.append("=" * 50)
    feedback_parts.append(f"Criteria met: {criteria_met}/{total_criteria}")
    feedback_parts.append(f"Final score: {score}%")
    feedback_parts.append(f"Result: {'PASSED ✓' if passed else 'FAILED ✗'}")
    
    if not passed:
        feedback_parts.append("")
        feedback_parts.append("Hint: Open DevTools (F12) → Application tab → ")
        feedback_parts.append("IndexedDB → TaskManager → tasks → ")
        feedback_parts.append("Find record with id=3 and change status to 'completed'")
    
    feedback = "\n".join(feedback_parts)
    
    logger.info(f"Verification complete: passed={passed}, score={score}, status={status}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "current_status": status,
            "expected_status": expected_status,
            "initial_status": initial_status,
            "criteria_met": criteria_met
        }
    }
