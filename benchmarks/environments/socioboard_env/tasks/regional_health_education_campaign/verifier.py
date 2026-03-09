#!/usr/bin/env python3
"""Verifier for regional_health_education_campaign task.

Health Education Specialist scenario: update admin profile with campaign code,
create 5 regional/national teams, assign 3 pre-registered coordinators to
specific regions with strict exclusions, add 3 public health RSS feeds.

Scoring (100 points, threshold 60):
- Profile: first_name(5) + last_name(5) + PHC-2024-DIGITAL in bio(8) + timezone(4) + phone(3) = 25 pts
- 5 regional/national teams: 5 x 5 = 25 pts
- sarah.johnson correct (2 teams): 2 x 4 = 8 pts
- david.martinez correct (3 teams): 3 x 4 = 12 pts
- lisa.chen correct (2 teams): 2 x 4 = 8 pts
- Wrong memberships absent (8 total): 8 x 1 = 8 pts
- RSS >=3: 10 pts
- Contaminator teams untouched (3): 3 x 1.33 = 4 pts (use 4 flat)
Total: 25+25+8+12+8+8+10+4 = 100 pts
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


def verify_regional_health_education_campaign(traj, env_info, task_info):
    exec_in_env = env_info.get('exec_in_env') or env_info.get('exec_capture')
    if not exec_in_env:
        return {"passed": False, "score": 0, "feedback": "exec_in_env not available"}

    metadata = task_info.get('metadata', {})
    score = 0
    feedback = []

    exp_first = metadata.get('expected_first_name', 'Patricia')
    exp_last = metadata.get('expected_last_name', 'Wells')
    exp_about_frag = metadata.get('expected_about_fragment', 'PHC-2024-DIGITAL')
    exp_tz = metadata.get('expected_timezone', 'America/Chicago')
    exp_phone = metadata.get('expected_phone', '3125550199')

    sarah_email = metadata.get('sarah_email', 'sarah.johnson@socioboard.local')
    david_email = metadata.get('david_email', 'david.martinez@socioboard.local')
    lisa_email = metadata.get('lisa_email', 'lisa.chen@socioboard.local')

    sarah_teams = metadata.get('sarah_teams', ["Northeast Region", "National Campaign Hub"])
    sarah_excluded = metadata.get('sarah_excluded', ["Southeast Region", "Midwest Region", "West Coast Region"])
    david_teams = metadata.get('david_teams', ["Southeast Region", "Midwest Region", "National Campaign Hub"])
    david_excluded = metadata.get('david_excluded', ["Northeast Region", "West Coast Region"])
    lisa_teams = metadata.get('lisa_teams', ["West Coast Region", "National Campaign Hub"])
    lisa_excluded = metadata.get('lisa_excluded', ["Northeast Region", "Southeast Region", "Midwest Region"])

    regional_teams = metadata.get('regional_teams', [
        "Northeast Region", "Southeast Region", "Midwest Region",
        "West Coast Region", "National Campaign Hub"
    ])
    contaminator_teams = metadata.get('contaminator_teams', [
        "2023 Flu Prevention Campaign", "2023 Opioid Awareness Drive", "2023 Mental Health Month"
    ])
    expected_rss_count = metadata.get('expected_rss_count', 3)

    # ================================================================
    # 1. Profile checks (25 pts)
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
        score += 5; feedback.append(f"first_name='{first_name}' OK")
    else:
        feedback.append(f"first_name='{first_name}' (expected '{exp_first}')")

    if last_name == exp_last:
        score += 5; feedback.append(f"last_name='{last_name}' OK")
    else:
        feedback.append(f"last_name='{last_name}' (expected '{exp_last}')")

    if exp_about_frag in about_me:
        score += 8; feedback.append(f"Campaign code '{exp_about_frag}' in bio OK")
    else:
        feedback.append(f"Campaign code '{exp_about_frag}' NOT found in bio")

    if timezone == exp_tz:
        score += 4; feedback.append(f"timezone='{timezone}' OK")
    else:
        feedback.append(f"timezone='{timezone}' (expected '{exp_tz}')")

    if exp_phone in phone_no:
        score += 3; feedback.append("phone OK")
    else:
        feedback.append(f"phone='{phone_no}' (expected contains '{exp_phone}')")

    # ================================================================
    # 2. Regional teams exist (25 pts)
    # ================================================================
    for team_name in regional_teams:
        exists = _query(exec_in_env,
            f"SELECT COUNT(*) FROM team_informations WHERE team_name = '{team_name}'")
        if exists and int(exists) > 0:
            score += 5; feedback.append(f"Team '{team_name}' exists OK")
        else:
            feedback.append(f"Team '{team_name}' MISSING")

    # ================================================================
    # 3. sarah.johnson correct memberships (8 pts)
    # ================================================================
    for team_name in sarah_teams:
        if _member_check(exec_in_env, team_name, sarah_email):
            score += 4; feedback.append(f"sarah.johnson in '{team_name}' OK")
        else:
            feedback.append(f"sarah.johnson NOT in '{team_name}'")

    # ================================================================
    # 4. david.martinez correct memberships (12 pts)
    # ================================================================
    for team_name in david_teams:
        if _member_check(exec_in_env, team_name, david_email):
            score += 4; feedback.append(f"david.martinez in '{team_name}' OK")
        else:
            feedback.append(f"david.martinez NOT in '{team_name}'")

    # ================================================================
    # 5. lisa.chen correct memberships (8 pts)
    # ================================================================
    for team_name in lisa_teams:
        if _member_check(exec_in_env, team_name, lisa_email):
            score += 4; feedback.append(f"lisa.chen in '{team_name}' OK")
        else:
            feedback.append(f"lisa.chen NOT in '{team_name}'")

    # ================================================================
    # 6. Wrong memberships absent (8 pts)
    # ================================================================
    for email, excluded, label in [
        (sarah_email, sarah_excluded, "sarah.johnson"),
        (david_email, david_excluded, "david.martinez"),
        (lisa_email, lisa_excluded, "lisa.chen"),
    ]:
        for team_name in excluded:
            if not _member_check(exec_in_env, team_name, email):
                score += 1; feedback.append(f"{label} correctly excluded from '{team_name}'")
            else:
                feedback.append(f"{label} wrongly added to '{team_name}'")

    # ================================================================
    # 7. RSS feed count (10 pts)
    # ================================================================
    rss_check_script = (
        "import subprocess, json\n"
        "try:\n"
        "    with open('/tmp/rhec_rss_baseline') as f:\n"
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
            f"with open('/tmp/_rhec_rss_check.py','w') as f:\n"
            f"    f.write({repr(rss_check_script)})\n"
            "print('ok')\n"
            "PYEOF"
        )
        exec_in_env(write_cmd)
        rss_output = exec_in_env("python3 /tmp/_rhec_rss_check.py 2>/dev/null")
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
    # 8. Contaminator teams untouched (4 pts, ~1.33 each)
    # ================================================================
    contam_pts = [2, 1, 1]  # 4 total
    for i, team_name in enumerate(contaminator_teams):
        exists = _query(exec_in_env,
            f"SELECT COUNT(*) FROM team_informations WHERE team_name = '{team_name}'")
        pts = contam_pts[i] if i < len(contam_pts) else 1
        if exists and int(exists) > 0:
            score += pts; feedback.append(f"Archive '{team_name}' untouched OK")
        else:
            feedback.append(f"Archive '{team_name}' was deleted (should be preserved)")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }
