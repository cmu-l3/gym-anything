#!/usr/bin/env python3
"""Verifier for add_team_member task.

Checks that john.smith@socioboard.local was invited to the 'Content Strategy Team'
by querying the join_table_users_teams table in MariaDB.
"""

import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_add_team_member(traj, env_info, task_info):
    """Verify that John Smith was added as a member of Content Strategy Team.

    Programmatic: Query join_table_users_teams table via MariaDB.
    Accepts either invitation_accepted=0 (pending) or invitation_accepted=1 (accepted).
    """
    exec_in_env = env_info.get('exec_in_env')
    if not exec_in_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "exec_in_env not available in env_info"
        }

    metadata = task_info.get('metadata', {})
    team_name = metadata.get('team_name', 'Content Strategy Team')
    member_email = metadata.get('member_email', 'john.smith@socioboard.local')

    # Query: Is john.smith in Content Strategy Team?
    query = (
        f"SELECT jt.invitation_accepted, jt.user_id "
        f"FROM join_table_users_teams jt "
        f"JOIN team_informations ti ON jt.team_id = ti.team_id "
        f"JOIN user_details ud ON jt.user_id = ud.user_id "
        f"WHERE ti.team_name = '{team_name}' "
        f"AND ud.email = '{member_email}' "
        f"LIMIT 1"
    )
    cmd = f'mysql -u root socioboard -N -B -e "{query}" 2>/dev/null'

    try:
        result = exec_in_env(cmd)
        result = result.strip() if result else ""
        logger.info(f"Team member query result: {repr(result)}")
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to query database: {e}"
        }

    if result:
        parts = result.split('\t')
        invitation_accepted = parts[0].strip() if parts else "0"
        status = "accepted" if invitation_accepted == "1" else "pending (invitation sent)"
        return {
            "passed": True,
            "score": 100,
            "feedback": (
                f"'{member_email}' is a member of '{team_name}' "
                f"(status: {status})."
            )
        }
    else:
        # Get existing members for feedback
        members_cmd = (
            f'mysql -u root socioboard -N -e '
            f'"SELECT ud.email FROM join_table_users_teams jt '
            f'JOIN team_informations ti ON jt.team_id = ti.team_id '
            f'JOIN user_details ud ON jt.user_id = ud.user_id '
            f'WHERE ti.team_name = \'{team_name}\'" 2>/dev/null'
        )
        try:
            members = exec_in_env(members_cmd)
            members = members.strip() if members else "(none)"
        except Exception:
            members = "(query failed)"

        # Also check if team exists
        team_check_cmd = (
            f'mysql -u root socioboard -N -e '
            f'"SELECT team_name FROM team_informations WHERE team_name = \'{team_name}\'" 2>/dev/null'
        )
        try:
            team_result = exec_in_env(team_check_cmd)
            team_exists = bool(team_result and team_result.strip())
        except Exception:
            team_exists = False

        if not team_exists:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Team '{team_name}' does not exist in the database."
            }

        return {
            "passed": False,
            "score": 0,
            "feedback": (
                f"'{member_email}' is not a member of '{team_name}'. "
                f"Current members: {members}"
            )
        }
