#!/usr/bin/env python3
"""Verifier for vendor_onboarding_content_workflow task.

Online Merchant scenario: fix profile, create 3 teams, invite 2 users
selectively, add RSS feed. Contaminator teams must remain.

Scoring (100 points):
- Profile: first_name (5), last_name (5), about_fragment1 (5),
  about_fragment2 (5), timezone (5), phone (5) = 30 pts
- Teams: 3 × 8 pts = 24 pts
- emily.chen correct teams: 2 × 5 pts = 10 pts
- emily.chen excluded: 1 × 4 pts = 4 pts
- john.smith correct teams: 1 × 5 pts = 5 pts
- john.smith excluded: 2 × 4 pts = 8 pts
- Contaminator teams untouched: 2 × 3 pts = 6 pts
- RSS: 8 pts
- Baseline timestamp check: 5 pts
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


def _check_membership(exec_in_env, email, team_name):
    result = _query(exec_in_env,
        f"SELECT COUNT(*) FROM join_table_users_teams jt "
        f"JOIN team_informations ti ON jt.team_id = ti.team_id "
        f"JOIN user_details ud ON jt.user_id = ud.user_id "
        f"WHERE ti.team_name = '{team_name}' AND ud.email = '{email}'")
    return result and int(result) > 0


def verify_vendor_onboarding_content_workflow(traj, env_info, task_info):
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
        (first_name == metadata.get('expected_first_name', 'David'), 5,
         f"first_name='{first_name}'"),
        (last_name == metadata.get('expected_last_name', 'Nakamura'), 5,
         f"last_name='{last_name}'"),
        (metadata.get('expected_about_fragment', 'Riverside Retail') in about_me, 5,
         "about_me contains company"),
        (metadata.get('expected_about_fragment_2', 'social commerce').lower() in about_me.lower(), 5,
         "about_me contains strategy"),
        (timezone == metadata.get('expected_timezone', 'America/Chicago'), 5,
         f"timezone='{timezone}'"),
        (metadata.get('expected_phone', '3125551847') in phone_no, 5,
         f"phone='{phone_no}'"),
    ]
    for passed, pts, desc in checks:
        if passed:
            score += pts
            feedback.append(f"{desc} OK")
        else:
            feedback.append(f"{desc} FAIL")

    # ================================================================
    # 2. Team existence (24 pts)
    # ================================================================
    for team_name in metadata.get('teams', []):
        exists = _query(exec_in_env,
            f"SELECT COUNT(*) FROM team_informations WHERE team_name = '{team_name}'")
        if exists and int(exists) > 0:
            score += 8; feedback.append(f"Team '{team_name}' exists")
        else:
            feedback.append(f"Team '{team_name}' MISSING")

    # ================================================================
    # 3. emily.chen membership (14 pts)
    # ================================================================
    emily_email = metadata.get('emily_email', 'emily.chen@socioboard.local')
    for team_name in metadata.get('emily_teams', []):
        if _check_membership(exec_in_env, emily_email, team_name):
            score += 5; feedback.append(f"emily in '{team_name}' OK")
        else:
            feedback.append(f"emily NOT in '{team_name}'")

    for team_name in metadata.get('emily_excluded_teams', []):
        if not _check_membership(exec_in_env, emily_email, team_name):
            score += 4; feedback.append(f"emily correctly NOT in '{team_name}'")
        else:
            feedback.append(f"emily wrongly in '{team_name}'")

    # ================================================================
    # 4. john.smith membership (13 pts)
    # ================================================================
    john_email = metadata.get('john_email', 'john.smith@socioboard.local')
    for team_name in metadata.get('john_teams', []):
        if _check_membership(exec_in_env, john_email, team_name):
            score += 5; feedback.append(f"john in '{team_name}' OK")
        else:
            feedback.append(f"john NOT in '{team_name}'")

    for team_name in metadata.get('john_excluded_teams', []):
        if not _check_membership(exec_in_env, john_email, team_name):
            score += 4; feedback.append(f"john correctly NOT in '{team_name}'")
        else:
            feedback.append(f"john wrongly in '{team_name}'")

    # ================================================================
    # 5. Contaminator teams (6 pts)
    # ================================================================
    for team_name in metadata.get('contaminator_teams', []):
        exists = _query(exec_in_env,
            f"SELECT COUNT(*) FROM team_informations WHERE team_name = '{team_name}'")
        if exists and int(exists) > 0:
            score += 3; feedback.append(f"Contaminator '{team_name}' untouched")
        else:
            feedback.append(f"Contaminator '{team_name}' was removed")

    # ================================================================
    # 6. RSS check (8 pts)
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
        "print(json.dumps({'found': 'POST /getRss' in tail.stdout}))\n"
    )
    try:
        exec_in_env(
            "python3 - << 'PYEOF'\n"
            f"with open('/tmp/_rss_check.py','w') as f: f.write({repr(log_script)})\n"
            "PYEOF"
        )
        rss_out = exec_in_env("python3 /tmp/_rss_check.py 2>/dev/null")
        rss_out = rss_out.strip() if rss_out else "{}"
        if json.loads(rss_out).get('found'):
            score += 8; feedback.append("RSS submitted OK")
        else:
            feedback.append("No RSS submission detected")
    except Exception as e:
        feedback.append(f"RSS check error: {e}")

    # ================================================================
    # 7. Baseline timestamp (5 pts)
    # ================================================================
    try:
        ts_raw = exec_in_env("cat /tmp/task_start_timestamp 2>/dev/null")
        if ts_raw and ts_raw.strip():
            score += 5; feedback.append("Baseline timestamp valid")
        else:
            feedback.append("No baseline timestamp")
    except Exception:
        feedback.append("Timestamp check failed")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback)
    }
