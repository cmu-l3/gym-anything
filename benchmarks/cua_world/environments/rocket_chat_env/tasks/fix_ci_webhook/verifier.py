#!/usr/bin/env python3
"""
Verifier for fix_ci_webhook task.

Verifies:
1. Target integration 'channel' was updated to `#build-alerts`.
2. Target integration 'username' was updated to `build-bot`.
3. Validates functional repair by asserting that an integration message from `build-bot` was posted to `#build-alerts`.
"""

import os
import json
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_fix_ci_webhook(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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

    # Criterion 1: Target Channel Fixed (40 pts)
    webhook_channel = result.get("webhook_channel", "")
    if webhook_channel in ["#build-alerts", "build-alerts"]:
        score += 40
        feedback_parts.append("Channel correctly updated to #build-alerts")
    elif webhook_channel:
        feedback_parts.append(f"Channel is {webhook_channel}, expected #build-alerts")
    else:
        feedback_parts.append("Integration 'CI Notification Bot' not found or channel empty")

    # Criterion 2: Bot Identity Fixed (30 pts)
    webhook_username = result.get("webhook_username", "")
    if webhook_username == "build-bot":
        score += 30
        feedback_parts.append("Username correctly updated to build-bot")
    elif webhook_username:
        feedback_parts.append(f"Username is {webhook_username}, expected build-bot")
    
    # Criterion 3: Functional Verification (30 pts)
    # The agent must prove they fixed it by making a terminal curl request resulting in a message inside #build-alerts
    test_msg_count = result.get("test_message_count", 0)
    if test_msg_count > 0:
        score += 30
        feedback_parts.append(f"Test message successfully received in #build-alerts ({test_msg_count} found)")
    else:
        feedback_parts.append("No test message from build-bot found in #build-alerts")

    # Pass threshold: Agent must at least fix the config, though testing is highly recommended.
    # 70 pts guarantees both configs were fixed OR one config + functional test (partial fix + test).
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }