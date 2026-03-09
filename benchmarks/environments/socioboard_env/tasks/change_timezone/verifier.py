#!/usr/bin/env python3
"""Verifier for change_timezone task.

Checks that the admin user's time_zone was updated in MariaDB user_details
to the expected timezone (America/New_York).
"""

import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_change_timezone(traj, env_info, task_info):
    """Verify that admin's timezone was changed to America/New_York.

    Programmatic: Query user_details.time_zone in MariaDB.
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
    expected_tz = metadata.get('expected_timezone', 'America/New_York')

    # Query MariaDB for time_zone
    query = f"SELECT time_zone FROM user_details WHERE email = '{admin_email}' LIMIT 1"
    cmd = f'mysql -u root socioboard -N -e "{query}" 2>/dev/null'

    try:
        result = exec_in_env(cmd)
        result = result.strip() if result else ""
        logger.info(f"Timezone query result: {repr(result)}")
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to query database: {e}"
        }

    if result == expected_tz:
        return {
            "passed": True,
            "score": 100,
            "feedback": f"Timezone correctly set to '{expected_tz}'."
        }
    elif result:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Timezone is '{result}' but expected '{expected_tz}'."
        }
    else:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Timezone not set (NULL or empty). Expected '{expected_tz}'."
        }
