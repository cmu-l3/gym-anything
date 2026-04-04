#!/usr/bin/env python3
"""
Verifier for Configure Custom Workspace task.
"""

import json
import logging
import tempfile
import os

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_custom_workspace(traj, env_info, task_info):
    """
    Verify that the job was configured with a custom workspace and a build was run.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_ws = metadata.get('expected_workspace', '/tmp/legacy_ws')

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/custom_workspace_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        
        # Criterion 1: Configuration (40 points)
        configured_ws = result.get('config', {}).get('custom_workspace', '').strip()
        if configured_ws == expected_ws:
            score += 40
            feedback_parts.append(f"Configuration correct: '{expected_ws}' set")
        elif configured_ws:
            score += 10 # Partial credit for finding the setting
            feedback_parts.append(f"Wrong path set: '{configured_ws}' (expected '{expected_ws}')")
        else:
            feedback_parts.append("Custom workspace not configured in job")

        # Criterion 2: Build Execution (30 points)
        build_data = result.get('build', {})
        if build_data.get('triggered', False):
            if build_data.get('result') == 'SUCCESS':
                score += 30
                feedback_parts.append("Build ran successfully")
            else:
                score += 15
                feedback_parts.append(f"Build ran but status is {build_data.get('result')}")
        else:
            feedback_parts.append("No new build triggered")

        # Criterion 3: Log Verification (15 points)
        if build_data.get('log_match', False):
            score += 15
            feedback_parts.append("Log confirms usage of custom workspace")
        else:
            feedback_parts.append("Log does not show custom workspace usage")

        # Criterion 4: Filesystem Proof (15 points) - Anti-gaming
        fs_data = result.get('filesystem', {})
        if fs_data.get('exists', False) and fs_data.get('has_files', False):
            score += 15
            feedback_parts.append("Workspace directory verified on disk")
        elif fs_data.get('exists', False):
            score += 5
            feedback_parts.append("Directory exists but is empty")
        else:
            feedback_parts.append("Workspace directory not found on disk")

        passed = score >= 70
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Verification failed: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}