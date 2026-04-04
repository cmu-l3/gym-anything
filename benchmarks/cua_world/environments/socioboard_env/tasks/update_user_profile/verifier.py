#!/usr/bin/env python3
"""Verifier for update_user_profile task.

Checks that the admin user's profile was updated in MariaDB user_details table
with first_name=Sarah, last_name=Connor, and about_me containing the expected text.
"""

import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_update_user_profile(traj, env_info, task_info):
    """Verify that admin profile was updated with Sarah Connor details.

    Programmatic: Query user_details table in MariaDB.
    Checks: first_name, last_name, about_me, phone fields.
    """
    exec_in_env = env_info.get('exec_in_env')
    if not exec_in_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "exec_in_env not available in env_info"
        }

    metadata = task_info.get('metadata', {})
    admin_email = "admin@socioboard.local"
    expected_first = metadata.get('expected_first_name', 'Sarah')
    expected_last = metadata.get('expected_last_name', 'Connor')
    expected_about_fragment = "Digital marketing strategist"

    # Query MariaDB for profile fields
    query = (
        f"SELECT first_name, last_name, about_me, phone_no, phone_code "
        f"FROM user_details WHERE email = '{admin_email}' LIMIT 1"
    )
    cmd = f'mysql -u root socioboard -N -B -e "{query}" 2>/dev/null'

    try:
        result = exec_in_env(cmd)
        result = result.strip() if result else ""
        logger.info(f"Profile query result: {repr(result)}")
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to query database: {e}"
        }

    if not result:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"No user found with email {admin_email}"
        }

    # Parse tab-separated result
    parts = result.split('\t')
    if len(parts) < 3:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Unexpected query result format: {repr(result)}"
        }

    first_name = parts[0].strip() if parts else ""
    last_name = parts[1].strip() if len(parts) > 1 else ""
    about_me = parts[2].strip() if len(parts) > 2 else ""
    phone_no = parts[3].strip() if len(parts) > 3 else ""

    score = 0
    feedback_parts = []

    # Check first name (25 points)
    if first_name == expected_first:
        score += 25
        feedback_parts.append(f"first_name='{first_name}' ✓")
    else:
        feedback_parts.append(f"first_name='{first_name}' (expected '{expected_first}') ✗")

    # Check last name (25 points)
    if last_name == expected_last:
        score += 25
        feedback_parts.append(f"last_name='{last_name}' ✓")
    else:
        feedback_parts.append(f"last_name='{last_name}' (expected '{expected_last}') ✗")

    # Check about_me (40 points)
    if about_me and expected_about_fragment in about_me:
        score += 40
        feedback_parts.append(f"about_me contains expected text ✓")
    else:
        feedback_parts.append(f"about_me='{about_me[:80]}' (expected to contain '{expected_about_fragment}') ✗")

    # Check phone number (10 points)
    # Task requires: +1-5550101234 (phone_code=1, phone_no=5550101234)
    expected_phone_no = metadata.get('expected_phone_no', '5550101234')
    if phone_no and expected_phone_no in phone_no:
        score += 10
        feedback_parts.append(f"phone_no='{phone_no}' ✓")
    else:
        feedback_parts.append(f"phone_no='{phone_no}' (expected '{expected_phone_no}') ✗")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }
