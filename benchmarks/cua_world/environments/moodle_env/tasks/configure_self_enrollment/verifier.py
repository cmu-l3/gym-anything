#!/usr/bin/env python3
"""Verifier for Configure Self Enrollment task in Moodle."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_configure_self_enrollment(traj, env_info, task_info):
    """
    Verify that self-enrollment is correctly configured for CHEM101.

    Scoring (100 points):
    - Self-enrollment enabled (25 pts)
    - Enrollment key correct (25 pts)
    - Max users correct (20 pts)
    - Duration correct (15 pts)
    - Custom instance name correct (15 pts)

    Pass threshold: 50 points (Must include enabled + key correct)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_key = metadata.get('expected_password', 'ChemFall2025')
    expected_name = metadata.get('expected_instance_name', 'Lab Safety Self-Enrollment')
    expected_max = int(metadata.get('expected_max_users', 30))
    expected_duration = int(metadata.get('expected_duration_seconds', 15552000))

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/configure_self_enrollment_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        instances = result.get('instances', [])
        
        if not instances:
            return {
                "passed": False,
                "score": 0,
                "feedback": "No self-enrollment method found on the course."
            }

        # Check if ANY instance meets the criteria
        # We calculate the best score across all instances
        best_score = 0
        best_feedback = "No valid configuration found."
        best_subscores = {}

        for inst in instances:
            current_score = 0
            current_feedback = []
            subscores = {}
            
            # 1. Enabled (status=0) - 25 pts
            status = str(inst.get('status', '1'))
            if status == '0':
                current_score += 25
                subscores['enabled'] = True
                current_feedback.append("Method enabled")
            else:
                subscores['enabled'] = False
                current_feedback.append("Method disabled (eye closed)")

            # 2. Key correct - 25 pts
            password = inst.get('password', '')
            if password == expected_key:
                current_score += 25
                subscores['key_correct'] = True
                current_feedback.append("Enrollment key correct")
            else:
                subscores['key_correct'] = False
                current_feedback.append(f"Wrong key: '{password}'")

            # 3. Max users - 20 pts
            try:
                max_users = int(inst.get('max_users', 0))
            except:
                max_users = 0
            
            if max_users == expected_max:
                current_score += 20
                subscores['max_users_correct'] = True
                current_feedback.append("Max users correct")
            else:
                subscores['max_users_correct'] = False
                current_feedback.append(f"Max users mismatch: {max_users}")

            # 4. Duration - 15 pts
            try:
                duration = int(inst.get('duration', 0))
            except:
                duration = 0
            
            # Allow small tolerance if agent sets date manually vs duration? 
            # Moodle UI sets duration in seconds.
            if duration == expected_duration:
                current_score += 15
                subscores['duration_correct'] = True
                current_feedback.append("Duration correct (180 days)")
            elif duration > 0:
                subscores['duration_correct'] = False
                current_feedback.append(f"Duration mismatch: {duration}s")
            else:
                subscores['duration_correct'] = False
                current_feedback.append("Duration not set")

            # 5. Name - 15 pts
            name = inst.get('name', '')
            if expected_name.lower() in name.lower():
                current_score += 15
                subscores['name_correct'] = True
                current_feedback.append("Instance name correct")
            else:
                subscores['name_correct'] = False
                current_feedback.append(f"Name mismatch: '{name}'")

            if current_score > best_score:
                best_score = current_score
                best_feedback = " | ".join(current_feedback)
                best_subscores = subscores

        # Pass logic: Must have enabled + key correct (50 pts threshold usually implies these basics)
        # Actually, let's enforce threshold strictness
        passed = (best_score >= 50 and 
                  best_subscores.get('enabled', False) and 
                  best_subscores.get('key_correct', False))

        return {
            "passed": passed,
            "score": best_score,
            "feedback": best_feedback,
            "subscores": best_subscores
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification failed: {str(e)}"}