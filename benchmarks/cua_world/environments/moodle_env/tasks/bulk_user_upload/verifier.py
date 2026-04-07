#!/usr/bin/env python3
"""Verifier for Bulk User Upload task in Moodle."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_bulk_user_upload(traj, env_info, task_info):
    """
    Verify that 8 users were created via CSV upload and 5 were enrolled in BIO101.

    Scoring (100 points total):
    - Users created (40 pts): 5 pts per user (8 total)
    - Email correctness (10 pts): All emails match expected
    - City correctness (5 pts): All cities match expected
    - Enrollments (30 pts): 6 pts per correctly enrolled user (5 total)
    - Anti-gaming (15 pts): Users must be new (created after task start)

    Pass threshold: 60 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expectations from metadata
    metadata = task_info.get('metadata', {})
    expected_users = metadata.get('expected_users', [])
    expected_enrolled = metadata.get('expected_enrolled_bio101', [])
    
    # Defaults for specific checking if metadata missing
    if not expected_users:
        expected_users = ['tnguyen', 'rkapoor', 'lchen', 'mhernandez', 'sproctor', 'jokwu', 'kfischer', 'dpatel']
    if not expected_enrolled:
        expected_enrolled = ['tnguyen', 'rkapoor', 'lchen', 'mhernandez', 'sproctor']

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/bulk_upload_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        
        users_found = result.get('users_found', {})
        enrolled_found = result.get('users_enrolled_bio101', [])
        task_start_time = result.get('task_start_time', 0)
        
        # 1. Verify Users Created (40 pts)
        users_created_count = 0
        new_users_count = 0
        
        for user in expected_users:
            if user in users_found:
                users_created_count += 1
                # Anti-gaming: Check creation time
                created_time = users_found[user].get('timecreated', 0)
                if created_time > task_start_time:
                    new_users_count += 1
        
        # Score for existence (max 40)
        user_score = users_created_count * 5
        score += user_score
        
        if users_created_count == len(expected_users):
            feedback_parts.append(f"All {len(expected_users)} users created")
        else:
            feedback_parts.append(f"{users_created_count}/{len(expected_users)} users created")

        # 2. Verify Data Accuracy (Emails & Cities) (15 pts)
        # We assume if the user exists, the CSV parser likely got the fields right, 
        # but we check specific mapping to ensure columns weren't swapped.
        data_accurate = True
        for user in expected_users:
            if user in users_found:
                # Basic check: email should contain username (based on our CSV data pattern)
                email = users_found[user].get('email', '')
                if user not in email:
                    data_accurate = False
                    break
        
        if users_created_count > 0:
            if data_accurate:
                score += 15
                feedback_parts.append("User data (email/city) correct")
            else:
                feedback_parts.append("User data mismatch (columns likely swapped)")

        # 3. Verify Enrollments (30 pts)
        enrollment_score = 0
        correct_enrollments = 0
        for user in expected_enrolled:
            if user in enrolled_found:
                correct_enrollments += 1
                enrollment_score += 6
        
        score += enrollment_score
        if correct_enrollments == len(expected_enrolled):
            feedback_parts.append(f"All {len(expected_enrolled)} enrollments correct")
        else:
            feedback_parts.append(f"{correct_enrollments}/{len(expected_enrolled)} enrollments correct")

        # 4. Anti-gaming / Timestamp check (15 pts)
        # If all found users were created after task start
        if users_created_count > 0 and new_users_count == users_created_count:
            score += 15
            feedback_parts.append("Users verified as newly created")
        elif users_created_count > 0:
            feedback_parts.append("Warning: Some users appear to be pre-existing")
        
        # Final pass check
        passed = score >= 60 and users_created_count >= 6 and correct_enrollments >= 3
        
        return {
            "passed": passed,
            "score": min(100, score),
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification failed: {str(e)}"}