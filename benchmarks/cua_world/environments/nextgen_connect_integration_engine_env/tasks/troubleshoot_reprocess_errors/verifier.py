#!/usr/bin/env python3
"""Verifier for troubleshoot_reprocess_errors task."""

import json
import tempfile
import os

def verify_troubleshoot_reprocess_errors(traj, env_info, task_info):
    """Verify that errors were cleared, messages reprocessed, and code fixed."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_files = metadata.get('expected_total_files', 20)
    
    # Load result
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

    # Extract metrics
    channel_found = result.get('channel_found', False)
    stats_errored = result.get('stats_errored', -1)
    stats_sent = result.get('stats_sent', 0)
    output_count = result.get('output_file_count', 0)
    content_fix_verified = result.get('content_fix_verified', False)
    channel_state = result.get('channel_state', 'UNKNOWN')

    score = 0
    feedback_parts = []

    # Criterion 1: Channel State (10 pts)
    if channel_found and channel_state in ['STARTED', 'STARTING', 'RUNNING']:
        score += 10
        feedback_parts.append("Channel is running")
    else:
        feedback_parts.append(f"Channel not running (State: {channel_state})")

    # Criterion 2: Zero Errors (30 pts)
    if stats_errored == 0:
        score += 30
        feedback_parts.append("Zero errors in channel stats")
    else:
        feedback_parts.append(f"Channel still has {stats_errored} errors")

    # Criterion 3: Full Message Recovery (30 pts)
    # We expect 20 output files (10 initial + 10 reprocessed)
    if output_count >= expected_files:
        score += 30
        feedback_parts.append(f"All {output_count} messages delivered")
    elif output_count > 10:
        # Partial recovery
        score += 15
        feedback_parts.append(f"Partial recovery: {output_count} files (expected {expected_files})")
    else:
        feedback_parts.append(f"No recovery detected: {output_count} files (only initial 10?)")

    # Criterion 4: Logic Fix Verification (30 pts)
    # The output must contain "UNKNOWN" for the bad messages
    if content_fix_verified:
        score += 30
        feedback_parts.append("Defensive coding fix verified (fallback value found in output)")
    else:
        feedback_parts.append("Fix not verified: Fallback value 'UNKNOWN' not found in output files")

    passed = score >= 90
    feedback = "\n".join(feedback_parts)

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }