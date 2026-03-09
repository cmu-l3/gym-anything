#!/usr/bin/env python3
"""
Verifier for configure_smtp_relay task.

VERIFICATION CRITERIA:
1. relayhost matches smtp.secure-relay.com:587 (30 pts)
2. smtp_sasl_auth_enable is yes (25 pts)
3. Password map file exists and is configured (15 pts)
4. Password map contains correct username and password (20 pts)
5. Postfix service is running (10 pts)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_smtp_relay(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    expected_relay = metadata.get('expected_relayhost', 'smtp.secure-relay.com')
    expected_port = metadata.get('expected_port', '587')
    expected_user = metadata.get('expected_user', 'relay_transport')
    expected_pass = metadata.get('expected_pass', 'SecureRoute99!')

    # Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Verify Relay Host (30 pts)
    # Accept format: host:port or [host]:port
    actual_relay = result.get('relayhost_value', '').strip()
    target_str_1 = f"{expected_relay}:{expected_port}"
    target_str_2 = f"[{expected_relay}]:{expected_port}"
    
    if target_str_1 in actual_relay or target_str_2 in actual_relay:
        score += 30
        feedback_parts.append("Relay host configured correctly")
    elif expected_relay in actual_relay and expected_port in actual_relay:
        # Partial credit if slightly malformed but contains both
        score += 15
        feedback_parts.append("Relay host matches but format might be slightly off")
    else:
        feedback_parts.append(f"Relay host incorrect (Found: {actual_relay})")

    # 2. Verify SASL Enabled (25 pts)
    sasl_enabled = result.get('sasl_enable_value', '').lower()
    if sasl_enabled == 'yes':
        score += 25
        feedback_parts.append("SASL authentication enabled")
    else:
        feedback_parts.append("SASL authentication NOT enabled")

    # 3. Verify Map File Configuration (15 pts)
    maps_config = result.get('sasl_maps_value', '')
    map_exists = result.get('map_file_exists', False)
    
    if maps_config and map_exists:
        score += 15
        feedback_parts.append("Password map file configured and exists")
    elif maps_config:
        score += 5
        feedback_parts.append("Password map configured but file missing")
    else:
        feedback_parts.append("No password map configured")

    # 4. Verify Map Content (20 pts)
    # Check if username and password appear in the file content
    content = result.get('map_file_content', '')
    if expected_user in content and expected_pass in content:
        score += 20
        feedback_parts.append("Credentials found in map file")
    elif expected_user in content:
        score += 10
        feedback_parts.append("Username found but password missing/wrong")
    else:
        if map_exists:
            feedback_parts.append("Credentials NOT found in map file")

    # 5. Verify Postfix Running (10 pts)
    if result.get('postfix_running', False):
        score += 10
        feedback_parts.append("Postfix is running")
    else:
        feedback_parts.append("Postfix service is NOT running")

    # Check for anti-gaming: Map file modified during task
    if map_exists and not result.get('map_file_modified', False):
        feedback_parts.append("(Warning: Password file not modified during task time)")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }