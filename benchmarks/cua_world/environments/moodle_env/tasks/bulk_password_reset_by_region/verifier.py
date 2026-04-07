#!/usr/bin/env python3
"""Verifier for Bulk Password Reset by Region task in Moodle."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_bulk_password_reset(traj, env_info, task_info):
    """
    Verify that Canadian users have forced password reset, and others do not.
    
    Scoring (100 points total):
    - 40 points: All Target Users (CA) have force_change = 1
    - 40 points: All Control Users (US, GB) have force_change = 0 (Safety check)
    - 20 points: At least one user was modified (prevents "do nothing" state)
    
    Pass threshold: 100 points. (Security/Compliance task requires precision)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected metadata
    metadata = task_info.get('metadata', {})
    target_users = set(metadata.get('target_users', ["liam.smith", "olivia.tremblay", "noah.gauthier"]))
    control_users = set(metadata.get('control_users', ["james.johnson", "emma.williams", "charlie.brown"]))

    try:
        # Copy result JSON
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/bulk_password_reset_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        users_data = result.get('users', [])
        
        # Convert list to dictionary for easier lookup
        user_status = {u['username']: str(u['force_change']) == '1' for u in users_data}
        
        logger.info(f"User status: {user_status}")

        score = 0
        feedback_parts = []
        
        # Check Targets (Must be True)
        targets_correct = 0
        targets_total = len(target_users)
        failed_targets = []
        
        for u in target_users:
            if user_status.get(u, False):
                targets_correct += 1
            else:
                failed_targets.append(u)
        
        if targets_correct == targets_total:
            score += 40
            feedback_parts.append(f"All {targets_total} Canadian users set to force reset")
        else:
            feedback_parts.append(f"Failed to reset {len(failed_targets)} Canadian users ({', '.join(failed_targets)})")

        # Check Controls (Must be False)
        controls_correct = 0
        controls_total = len(control_users)
        failed_controls = []
        
        for u in control_users:
            if not user_status.get(u, False):
                controls_correct += 1
            else:
                failed_controls.append(u)
                
        if controls_correct == controls_total:
            score += 40
            feedback_parts.append(f"All {controls_total} non-Canadian users safe (not reset)")
        else:
            feedback_parts.append(f"Incorrectly reset {len(failed_controls)} non-Canadian users ({', '.join(failed_controls)})")

        # Check Process (At least one modification happened)
        # This prevents scoring 40 points for doing nothing (if we split points differently)
        # But in this scheme, if you do nothing, you get 40 points for safety but 0 for targets.
        # We add 20 points explicitly for successfully changing at least one target to reinforce action.
        if targets_correct > 0:
            score += 20
        else:
            feedback_parts.append("No actions appeared to take effect")

        passed = (score == 100)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": {
                "targets_reset": targets_correct == targets_total,
                "controls_safe": controls_correct == controls_total
            }
        }

    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found - export failed"}
    except json.JSONDecodeError:
        return {"passed": False, "score": 0, "feedback": "Invalid JSON result"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}