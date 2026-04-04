#!/usr/bin/env python3
"""Verifier for crisis_comms_rapid_response task.

PR Specialist scenario: delete 4 [ARCHIVED] teams, update admin profile,
create 3 crisis monitoring teams, add victoria.santos to all 3 crisis teams,
add john.smith to 2 of 3 (not Executive Briefing), add 4 RSS feeds.

The team-deletion check is the unique feature that distinguishes this task.
Even if deletion fails, the remaining criteria total 80pts so the task can
still pass at threshold 60.

Scoring (100 points, threshold 60):
- [ARCHIVED] teams deleted (4): 4 x 5 = 20 pts
- Profile: first_name(4) + last_name(4) + Meridian PR in bio(5) + timezone(4) + phone(4) = 21 pts
- 3 crisis teams: 3 x 5 = 15 pts
- victoria.santos in all 3 crisis teams: 3 x 5 = 15 pts
- john.smith in Media Monitoring + Social Sentiment: 2 x 5 = 10 pts
- john.smith NOT in Executive Briefing: 5 pts
- RSS >= 4: 10 pts
- Safe teams untouched (2): 2 x 2 = 4 pts
Total: 20+21+15+15+10+5+10+4 = 100 pts
"""

import json
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def _query(exec_in_env, sql):
    cmd = f'mysql -u root socioboard -N -B -e "{sql}" 2>/dev/null'
    try:
        result = exec_in_env(cmd)
        return result.strip() if result else ""
    except Exception as e:
        logger.warning(f"Query failed: {e}")
        return ""


def _member_check(exec_in_env, team_name, email):
    sql = (
        f"SELECT COUNT(*) FROM join_table_users_teams jt "
        f"JOIN team_informations ti ON jt.team_id = ti.team_id "
        f"JOIN user_details ud ON jt.user_id = ud.user_id "
        f"WHERE ti.team_name = '{team_name}' AND ud.email = '{email}'"
    )
    result = _query(exec_in_env, sql)
    return result and int(result) > 0


def verify_crisis_comms_rapid_response(traj, env_info, task_info):
    exec_in_env = env_info.get('exec_in_env') or env_info.get('exec_capture')
    if not exec_in_env:
        return {"passed": False, "score": 0, "feedback": "exec_in_env not available"}

    metadata = task_info.get('metadata', {})
    score = 0
    feedback = []

    archived_teams = metadata.get('archived_teams', [
        "[ARCHIVED] Seasonal Campaign Q3",
        "[ARCHIVED] Product Launch Beta",
        "[ARCHIVED] Regional Partnership West",
        "[ARCHIVED] Trade Show Presence"
    ])
    exp_first = metadata.get('expected_first_name', 'Daniel')
    exp_last = metadata.get('expected_last_name', 'Park')
    exp_about_frag = metadata.get('expected_about_fragment', 'Meridian PR')
    exp_tz = metadata.get('expected_timezone', 'Europe/London')
    exp_phone = metadata.get('expected_phone', '7700900042')
    crisis_teams = metadata.get('crisis_teams', [
        "Crisis: Media Monitoring", "Crisis: Social Sentiment", "Crisis: Executive Briefing"
    ])
    victoria_email = metadata.get('victoria_email', 'victoria.santos@socioboard.local')
    john_email = metadata.get('john_email', 'john.smith@socioboard.local')
    victoria_teams = metadata.get('victoria_teams', crisis_teams)
    john_teams = metadata.get('john_teams', ["Crisis: Media Monitoring", "Crisis: Social Sentiment"])
    john_excluded = metadata.get('john_excluded', ["Crisis: Executive Briefing"])
    safe_teams = metadata.get('safe_teams', ["Brand Monitoring", "Media Relations"])
    expected_rss_count = metadata.get('expected_rss_count', 4)

    # ================================================================
    # 1. [ARCHIVED] teams deleted (20 pts)
    # ================================================================
    for team_name in archived_teams:
        exists = _query(exec_in_env,
            f"SELECT COUNT(*) FROM team_informations WHERE team_name = '{team_name}'")
        if not exists or int(exists) == 0:
            score += 5; feedback.append(f"[ARCHIVED] '{team_name}' deleted OK")
        else:
            feedback.append(f"[ARCHIVED] '{team_name}' still exists (should be deleted)")

    # ================================================================
    # 2. Profile checks (21 pts)
    # ================================================================
    profile = _query(exec_in_env,
        "SELECT first_name, last_name, about_me, phone_no, time_zone "
        "FROM user_details WHERE email = 'admin@socioboard.local' LIMIT 1")

    if not profile:
        return {"passed": False, "score": score, "feedback": "Admin user not found in DB"}

    parts = profile.split('\t')
    first_name = parts[0].strip() if len(parts) > 0 else ""
    last_name = parts[1].strip() if len(parts) > 1 else ""
    about_me = parts[2].strip() if len(parts) > 2 else ""
    phone_no = parts[3].strip() if len(parts) > 3 else ""
    timezone = parts[4].strip() if len(parts) > 4 else ""

    if first_name == exp_first:
        score += 4; feedback.append(f"first_name='{first_name}' OK")
    else:
        feedback.append(f"first_name='{first_name}' (expected '{exp_first}')")

    if last_name == exp_last:
        score += 4; feedback.append(f"last_name='{last_name}' OK")
    else:
        feedback.append(f"last_name='{last_name}' (expected '{exp_last}')")

    if exp_about_frag in about_me:
        score += 5; feedback.append(f"'{exp_about_frag}' in bio OK")
    else:
        feedback.append(f"Bio missing '{exp_about_frag}'")

    if timezone == exp_tz:
        score += 4; feedback.append(f"timezone='{timezone}' OK")
    else:
        feedback.append(f"timezone='{timezone}' (expected '{exp_tz}')")

    if exp_phone in phone_no:
        score += 4; feedback.append("phone OK")
    else:
        feedback.append(f"phone='{phone_no}' (expected contains '{exp_phone}')")

    # ================================================================
    # 3. Crisis teams exist (15 pts)
    # ================================================================
    for team_name in crisis_teams:
        exists = _query(exec_in_env,
            f"SELECT COUNT(*) FROM team_informations WHERE team_name = '{team_name}'")
        if exists and int(exists) > 0:
            score += 5; feedback.append(f"Crisis team '{team_name}' exists OK")
        else:
            feedback.append(f"Crisis team '{team_name}' MISSING")

    # ================================================================
    # 4. victoria.santos in all crisis teams (15 pts)
    # ================================================================
    for team_name in victoria_teams:
        if _member_check(exec_in_env, team_name, victoria_email):
            score += 5; feedback.append(f"victoria.santos in '{team_name}' OK")
        else:
            feedback.append(f"victoria.santos NOT in '{team_name}'")

    # ================================================================
    # 5. john.smith in correct crisis teams (10 pts)
    # ================================================================
    for team_name in john_teams:
        if _member_check(exec_in_env, team_name, john_email):
            score += 5; feedback.append(f"john.smith in '{team_name}' OK")
        else:
            feedback.append(f"john.smith NOT in '{team_name}'")

    # ================================================================
    # 6. john.smith NOT in Executive Briefing (5 pts)
    # ================================================================
    for team_name in john_excluded:
        if not _member_check(exec_in_env, team_name, john_email):
            score += 5; feedback.append(f"john.smith correctly excluded from '{team_name}'")
        else:
            feedback.append(f"john.smith wrongly in '{team_name}'")

    # ================================================================
    # 7. RSS feed count (10 pts)
    # ================================================================
    rss_check_script = (
        "import subprocess, json\n"
        "try:\n"
        "    with open('/tmp/ccr_rss_baseline') as f:\n"
        "        baseline = int(f.read().strip())\n"
        "except Exception:\n"
        "    baseline = 0\n"
        "tail_result = subprocess.run(\n"
        "    ['sudo', 'tail', '-n', '+' + str(baseline + 1),\n"
        "     '/var/log/apache2/socioboard_access.log'],\n"
        "    capture_output=True, text=True\n"
        ")\n"
        "rss_count = tail_result.stdout.count('POST /getRss')\n"
        "print(json.dumps({'rss_count': rss_count}))\n"
    )
    try:
        write_cmd = (
            "python3 - << 'PYEOF'\n"
            "import sys\n"
            f"with open('/tmp/_ccr_rss_check.py','w') as f:\n"
            f"    f.write({repr(rss_check_script)})\n"
            "print('ok')\n"
            "PYEOF"
        )
        exec_in_env(write_cmd)
        rss_output = exec_in_env("python3 /tmp/_ccr_rss_check.py 2>/dev/null")
        rss_output = rss_output.strip() if rss_output else "{}"
        rss_data = json.loads(rss_output)
        rss_count = rss_data.get('rss_count', 0)
        if rss_count >= expected_rss_count:
            score += 10; feedback.append(f"RSS: {rss_count} submissions (need {expected_rss_count}) OK")
        else:
            feedback.append(f"RSS: only {rss_count} submissions (need {expected_rss_count})")
    except Exception as e:
        logger.warning(f"RSS check failed: {e}")
        feedback.append(f"RSS check error: {e}")

    # ================================================================
    # 8. Safe/normal teams not deleted (4 pts)
    # ================================================================
    for team_name in safe_teams:
        exists = _query(exec_in_env,
            f"SELECT COUNT(*) FROM team_informations WHERE team_name = '{team_name}'")
        if exists and int(exists) > 0:
            score += 2; feedback.append(f"Safe team '{team_name}' preserved OK")
        else:
            feedback.append(f"Safe team '{team_name}' was wrongly deleted")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }
