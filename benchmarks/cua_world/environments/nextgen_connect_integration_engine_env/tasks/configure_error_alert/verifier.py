#!/usr/bin/env python3
"""Verifier for configure_error_alert task."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_configure_error_alert(traj, env_info, task_info):
    """
    Verify that an error monitoring alert was created with specific configuration.

    Criteria:
    1. Alert exists with name 'ADT Critical Error Monitor' (20 pts)
    2. Alert is enabled (10 pts)
    3. Monitors the correct channel (20 pts)
    4. Configured for SOURCE/DESTINATION error types (15 pts)
    5. Regex pattern configured (10 pts)
    6. Action group subject contains 'ADT' (10 pts)
    7. Action group template contains '${error}' (5 pts)
    8. Action group has at least one recipient (5 pts)
    9. Anti-gaming: Alert created during task (5 pts)

    Pass threshold: 60 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file
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

    # Extract data
    alert_found = result.get('alert_found', False)
    alert_name = result.get('alert_name', '')
    alert_enabled = result.get('alert_enabled', False)
    monitored_ids = result.get('channel_ids_monitored', [])
    error_types = result.get('error_event_types', [])
    regex = result.get('regex_pattern', '')
    action_subject = result.get('action_subject', '')
    action_template = result.get('action_template', '')
    recipients = result.get('action_recipients', [])
    target_channel_id = result.get('target_channel_id', '')
    total_alerts = result.get('total_alerts', 0)
    initial_alerts = result.get('initial_alert_count', 0)

    score = 0
    feedback_parts = []

    # Criterion 1: Alert Name (20 pts)
    if alert_found:
        if alert_name == "ADT Critical Error Monitor":
            score += 20
            feedback_parts.append(f"Alert found with exact name: '{alert_name}'")
        else:
            score += 10
            feedback_parts.append(f"Alert found but name mismatch: '{alert_name}'")
    else:
        feedback_parts.append("Alert 'ADT Critical Error Monitor' not found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: Enabled (10 pts)
    if alert_enabled:
        score += 10
        feedback_parts.append("Alert is enabled")
    else:
        feedback_parts.append("Alert is disabled")

    # Criterion 3: Monitored Channel (20 pts)
    if target_channel_id in monitored_ids:
        score += 20
        feedback_parts.append("Monitors correct channel")
    elif monitored_ids:
        # Partial credit if they monitored *something* but not the right one
        score += 5
        feedback_parts.append(f"Monitors wrong channel(s): {monitored_ids}")
    else:
        feedback_parts.append("No channels monitored")

    # Criterion 4: Error Event Types (15 pts)
    has_source = any('SOURCE_CONNECTOR' in et for et in error_types)
    has_dest = any('DESTINATION_CONNECTOR' in et for et in error_types)
    
    if has_source and has_dest:
        score += 15
        feedback_parts.append("Error types configured correctly")
    elif has_source or has_dest:
        score += 8
        feedback_parts.append(f"Partial error types: {error_types}")
    else:
        feedback_parts.append("Missing required error event types")

    # Criterion 5: Regex (10 pts)
    if regex:
        score += 10
        feedback_parts.append(f"Regex configured: '{regex}'")
    else:
        feedback_parts.append("No regex pattern configured")

    # Criterion 6: Action Subject (10 pts)
    if 'ADT' in action_subject:
        score += 10
        feedback_parts.append("Subject contains 'ADT'")
    elif action_subject:
        score += 5
        feedback_parts.append(f"Subject missing 'ADT': '{action_subject}'")
    else:
        feedback_parts.append("No action subject configured")

    # Criterion 7: Action Template (5 pts)
    if '${error}' in action_template:
        score += 5
        feedback_parts.append("Template contains ${error}")
    else:
        feedback_parts.append("Template missing ${error}")

    # Criterion 8: Recipient (5 pts)
    if len(recipients) > 0:
        score += 5
        feedback_parts.append(f"Recipient configured: {recipients[0].get('recipient')}")
    else:
        feedback_parts.append("No recipients configured")

    # Criterion 9: Anti-gaming (5 pts)
    if total_alerts > initial_alerts:
        score += 5
        feedback_parts.append("New alert created during task")
    else:
        # If alert found but count didn't increase, they might have edited an existing one (unlikely given setup clears them)
        # or there's a counting issue. We'll give partial if alert is found.
        feedback_parts.append("Alert count did not increase")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }