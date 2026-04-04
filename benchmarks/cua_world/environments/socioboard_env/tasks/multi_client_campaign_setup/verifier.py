#!/usr/bin/env python3
"""Verifier for multi_client_campaign_setup task.

Marketing Manager scenario: update profile, create 4 teams,
selectively invite john.smith, add RSS feed. Contaminator teams
must remain untouched.

Scoring (100 points):
- Profile first_name (5), last_name (5), about_me fragment 1 (5),
  about_me fragment 2 (5), timezone (5), phone (5) = 30 pts
- Team existence: 4 teams × 8 pts = 32 pts
- john.smith in correct teams: 2 × 7 pts = 14 pts
- john.smith NOT in excluded teams: 2 × 4 pts = 8 pts
- Contaminator teams untouched: 2 × 3 pts = 6 pts
- RSS feed accessed: 10 pts
Total: 100 pts. Pass threshold: 60.
"""

import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def _query(exec_in_env, sql):
    """Run a MySQL query and return stripped result."""
    cmd = f'mysql -u root socioboard -N -B -e "{sql}" 2>/dev/null'
    try:
        result = exec_in_env(cmd)
        return result.strip() if result else ""
    except Exception as e:
        logger.warning(f"Query failed: {e}")
        return ""


def verify_multi_client_campaign_setup(traj, env_info, task_info):
    exec_in_env = env_info.get('exec_in_env')
    if not exec_in_env:
        return {"passed": False, "score": 0, "feedback": "exec_in_env not available"}

    metadata = task_info.get('metadata', {})
    score = 0
    feedback = []

    # ================================================================
    # 1. Profile checks (30 pts)
    # ================================================================
    profile = _query(exec_in_env,
        "SELECT first_name, last_name, about_me, phone_no, phone_code, time_zone "
        "FROM user_details WHERE email = 'admin@socioboard.local' LIMIT 1")

    if not profile:
        return {"passed": False, "score": 0, "feedback": "Admin user not found in DB"}

    parts = profile.split('\t')
    first_name = parts[0].strip() if len(parts) > 0 else ""
    last_name = parts[1].strip() if len(parts) > 1 else ""
    about_me = parts[2].strip() if len(parts) > 2 else ""
    phone_no = parts[3].strip() if len(parts) > 3 else ""
    phone_code = parts[4].strip() if len(parts) > 4 else ""
    timezone = parts[5].strip() if len(parts) > 5 else ""

    exp_first = metadata.get('expected_first_name', 'Rebecca')
    exp_last = metadata.get('expected_last_name', 'Torres')
    exp_about1 = metadata.get('expected_about_fragment', 'Pinnacle Digital Agency')
    exp_about2 = metadata.get('expected_about_fragment_2', 'B2B technology')
    exp_tz = metadata.get('expected_timezone', 'Europe/London')
    exp_phone = metadata.get('expected_phone', '7911234567')

    if first_name == exp_first:
        score += 5; feedback.append(f"first_name='{first_name}' OK")
    else:
        feedback.append(f"first_name='{first_name}' (expected '{exp_first}')")

    if last_name == exp_last:
        score += 5; feedback.append(f"last_name='{last_name}' OK")
    else:
        feedback.append(f"last_name='{last_name}' (expected '{exp_last}')")

    if exp_about1 in about_me:
        score += 5; feedback.append("about_me contains agency name OK")
    else:
        feedback.append(f"about_me missing '{exp_about1}'")

    if exp_about2.lower() in about_me.lower():
        score += 5; feedback.append("about_me contains specialization OK")
    else:
        feedback.append(f"about_me missing '{exp_about2}'")

    if timezone == exp_tz:
        score += 5; feedback.append(f"timezone='{timezone}' OK")
    else:
        feedback.append(f"timezone='{timezone}' (expected '{exp_tz}')")

    if exp_phone in phone_no:
        score += 5; feedback.append(f"phone OK")
    else:
        feedback.append(f"phone='{phone_no}' (expected contains '{exp_phone}')")

    # ================================================================
    # 2. Team existence (32 pts)
    # ================================================================
    required_teams = metadata.get('teams', [])
    for team_name in required_teams:
        exists = _query(exec_in_env,
            f"SELECT COUNT(*) FROM team_informations WHERE team_name = '{team_name}'")
        if exists and int(exists) > 0:
            score += 8; feedback.append(f"Team '{team_name}' exists")
        else:
            feedback.append(f"Team '{team_name}' MISSING")

    # ================================================================
    # 3. john.smith membership - correct teams (14 pts)
    # ================================================================
    member_email = metadata.get('member_email', 'john.smith@socioboard.local')
    for team_name in metadata.get('john_smith_teams', []):
        member_check = _query(exec_in_env,
            f"SELECT COUNT(*) FROM join_table_users_teams jt "
            f"JOIN team_informations ti ON jt.team_id = ti.team_id "
            f"JOIN user_details ud ON jt.user_id = ud.user_id "
            f"WHERE ti.team_name = '{team_name}' "
            f"AND ud.email = '{member_email}'")
        if member_check and int(member_check) > 0:
            score += 7; feedback.append(f"john.smith in '{team_name}' OK")
        else:
            feedback.append(f"john.smith NOT in '{team_name}'")

    # ================================================================
    # 4. john.smith NOT in excluded teams (8 pts)
    # ================================================================
    for team_name in metadata.get('john_smith_excluded_teams', []):
        member_check = _query(exec_in_env,
            f"SELECT COUNT(*) FROM join_table_users_teams jt "
            f"JOIN team_informations ti ON jt.team_id = ti.team_id "
            f"JOIN user_details ud ON jt.user_id = ud.user_id "
            f"WHERE ti.team_name = '{team_name}' "
            f"AND ud.email = '{member_email}'")
        if not member_check or int(member_check) == 0:
            score += 4; feedback.append(f"john.smith correctly NOT in '{team_name}'")
        else:
            feedback.append(f"john.smith wrongly in '{team_name}'")

    # ================================================================
    # 5. Contaminator teams untouched (6 pts)
    # ================================================================
    for team_name in metadata.get('contaminator_teams', []):
        still_exists = _query(exec_in_env,
            f"SELECT COUNT(*) FROM team_informations WHERE team_name = '{team_name}'")
        if still_exists and int(still_exists) > 0:
            score += 3; feedback.append(f"Contaminator '{team_name}' untouched OK")
        else:
            feedback.append(f"Contaminator '{team_name}' was deleted/modified")

    # ================================================================
    # 6. RSS feed check (10 pts)
    # ================================================================
    log_check_script = (
        "import subprocess, json\n"
        "try:\n"
        "    with open('/tmp/rss_log_baseline') as f:\n"
        "        baseline = int(f.read().strip())\n"
        "except Exception:\n"
        "    baseline = 0\n"
        "tail_result = subprocess.run(\n"
        "    ['sudo', 'tail', '-n', '+' + str(baseline + 1),\n"
        "     '/var/log/apache2/socioboard_access.log'],\n"
        "    capture_output=True, text=True\n"
        ")\n"
        "found = 'POST /getRss' in tail_result.stdout\n"
        "print(json.dumps({'found': found}))\n"
    )
    try:
        write_cmd = (
            "python3 - << 'PYEOF'\n"
            "import sys\n"
            f"with open('/tmp/_rss_check.py','w') as f:\n"
            f"    f.write({repr(log_check_script)})\n"
            "print('ok')\n"
            "PYEOF"
        )
        exec_in_env(write_cmd)
        rss_output = exec_in_env("python3 /tmp/_rss_check.py 2>/dev/null")
        rss_output = rss_output.strip() if rss_output else "{}"
        import json
        rss_data = json.loads(rss_output)
        if rss_data.get('found'):
            score += 10; feedback.append("RSS feed submitted OK")
        else:
            feedback.append("No RSS form submission detected in Apache logs")
    except Exception as e:
        logger.warning(f"RSS check failed: {e}")
        feedback.append(f"RSS check error: {e}")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }
