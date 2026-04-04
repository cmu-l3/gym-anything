#!/usr/bin/env python3
"""
Verifier for configure_backup task.
Verifies that the backup configuration exists in Artifactory's system config.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_backup(traj, env_info, task_info):
    """
    Verify the backup configuration.
    
    Criteria:
    1. Backup entry with key 'nightly-backup' exists (30 pts)
    2. Cron expression is '0 0 2 * * ?' (20 pts)
    3. Retention period is 168 hours (10 pts)
    4. Backup is enabled (15 pts)
    5. VLM verification of UI (15 pts) - Optional fallback or bonus, 
       but here we stick to programmatically verifying the config for robustness.
       We'll allocate points primarily to the config correctness.
    
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    expected_key = metadata.get('expected_key', 'nightly-backup')
    expected_cron = metadata.get('expected_cron', '0 0 2 * * ?')
    expected_retention = metadata.get('expected_retention_hours', 168)

    # Read result from container
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
    
    # Check if config was retrieved
    if not result.get('config_retrieved', False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Failed to retrieve Artifactory configuration for verification"
        }

    backups = result.get('backups', [])
    target_backup = next((b for b in backups if b.get('key') == expected_key), None)

    # Criterion 1: Backup exists
    if target_backup:
        score += 40
        feedback_parts.append(f"Backup '{expected_key}' created")
        
        # Criterion 2: Cron expression
        actual_cron = target_backup.get('cronExp', '')
        if actual_cron == expected_cron:
            score += 25
            feedback_parts.append(f"Cron expression correct ({expected_cron})")
        else:
            feedback_parts.append(f"Cron expression incorrect (expected '{expected_cron}', got '{actual_cron}')")

        # Criterion 3: Retention
        actual_retention = target_backup.get('retentionPeriodHours', 0)
        if actual_retention == expected_retention:
            score += 20
            feedback_parts.append(f"Retention period correct ({expected_retention} hours)")
        else:
            feedback_parts.append(f"Retention period incorrect (expected {expected_retention}, got {actual_retention})")

        # Criterion 4: Enabled
        if target_backup.get('enabled', False):
            score += 15
            feedback_parts.append("Backup is enabled")
        else:
            feedback_parts.append("Backup is DISABLED")

    else:
        feedback_parts.append(f"Backup '{expected_key}' NOT found in configuration")

    # Pass threshold
    passed = score >= 60 and target_backup is not None

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }