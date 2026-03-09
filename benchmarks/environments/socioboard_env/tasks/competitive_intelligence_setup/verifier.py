#!/usr/bin/env python3
"""Verifier for competitive_intelligence_setup task.

Marketing Manager scenario: update admin profile with embedded campaign code
(COMPINT-Q2-2024), create 5 market segment teams, manage two users (alex.brand
and john.smith) with complementary/non-overlapping assignments, add 4 RSS feeds,
and critically preserve 4 Q1 contaminator teams completely unchanged.

Scoring (100 points, threshold 60):
- Profile: first_name(4) + last_name(4) + COMPINT-Q2-2024 in bio(8) + timezone(4) + phone(4) = 24 pts
- 5 market teams: 5 x 6 = 30 pts
- alex.brand correct (3 teams): 3 x 4 = 12 pts
- alex.brand NOT in wrong teams (2): 2 x 3 = 6 pts
- john.smith correct (2 teams): 2 x 4 = 8 pts
- john.smith NOT in wrong teams (3): 3 x 2 = 6 pts
- RSS >= 4: 8 pts
- Q1 contaminator teams untouched (4): 4 x 1.5 = 6 pts
Total: 24+30+12+6+8+6+8+6 = 100 pts
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
    # Escape single quotes in team_name for SQL safety
    safe_team = team_name.replace("'", "\\'")
    sql = (
        f"SELECT COUNT(*) FROM join_table_users_teams jt "
        f"JOIN team_informations ti ON jt.team_id = ti.team_id "
        f"JOIN user_details ud ON jt.user_id = ud.user_id "
        f"WHERE ti.team_name = '{safe_team}' AND ud.email = '{email}'"
    )
    result = _query(exec_in_env, sql)
    return result and int(result) > 0


def verify_competitive_intelligence_setup(traj, env_info, task_info):
    exec_in_env = env_info.get('exec_in_env') or env_info.get('exec_capture')
    if not exec_in_env:
        return {"passed": False, "score": 0, "feedback": "exec_in_env not available"}

    metadata = task_info.get('metadata', {})
    score = 0
    feedback = []

    exp_first = metadata.get('expected_first_name', 'Sophia')
    exp_last = metadata.get('expected_last_name', 'Chen')
    exp_about_frag = metadata.get('expected_about_fragment', 'COMPINT-Q2-2024')
    exp_tz = metadata.get('expected_timezone', 'America/Los_Angeles')
    exp_phone = metadata.get('expected_phone', '4155550233')

    market_teams = metadata.get('market_teams', [
        "Enterprise Solutions Vertical", "SMB Focus Group", "Consumer Direct Channel",
        "Healthcare Vertical", "Education Sector"
    ])
    alex_email = metadata.get('alex_email', 'alex.brand@socioboard.local')
    john_email = metadata.get('john_email', 'john.smith@socioboard.local')
    alex_teams = metadata.get('alex_teams', [
        "Enterprise Solutions Vertical", "Healthcare Vertical", "Education Sector"
    ])
    alex_excluded = metadata.get('alex_excluded', ["SMB Focus Group", "Consumer Direct Channel"])
    john_teams = metadata.get('john_teams', ["SMB Focus Group", "Consumer Direct Channel"])
    john_excluded = metadata.get('john_excluded', [
        "Enterprise Solutions Vertical", "Healthcare Vertical", "Education Sector"
    ])
    expected_rss_count = metadata.get('expected_rss_count', 4)
    contaminator_teams = metadata.get('contaminator_teams', [
        "Q1: Brand Awareness", "Q1: Product Launch Alpha",
        "Q1: Retail Partnerships", "Q1: Digital Outreach"
    ])

    # ================================================================
    # 1. Profile checks (24 pts)
    # ================================================================
    profile = _query(exec_in_env,
        "SELECT first_name, last_name, about_me, phone_no, time_zone "
        "FROM user_details WHERE email = 'admin@socioboard.local' LIMIT 1")

    if not profile:
        return {"passed": False, "score": 0, "feedback": "Admin user not found in DB"}

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
        score += 8; feedback.append(f"Campaign code '{exp_about_frag}' in bio OK")
    else:
        feedback.append(f"Campaign code '{exp_about_frag}' NOT in bio")

    if timezone == exp_tz:
        score += 4; feedback.append(f"timezone='{timezone}' OK")
    else:
        feedback.append(f"timezone='{timezone}' (expected '{exp_tz}')")

    if exp_phone in phone_no:
        score += 4; feedback.append("phone OK")
    else:
        feedback.append(f"phone='{phone_no}' (expected contains '{exp_phone}')")

    # ================================================================
    # 2. Market segment teams exist (30 pts)
    # ================================================================
    for team_name in market_teams:
        exists = _query(exec_in_env,
            f"SELECT COUNT(*) FROM team_informations WHERE team_name = '{team_name}'")
        if exists and int(exists) > 0:
            score += 6; feedback.append(f"Market team '{team_name}' exists OK")
        else:
            feedback.append(f"Market team '{team_name}' MISSING")

    # ================================================================
    # 3. alex.brand memberships (12 pts correct + 6 pts exclusions)
    # ================================================================
    for team_name in alex_teams:
        if _member_check(exec_in_env, team_name, alex_email):
            score += 4; feedback.append(f"alex.brand in '{team_name}' OK")
        else:
            feedback.append(f"alex.brand NOT in '{team_name}'")

    for team_name in alex_excluded:
        if not _member_check(exec_in_env, team_name, alex_email):
            score += 3; feedback.append(f"alex.brand excluded from '{team_name}' OK")
        else:
            feedback.append(f"alex.brand wrongly in '{team_name}'")

    # ================================================================
    # 4. john.smith memberships (8 pts correct + 6 pts exclusions)
    # ================================================================
    for team_name in john_teams:
        if _member_check(exec_in_env, team_name, john_email):
            score += 4; feedback.append(f"john.smith in '{team_name}' OK")
        else:
            feedback.append(f"john.smith NOT in '{team_name}'")

    for team_name in john_excluded:
        if not _member_check(exec_in_env, team_name, john_email):
            score += 2; feedback.append(f"john.smith excluded from '{team_name}' OK")
        else:
            feedback.append(f"john.smith wrongly in '{team_name}'")

    # ================================================================
    # 5. RSS feed count (8 pts)
    # ================================================================
    rss_check_script = (
        "import subprocess, json\n"
        "try:\n"
        "    with open('/tmp/cis_rss_baseline') as f:\n"
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
            f"with open('/tmp/_cis_rss_check.py','w') as f:\n"
            f"    f.write({repr(rss_check_script)})\n"
            "print('ok')\n"
            "PYEOF"
        )
        exec_in_env(write_cmd)
        rss_output = exec_in_env("python3 /tmp/_cis_rss_check.py 2>/dev/null")
        rss_output = rss_output.strip() if rss_output else "{}"
        rss_data = json.loads(rss_output)
        rss_count = rss_data.get('rss_count', 0)
        if rss_count >= expected_rss_count:
            score += 8; feedback.append(f"RSS: {rss_count} submissions (need {expected_rss_count}) OK")
        else:
            feedback.append(f"RSS: only {rss_count} submissions (need {expected_rss_count})")
    except Exception as e:
        logger.warning(f"RSS check failed: {e}")
        feedback.append(f"RSS check error: {e}")

    # ================================================================
    # 6. Q1 contaminator teams untouched (6 pts total, ~1.5 each)
    # ================================================================
    contam_pts = [2, 2, 1, 1]  # 6 total
    for i, team_name in enumerate(contaminator_teams):
        safe_team = team_name.replace("'", "\\'")
        exists = _query(exec_in_env,
            f"SELECT COUNT(*) FROM team_informations WHERE team_name = '{safe_team}'")
        pts = contam_pts[i] if i < len(contam_pts) else 1
        if exists and int(exists) > 0:
            score += pts; feedback.append(f"Q1 team '{team_name}' preserved OK")
        else:
            feedback.append(f"Q1 team '{team_name}' was deleted (should be preserved)")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }
