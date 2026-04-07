#!/usr/bin/env python3
"""
Verifier for Configure SMTP Settings task.

Verifies that the Rocket.Chat SMTP settings match the required configuration.
Uses data exported from the container via the Rocket.Chat API.
"""

import json
import os
import logging
import tempfile
import sys

# Add parent directory to path to import vlm_utils if needed in future
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_smtp_settings(traj, env_info, task_info):
    """
    Verify SMTP settings configuration.
    
    Scoring Criteria:
    1. Protocol is 'smtp' (10 pts)
    2. Host is 'smtp.internal.corp' (30 pts)
    3. Port is '2525' (30 pts)
    4. IgnoreTLS is True (30 pts)
    
    Anti-gaming:
    - Checks if settings were actually retrievable from the API.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_protocol = metadata.get('expected_protocol', 'smtp')
    expected_host = metadata.get('expected_host', 'smtp.internal.corp')
    expected_port = metadata.get('expected_port', '2525')
    expected_ignore_tls = metadata.get('expected_ignore_tls', True)

    # Copy result file from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Check if API query was successful
    if not result.get('settings_found', False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Could not verify settings: Failed to query Rocket.Chat API."
        }

    actual_values = result.get('values', {})
    
    score = 0
    feedback_parts = []
    
    # 1. Verify Protocol
    val_protocol = actual_values.get('SMTP_Protocol', '')
    if val_protocol == expected_protocol:
        score += 10
        feedback_parts.append("Protocol: Correct")
    else:
        feedback_parts.append(f"Protocol: Incorrect (Expected '{expected_protocol}', got '{val_protocol}')")

    # 2. Verify Host
    val_host = actual_values.get('SMTP_Host', '')
    if val_host == expected_host:
        score += 30
        feedback_parts.append("Host: Correct")
    else:
        feedback_parts.append(f"Host: Incorrect (Expected '{expected_host}', got '{val_host}')")

    # 3. Verify Port
    val_port = str(actual_values.get('SMTP_Port', ''))
    if val_port == str(expected_port):
        score += 30
        feedback_parts.append("Port: Correct")
    else:
        feedback_parts.append(f"Port: Incorrect (Expected '{expected_port}', got '{val_port}')")

    # 4. Verify IgnoreTLS
    # API usually returns boolean or string "true"/"false"
    val_ignore_tls = actual_values.get('SMTP_IgnoreTLS')
    
    # Normalize to boolean
    is_ignoring_tls = False
    if isinstance(val_ignore_tls, bool):
        is_ignoring_tls = val_ignore_tls
    elif isinstance(val_ignore_tls, str):
        is_ignoring_tls = val_ignore_tls.lower() == 'true'
        
    if is_ignoring_tls == expected_ignore_tls:
        score += 30
        feedback_parts.append("IgnoreTLS: Correct")
    else:
        feedback_parts.append(f"IgnoreTLS: Incorrect (Expected {expected_ignore_tls}, got {is_ignoring_tls})")

    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }