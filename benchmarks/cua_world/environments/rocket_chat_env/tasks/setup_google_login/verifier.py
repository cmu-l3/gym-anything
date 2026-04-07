#!/usr/bin/env python3
"""
Verifier for setup_google_login task.

Verifies:
1. Google OAuth is Enabled (True).
2. Client ID matches exactly.
3. Client Secret matches exactly.
4. Settings were updated AFTER task start time (anti-gaming).
"""

import json
import logging
import os
import tempfile
from datetime import datetime
from dateutil import parser as date_parser

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_setup_google_login(traj, env_info, task_info):
    """
    Verify that Google OAuth was correctly configured in Rocket.Chat.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_id = metadata.get('expected_id_value', '49204819204-novatech.apps.googleusercontent.com')
    expected_secret = metadata.get('expected_secret_value', 'GOCSPX-NovaTechSecretKey2026')

    # Copy result file from container
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

    # Basic checks
    if not result.get("api_access", False):
        return {"passed": False, "score": 0, "feedback": "Could not access Rocket.Chat API to verify settings."}

    settings = result.get("settings", {})
    task_start_ts = result.get("task_start", 0)

    # Helper to parse Rocket.Chat setting objects
    def get_val(setting_obj):
        return setting_obj.get("value")

    def get_updated_at(setting_obj):
        ts_str = setting_obj.get("_updatedAt")
        if not ts_str:
            return 0
        try:
            # Parse ISO string to timestamp
            dt = date_parser.parse(ts_str)
            return dt.timestamp()
        except:
            return 0

    # Retrieve values
    enable_obj = settings.get("enable", {})
    id_obj = settings.get("id", {})
    secret_obj = settings.get("secret", {})

    actual_enable = get_val(enable_obj)
    actual_id = get_val(id_obj)
    actual_secret = get_val(secret_obj)

    # Check timestamps (Anti-gaming)
    # We check if ANY of the settings were updated during the task
    # Note: Rocket.Chat updates timestamp even if value doesn't change if "Save" is clicked,
    # but strictly we want to see if they were modified recently.
    updated_timestamps = [
        get_updated_at(enable_obj),
        get_updated_at(id_obj),
        get_updated_at(secret_obj)
    ]
    max_update_ts = max(updated_timestamps) if updated_timestamps else 0

    was_updated_during_task = max_update_ts > task_start_ts

    # Scoring
    score = 0
    feedback = []

    # Criterion 1: Enabled (30 pts)
    if actual_enable is True:
        score += 30
        feedback.append("Google OAuth enabled")
    else:
        feedback.append(f"Google OAuth NOT enabled (current: {actual_enable})")

    # Criterion 2: Client ID (30 pts)
    if actual_id == expected_id:
        score += 30
        feedback.append("Client ID correct")
    else:
        # Mask actual for security/brevity in logs
        masked_actual = str(actual_id)[:5] + "..." if actual_id else "empty"
        feedback.append(f"Client ID incorrect")

    # Criterion 3: Client Secret (30 pts)
    if actual_secret == expected_secret:
        score += 30
        feedback.append("Client Secret correct")
    else:
        feedback.append("Client Secret incorrect")

    # Criterion 4: Persistence/Saved (10 pts)
    # We check if the update timestamp is valid and recent
    if was_updated_during_task:
        score += 10
        feedback.append("Settings saved during task")
    else:
        feedback.append("Settings not modified during task session (timestamps too old)")

    passed = (score == 100)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }