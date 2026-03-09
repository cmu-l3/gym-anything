#!/usr/bin/env python3
"""Verifier for create_team task.

Checks that a team named 'Digital Marketing Hub' was created in the MariaDB
team_informations table.
"""

import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_create_team(traj, env_info, task_info):
    """Verify that 'Digital Marketing Hub' team was created.

    Programmatic: Query team_informations table in MariaDB.
    """
    exec_in_env = env_info.get('exec_in_env')
    if not exec_in_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "exec_in_env not available in env_info"
        }

    metadata = task_info.get('metadata', {})
    expected_team = metadata.get('expected_team_name', 'Digital Marketing Hub')

    # Query MariaDB for the team
    query = f"SELECT team_name FROM team_informations WHERE team_name = '{expected_team}' LIMIT 1"
    cmd = f'mysql -u root socioboard -N -e "{query}" 2>/dev/null'

    try:
        result = exec_in_env(cmd)
        result = result.strip() if result else ""
        logger.info(f"Team query result: {repr(result)}")
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to query database: {e}"
        }

    if expected_team in result:
        return {
            "passed": True,
            "score": 100,
            "feedback": f"Team '{expected_team}' found in database."
        }
    else:
        # Check what teams exist for better feedback
        all_cmd = "mysql -u root socioboard -N -e \"SELECT team_name FROM team_informations\" 2>/dev/null"
        try:
            all_teams = exec_in_env(all_cmd)
            all_teams = all_teams.strip() if all_teams else "(none)"
        except Exception:
            all_teams = "(query failed)"

        return {
            "passed": False,
            "score": 0,
            "feedback": f"Team '{expected_team}' not found. Existing teams: {all_teams}"
        }
