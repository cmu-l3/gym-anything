#!/usr/bin/env python3
"""Verifier for influencer_campaign_operations task.

Advertising Manager scenario: update admin profile, create 5 client teams,
manage three different users (alex.rivera, priya.nair, john.smith) with
overlapping but distinct team assignments and strict exclusions, add 3 RSS feeds.

Scoring (100 points, threshold 60):
- Profile: first_name(4) + last_name(4) + agency fragment(5) + timezone(4) + phone(3) = 20 pts
- 5 client teams: 5 x 5 = 25 pts
- alex.rivera correct (3 teams): 3 x 4 = 12 pts
- alex.rivera NOT in wrong teams (2): 2 x 2 = 4 pts
- priya.nair correct (3 teams): 3 x 4 = 12 pts
- priya.nair NOT in wrong teams (2): 2 x 2 = 4 pts
- john.smith correct (2 teams): 2 x 4 = 8 pts
- john.smith NOT in wrong teams (3): 3 x 2 = 6 pts
- RSS >=3: 9 pts
Total: 20+25+12+4+12+4+8+6+9 = 100 pts
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


def verify_influencer_campaign_operations(traj, env_info, task_info):
    exec_in_env = env_info.get('exec_in_env') or env_info.get('exec_capture')
    if not exec_in_env:
        return {"passed": False, "score": 0, "feedback": "exec_in_env not available"}

    metadata = task_info.get('metadata', {})
    score = 0
    feedback = []

    exp_first = metadata.get('expected_first_name', 'Marcus')
    exp_last = metadata.get('expected_last_name', 'Webb')
    exp_about_frag = metadata.get('expected_about_fragment', 'Fusion Creative Agency')
    exp_tz = metadata.get('expected_timezone', 'America/New_York')
    exp_phone = metadata.get('expected_phone', '2125550177')

    client_teams = metadata.get('client_teams', [
        "TechFlow Solutions", "NovaBrand Retail", "GreenPath Sustainability",
        "MediaCraft Studios", "SportsPulse Network"
    ])
    alex_email = metadata.get('alex_email', 'alex.rivera@socioboard.local')
    priya_email = metadata.get('priya_email', 'priya.nair@socioboard.local')
    john_email = metadata.get('john_email', 'john.smith@socioboard.local')

    alex_teams = metadata.get('alex_teams', ["TechFlow Solutions", "NovaBrand Retail", "GreenPath Sustainability"])
    alex_excluded = metadata.get('alex_excluded', ["MediaCraft Studios", "SportsPulse Network"])
    priya_teams = metadata.get('priya_teams', ["GreenPath Sustainability", "MediaCraft Studios", "SportsPulse Network"])
    priya_excluded = metadata.get('priya_excluded', ["TechFlow Solutions", "NovaBrand Retail"])
    john_teams = metadata.get('john_teams', ["NovaBrand Retail", "MediaCraft Studios"])
    john_excluded = metadata.get('john_excluded', ["TechFlow Solutions", "GreenPath Sustainability", "SportsPulse Network"])

    expected_rss_count = metadata.get('expected_rss_count', 3)

    # ================================================================
    # 1. Profile checks (20 pts)
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
        score += 5; feedback.append(f"Agency name in bio OK")
    else:
        feedback.append(f"Bio missing '{exp_about_frag}'")

    if timezone == exp_tz:
        score += 4; feedback.append(f"timezone='{timezone}' OK")
    else:
        feedback.append(f"timezone='{timezone}' (expected '{exp_tz}')")

    if exp_phone in phone_no:
        score += 3; feedback.append("phone OK")
    else:
        feedback.append(f"phone='{phone_no}' (expected contains '{exp_phone}')")

    # ================================================================
    # 2. Client teams exist (25 pts)
    # ================================================================
    for team_name in client_teams:
        exists = _query(exec_in_env,
            f"SELECT COUNT(*) FROM team_informations WHERE team_name = '{team_name}'")
        if exists and int(exists) > 0:
            score += 5; feedback.append(f"Team '{team_name}' exists OK")
        else:
            feedback.append(f"Team '{team_name}' MISSING")

    # ================================================================
    # 3. alex.rivera memberships (12 pts correct + 4 pts exclusions)
    # ================================================================
    for team_name in alex_teams:
        if _member_check(exec_in_env, team_name, alex_email):
            score += 4; feedback.append(f"alex.rivera in '{team_name}' OK")
        else:
            feedback.append(f"alex.rivera NOT in '{team_name}'")

    for team_name in alex_excluded:
        if not _member_check(exec_in_env, team_name, alex_email):
            score += 2; feedback.append(f"alex.rivera excluded from '{team_name}' OK")
        else:
            feedback.append(f"alex.rivera wrongly in '{team_name}'")

    # ================================================================
    # 4. priya.nair memberships (12 pts correct + 4 pts exclusions)
    # ================================================================
    for team_name in priya_teams:
        if _member_check(exec_in_env, team_name, priya_email):
            score += 4; feedback.append(f"priya.nair in '{team_name}' OK")
        else:
            feedback.append(f"priya.nair NOT in '{team_name}'")

    for team_name in priya_excluded:
        if not _member_check(exec_in_env, team_name, priya_email):
            score += 2; feedback.append(f"priya.nair excluded from '{team_name}' OK")
        else:
            feedback.append(f"priya.nair wrongly in '{team_name}'")

    # ================================================================
    # 5. john.smith memberships (8 pts correct + 6 pts exclusions)
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
    # 6. RSS feed count (9 pts)
    # ================================================================
    rss_check_script = (
        "import subprocess, json\n"
        "try:\n"
        "    with open('/tmp/ico_rss_baseline') as f:\n"
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
            f"with open('/tmp/_ico_rss_check.py','w') as f:\n"
            f"    f.write({repr(rss_check_script)})\n"
            "print('ok')\n"
            "PYEOF"
        )
        exec_in_env(write_cmd)
        rss_output = exec_in_env("python3 /tmp/_ico_rss_check.py 2>/dev/null")
        rss_output = rss_output.strip() if rss_output else "{}"
        rss_data = json.loads(rss_output)
        rss_count = rss_data.get('rss_count', 0)
        if rss_count >= expected_rss_count:
            score += 9; feedback.append(f"RSS: {rss_count} submissions (need {expected_rss_count}) OK")
        else:
            feedback.append(f"RSS: only {rss_count} submissions (need {expected_rss_count})")
    except Exception as e:
        logger.warning(f"RSS check failed: {e}")
        feedback.append(f"RSS check error: {e}")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }
