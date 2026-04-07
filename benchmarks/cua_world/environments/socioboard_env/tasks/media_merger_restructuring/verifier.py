#!/usr/bin/env python3
"""Verifier for media_merger_restructuring task.

Post-merger restructuring scenario: update admin profile, delete 3 [LEGACY]
teams, create 7 newsroom teams, assign 3 reporters with overlapping beat
assignments, add 6 RSS feeds, preserve 2 operational teams.

Scoring (100 points, threshold 60):
- [LEGACY] teams deleted (3): 3 x 4 = 12 pts
- Profile: first_name(3) + last_name(3) + Cascadia Media Group in bio(4)
           + 8 newsroom desks in bio(2) + timezone(2) + phone(2) = 16 pts
- 7 newsroom teams exist: 7 x 3 = 21 pts
- emily.chen in correct teams (3): 3 x 2 = 6 pts
- michael.okafor in correct teams (3): 3 x 2 = 6 pts
- victoria.santos in correct teams (3): 3 x 2 = 6 pts
- emily.chen NOT in wrong teams (4): 4 x 1 = 4 pts
- michael.okafor NOT in wrong teams (4): 4 x 1 = 4 pts
- victoria.santos NOT in wrong teams (4): 4 x 1 = 4 pts
- RSS >= 6 submissions: 15 pts
- Safe teams preserved (2): 2 x 3 = 6 pts
Total: 12+16+21+6+6+6+4+4+4+15+6 = 100 pts
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


def verify_media_merger_restructuring(traj, env_info, task_info):
    exec_in_env = env_info.get('exec_in_env') or env_info.get('exec_capture')
    if not exec_in_env:
        return {"passed": False, "score": 0, "feedback": "exec_in_env not available"}

    metadata = task_info.get('metadata', {})
    score = 0
    feedback = []

    # Load expected values from metadata (with hardcoded fallbacks)
    exp_first = metadata.get('expected_first_name', 'Rachel')
    exp_last = metadata.get('expected_last_name', 'Torres')
    exp_about_frag = metadata.get('expected_about_fragment', 'Cascadia Media Group')
    exp_about_frag_2 = metadata.get('expected_about_fragment_2', '8 newsroom desks')
    exp_tz = metadata.get('expected_timezone', 'US/Pacific')
    exp_phone = metadata.get('expected_phone', '5039876543')

    legacy_teams = metadata.get('legacy_teams', [
        "[LEGACY] Pacific West Division",
        "[LEGACY] Coastal Features Desk",
        "[LEGACY] Digital Pilot Program"
    ])
    newsroom_teams = metadata.get('newsroom_teams', [
        "Metro Desk", "State Politics", "Tech & Science",
        "Arts & Culture", "Sports", "Investigations", "Breaking News"
    ])

    emily_email = metadata.get('emily_email', 'emily.chen@socioboard.local')
    michael_email = metadata.get('michael_email', 'michael.okafor@socioboard.local')
    victoria_email = metadata.get('victoria_email', 'victoria.santos@socioboard.local')

    emily_teams = metadata.get('emily_teams', ["Metro Desk", "State Politics", "Investigations"])
    emily_excluded = metadata.get('emily_excluded', [
        "Tech & Science", "Arts & Culture", "Sports", "Breaking News"
    ])
    michael_teams = metadata.get('michael_teams', ["Tech & Science", "Arts & Culture", "Breaking News"])
    michael_excluded = metadata.get('michael_excluded', [
        "Metro Desk", "State Politics", "Sports", "Investigations"
    ])
    victoria_teams = metadata.get('victoria_teams', [
        "State Politics", "Investigations", "Breaking News"
    ])
    victoria_excluded = metadata.get('victoria_excluded', [
        "Metro Desk", "Tech & Science", "Arts & Culture", "Sports"
    ])

    safe_teams = metadata.get('safe_teams', ["Daily Briefing", "Weekend Edition"])
    expected_rss_count = metadata.get('expected_rss_count', 6)

    # ================================================================
    # 1. [LEGACY] teams deleted (12 pts)
    # ================================================================
    for team_name in legacy_teams:
        exists = _query(exec_in_env,
            f"SELECT COUNT(*) FROM team_informations WHERE team_name = '{team_name}'")
        if not exists or int(exists) == 0:
            score += 4; feedback.append(f"[LEGACY] '{team_name}' deleted OK")
        else:
            feedback.append(f"[LEGACY] '{team_name}' still exists (should be deleted)")

    # ================================================================
    # 2. Profile checks (16 pts)
    # ================================================================
    profile = _query(exec_in_env,
        "SELECT first_name, last_name, about_me, phone_no, time_zone "
        "FROM user_details WHERE email = 'admin@socioboard.local' LIMIT 1")

    if not profile:
        feedback.append("Admin user not found in DB")
    else:
        parts = profile.split('\t')
        first_name = parts[0].strip() if len(parts) > 0 else ""
        last_name = parts[1].strip() if len(parts) > 1 else ""
        about_me = parts[2].strip() if len(parts) > 2 else ""
        phone_no = parts[3].strip() if len(parts) > 3 else ""
        timezone = parts[4].strip() if len(parts) > 4 else ""

        if first_name == exp_first:
            score += 3; feedback.append(f"first_name='{first_name}' OK")
        else:
            feedback.append(f"first_name='{first_name}' (expected '{exp_first}')")

        if last_name == exp_last:
            score += 3; feedback.append(f"last_name='{last_name}' OK")
        else:
            feedback.append(f"last_name='{last_name}' (expected '{exp_last}')")

        if exp_about_frag in about_me:
            score += 4; feedback.append(f"'{exp_about_frag}' in bio OK")
        else:
            feedback.append(f"Bio missing '{exp_about_frag}'")

        if exp_about_frag_2 in about_me:
            score += 2; feedback.append(f"'{exp_about_frag_2}' in bio OK")
        else:
            feedback.append(f"Bio missing '{exp_about_frag_2}'")

        if timezone == exp_tz:
            score += 2; feedback.append(f"timezone='{timezone}' OK")
        else:
            feedback.append(f"timezone='{timezone}' (expected '{exp_tz}')")

        if exp_phone in phone_no:
            score += 2; feedback.append("phone OK")
        else:
            feedback.append(f"phone='{phone_no}' (expected contains '{exp_phone}')")

    # ================================================================
    # 3. Newsroom teams exist (21 pts)
    # ================================================================
    for team_name in newsroom_teams:
        exists = _query(exec_in_env,
            f"SELECT COUNT(*) FROM team_informations WHERE team_name = '{team_name}'")
        if exists and int(exists) > 0:
            score += 3; feedback.append(f"Newsroom team '{team_name}' exists OK")
        else:
            feedback.append(f"Newsroom team '{team_name}' MISSING")

    # ================================================================
    # 4. emily.chen in correct teams (6 pts)
    # ================================================================
    for team_name in emily_teams:
        if _member_check(exec_in_env, team_name, emily_email):
            score += 2; feedback.append(f"emily.chen in '{team_name}' OK")
        else:
            feedback.append(f"emily.chen NOT in '{team_name}'")

    # ================================================================
    # 5. michael.okafor in correct teams (6 pts)
    # ================================================================
    for team_name in michael_teams:
        if _member_check(exec_in_env, team_name, michael_email):
            score += 2; feedback.append(f"michael.okafor in '{team_name}' OK")
        else:
            feedback.append(f"michael.okafor NOT in '{team_name}'")

    # ================================================================
    # 6. victoria.santos in correct teams (6 pts)
    # ================================================================
    for team_name in victoria_teams:
        if _member_check(exec_in_env, team_name, victoria_email):
            score += 2; feedback.append(f"victoria.santos in '{team_name}' OK")
        else:
            feedback.append(f"victoria.santos NOT in '{team_name}'")

    # ================================================================
    # 7. emily.chen NOT in excluded teams (4 pts)
    # ================================================================
    for team_name in emily_excluded:
        if not _member_check(exec_in_env, team_name, emily_email):
            score += 1; feedback.append(f"emily.chen correctly excluded from '{team_name}'")
        else:
            feedback.append(f"emily.chen wrongly added to '{team_name}'")

    # ================================================================
    # 8. michael.okafor NOT in excluded teams (4 pts)
    # ================================================================
    for team_name in michael_excluded:
        if not _member_check(exec_in_env, team_name, michael_email):
            score += 1; feedback.append(f"michael.okafor correctly excluded from '{team_name}'")
        else:
            feedback.append(f"michael.okafor wrongly added to '{team_name}'")

    # ================================================================
    # 9. victoria.santos NOT in excluded teams (4 pts)
    # ================================================================
    for team_name in victoria_excluded:
        if not _member_check(exec_in_env, team_name, victoria_email):
            score += 1; feedback.append(f"victoria.santos correctly excluded from '{team_name}'")
        else:
            feedback.append(f"victoria.santos wrongly added to '{team_name}'")

    # ================================================================
    # 10. RSS feed count (15 pts)
    # ================================================================
    rss_check_script = (
        "import subprocess, json\n"
        "try:\n"
        "    with open('/tmp/mmr_rss_baseline') as f:\n"
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
            f"with open('/tmp/_mmr_rss_check.py','w') as f:\n"
            f"    f.write({repr(rss_check_script)})\n"
            "print('ok')\n"
            "PYEOF"
        )
        exec_in_env(write_cmd)
        rss_output = exec_in_env("python3 /tmp/_mmr_rss_check.py 2>/dev/null")
        rss_output = rss_output.strip() if rss_output else "{}"
        rss_data = json.loads(rss_output)
        rss_count = rss_data.get('rss_count', 0)
        if rss_count >= expected_rss_count:
            score += 15
            feedback.append(f"RSS: {rss_count} submissions (need {expected_rss_count}) OK")
        elif rss_count >= 4:
            score += 10
            feedback.append(f"RSS: {rss_count} submissions (need {expected_rss_count}, partial credit)")
        elif rss_count >= 2:
            score += 5
            feedback.append(f"RSS: {rss_count} submissions (need {expected_rss_count}, partial credit)")
        else:
            feedback.append(f"RSS: only {rss_count} submissions (need {expected_rss_count})")
    except Exception as e:
        logger.warning(f"RSS check failed: {e}")
        feedback.append(f"RSS check error: {e}")

    # ================================================================
    # 11. Safe teams preserved (6 pts)
    # ================================================================
    for team_name in safe_teams:
        exists = _query(exec_in_env,
            f"SELECT COUNT(*) FROM team_informations WHERE team_name = '{team_name}'")
        if exists and int(exists) > 0:
            score += 3; feedback.append(f"Safe team '{team_name}' preserved OK")
        else:
            feedback.append(f"Safe team '{team_name}' was wrongly deleted")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }
