#!/usr/bin/env python3
"""
Verifier for update_default_channels task.

Criteria:
1. Channel 'announcements' exists (20 pts)
2. Channel is Read-Only (20 pts)
3. Channel topic matches expected text (10 pts)
4. 'announcements' is in Default_Channels setting (25 pts)
5. 'general' is NOT in Default_Channels setting (25 pts)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_update_default_channels(traj, env_info, task_info):
    """
    Verify the agent correctly configured the announcements channel and default channel settings.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_channel = metadata.get('target_channel_name', 'announcements')
    expected_topic = metadata.get('target_topic', 'Official company news and updates')
    channel_to_remove = metadata.get('channel_to_remove', 'general')

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

    score = 0
    feedback_parts = []
    
    # 1. Verify Channel Existence (20 pts)
    channel_exists = result.get('channel_exists', False)
    if channel_exists:
        score += 20
        feedback_parts.append(f"Channel '{expected_channel}' created")
    else:
        feedback_parts.append(f"Channel '{expected_channel}' NOT found")
        # Critical failure, but we continue to check other settings just in case
        
    # 2. Verify Read-Only Status (20 pts)
    # The JSON bool might be actual boolean or string "true" depending on jq output
    is_ro = result.get('channel_ro')
    if is_ro is True or str(is_ro).lower() == 'true':
        score += 20
        feedback_parts.append("Read-only mode enabled")
    elif channel_exists:
        feedback_parts.append("Channel is NOT read-only")
        
    # 3. Verify Topic (10 pts)
    actual_topic = result.get('channel_topic', '')
    if actual_topic == expected_topic:
        score += 10
        feedback_parts.append("Topic matches")
    elif channel_exists:
        feedback_parts.append(f"Topic mismatch: got '{actual_topic}'")

    # Parse Default Channels Setting
    # The value is a comma-separated string, e.g., "announcements,random"
    default_channels_str = result.get('default_channels_value', '')
    default_channels_list = [c.strip() for c in default_channels_str.split(',') if c.strip()]
    
    # 4. Verify 'announcements' added (25 pts)
    if expected_channel in default_channels_list:
        score += 25
        feedback_parts.append(f"'{expected_channel}' added to defaults")
    else:
        feedback_parts.append(f"'{expected_channel}' missing from defaults")
        
    # 5. Verify 'general' removed (25 pts)
    if channel_to_remove not in default_channels_list:
        score += 25
        feedback_parts.append(f"'{channel_to_remove}' removed from defaults")
    else:
        feedback_parts.append(f"'{channel_to_remove}' still in defaults")

    # Anti-gaming: Check if channel was created during task
    task_start = result.get('task_start', 0)
    channel_created = result.get('channel_created_at', 0)
    
    # If channel claims to exist but timestamp is old or 0 (and it wasn't pre-existing because we deleted it),
    # that's suspicious, but we rely mainly on the fact that setup deleted it.
    # If channel_created < task_start, it implies it wasn't deleted or was created too early.
    # However, since setup script deletes it, existence implies creation.
    # We'll just trust the existence check + setup script logic here.

    passed = (score >= 70)

    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }