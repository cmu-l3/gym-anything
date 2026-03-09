#!/usr/bin/env python3
"""
Verifier for Install & Configure Plugin task.
Verifies that the Timestamper plugin is installed, the job is configured, and output has timestamps.
"""

import json
import os
import sys
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_install_configure_plugin(traj, env_info, task_info):
    """
    Verify the agent installed the plugin, configured the job, and verified output.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    max_score = 100

    # Criterion 1: Plugin Installed (30 pts)
    plugin_installed = result.get("plugin_installed", False)
    plugin_active = result.get("plugin_active", False)
    plugin_pre_installed = result.get("plugin_pre_installed", False)

    if plugin_pre_installed:
        feedback_parts.append("Warning: Plugin was already installed before task (Environment Issue).")
        # In a real eval, we might zero this out, but for robustness we accept if active
        if plugin_active:
            score += 30
    else:
        if plugin_installed and plugin_active:
            score += 30
            feedback_parts.append("Timestamper plugin installed and active (30/30)")
        elif plugin_installed:
            score += 15
            feedback_parts.append("Timestamper plugin installed but NOT active (15/30)")
        else:
            feedback_parts.append("Timestamper plugin NOT found (-30)")

    # Criterion 2: Job Configuration (30 pts)
    config_has_timestamp = result.get("config_has_timestamp", False)
    config_changed = result.get("config_changed", False)

    if config_has_timestamp:
        score += 30
        feedback_parts.append("Job configuration enables timestamps (30/30)")
    else:
        feedback_parts.append("Job configuration missing timestamp wrapper (-30)")

    if not config_changed and not plugin_pre_installed:
         feedback_parts.append("(Note: Job config did not change, likely failed)")

    # Criterion 3: Build Execution (20 pts)
    build_completed = result.get("build_completed", False)
    build_valid_time = result.get("build_timestamp_valid", False)

    if build_completed and build_valid_time:
        score += 20
        feedback_parts.append("Build executed successfully during task (20/20)")
    elif build_completed:
        score += 5
        feedback_parts.append("Build found, but timestamp indicates it was pre-task (5/20)")
    else:
        feedback_parts.append("No valid build completed (-20)")

    # Criterion 4: Console Output Verification (20 pts)
    console_has_timestamps = result.get("console_has_timestamps", False)
    
    if console_has_timestamps:
        score += 20
        feedback_parts.append("Timestamps confirmed in console output (20/20)")
    else:
        feedback_parts.append("Timestamps NOT found in console output (-20)")

    # Final Check
    passed = (score >= 60) and plugin_active and config_has_timestamp
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }