#!/usr/bin/env python3
"""Verifier for event_promotion_coordination task.

Event Planner scenario: update profile, create 3 teams with long
hyphenated names, invite john.smith to ALL 3 teams, add 2 RSS feeds.

Scoring (100 points):
- Profile: first_name (5), last_name (5), about_fragment1 (5),
  about_fragment2 (5), timezone (5), phone (5) = 30 pts
- Teams: 3 × 10 pts = 30 pts
- john.smith in all 3 teams: 3 × 7 pts = 21 pts
- RSS feed submissions (>= 2): 14 pts
- Baseline timestamp: 5 pts
Total: 100 pts. Pass threshold: 60.
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


def verify_event_promotion_coordination(traj, env_info, task_info):
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
        return {"passed": False, "score": 0, "feedback": "Admin user not found"}

    parts = profile.split('\t')
    first_name = parts[0].strip() if len(parts) > 0 else ""
    last_name = parts[1].strip() if len(parts) > 1 else ""
    about_me = parts[2].strip() if len(parts) > 2 else ""
    phone_no = parts[3].strip() if len(parts) > 3 else ""
    timezone = parts[5].strip() if len(parts) > 5 else ""

    checks = [
        (first_name == metadata.get('expected_first_name', 'Priya'), 5,
         f"first_name='{first_name}'"),
        (last_name == metadata.get('expected_last_name', 'Sharma'), 5,
         f"last_name='{last_name}'"),
        (metadata.get('expected_about_fragment', 'Nexus Conference Group') in about_me, 5,
         "about contains org name"),
        (metadata.get('expected_about_fragment_2', 'technology conferences').lower() in about_me.lower(), 5,
         "about contains domain"),
        (timezone == metadata.get('expected_timezone', 'America/New_York'), 5,
         f"timezone='{timezone}'"),
        (metadata.get('expected_phone', '2125559876') in phone_no, 5,
         f"phone='{phone_no}'"),
    ]
    for passed_check, pts, desc in checks:
        if passed_check:
            score += pts; feedback.append(f"{desc} OK")
        else:
            feedback.append(f"{desc} FAIL")

    # ================================================================
    # 2. Team existence (30 pts)
    # ================================================================
    for team_name in metadata.get('teams', []):
        exists = _query(exec_in_env,
            f"SELECT COUNT(*) FROM team_informations WHERE team_name = '{team_name}'")
        if exists and int(exists) > 0:
            score += 10; feedback.append(f"Team '{team_name}' exists")
        else:
            feedback.append(f"Team '{team_name}' MISSING")

    # ================================================================
    # 3. john.smith in all 3 teams (21 pts)
    # ================================================================
    member_email = metadata.get('member_email', 'john.smith@socioboard.local')
    for team_name in metadata.get('john_teams', []):
        member_check = _query(exec_in_env,
            f"SELECT COUNT(*) FROM join_table_users_teams jt "
            f"JOIN team_informations ti ON jt.team_id = ti.team_id "
            f"JOIN user_details ud ON jt.user_id = ud.user_id "
            f"WHERE ti.team_name = '{team_name}' AND ud.email = '{member_email}'")
        if member_check and int(member_check) > 0:
            score += 7; feedback.append(f"john.smith in '{team_name}' OK")
        else:
            feedback.append(f"john.smith NOT in '{team_name}'")

    # ================================================================
    # 4. RSS feed submissions >= 2 (14 pts)
    # ================================================================
    log_script = (
        "import subprocess, json\n"
        "try:\n"
        "    with open('/tmp/rss_log_baseline') as f:\n"
        "        baseline = int(f.read().strip())\n"
        "except Exception:\n"
        "    baseline = 0\n"
        "tail = subprocess.run(\n"
        "    ['sudo', 'tail', '-n', '+' + str(baseline + 1),\n"
        "     '/var/log/apache2/socioboard_access.log'],\n"
        "    capture_output=True, text=True\n"
        ")\n"
        "count = tail.stdout.count('POST /getRss')\n"
        "print(json.dumps({'count': count}))\n"
    )
    try:
        exec_in_env(
            "python3 - << 'PYEOF'\n"
            f"with open('/tmp/_rss_check.py','w') as f: f.write({repr(log_script)})\n"
            "PYEOF"
        )
        rss_out = exec_in_env("python3 /tmp/_rss_check.py 2>/dev/null")
        rss_out = rss_out.strip() if rss_out else "{}"
        rss_count = json.loads(rss_out).get('count', 0)
        expected = metadata.get('expected_rss_submissions', 2)
        if rss_count >= expected:
            score += 14; feedback.append(f"RSS submissions={rss_count} (>={expected}) OK")
        elif rss_count >= 1:
            score += 7; feedback.append(f"RSS submissions={rss_count} (partial, need {expected})")
        else:
            feedback.append("No RSS submissions detected")
    except Exception as e:
        feedback.append(f"RSS check error: {e}")

    # ================================================================
    # 5. Baseline timestamp (5 pts)
    # ================================================================
    try:
        ts_raw = exec_in_env("cat /tmp/task_start_timestamp 2>/dev/null")
        if ts_raw and ts_raw.strip():
            score += 5; feedback.append("Baseline timestamp valid")
    except Exception:
        pass

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback)
    }
