#!/usr/bin/env python3
"""Verifier for franchise_social_media_buildout."""

import json
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def _query(exec_in_env, sql):
    safe_sql = sql.replace('"', '\\"')
    cmd = f'mysql -u root socioboard -N -B -e "{safe_sql}" 2>/dev/null'
    try:
        out = exec_in_env(cmd)
        return out.strip() if out else ""
    except Exception as exc:
        logger.warning("Query failed: %s", exc)
        return ""


def _member_check(exec_in_env, team_name, email):
    safe_team = team_name.replace("'", "\\'")
    sql = (
        "SELECT COUNT(*) FROM join_table_users_teams jt "
        "JOIN team_informations ti ON jt.team_id = ti.team_id "
        "JOIN user_details ud ON jt.user_id = ud.user_id "
        f"WHERE ti.team_name = '{safe_team}' AND ud.email = '{email}'"
    )
    result = _query(exec_in_env, sql)
    return result and int(result) > 0


def _rss_submitted(exec_in_env):
    raw = exec_in_env("python3 - <<'PY'\nimport json, pathlib\nbaseline = int(pathlib.Path('/tmp/rss_log_baseline').read_text().strip() or '0')\nlog = pathlib.Path('/var/log/apache2/socioboard_access.log')\nlines = log.read_text(errors='ignore').splitlines() if log.exists() else []\nprint(json.dumps({'found': any('POST /getRss' in line for line in lines[baseline:])}))\nPY")
    try:
        return json.loads(raw.strip()).get("found", False)
    except Exception:
        return False


def verify_franchise_social_media_buildout(traj, env_info, task_info):
    exec_in_env = env_info.get("exec_in_env") or env_info.get("exec_capture")
    if not exec_in_env:
        return {"passed": False, "score": 0, "feedback": "exec_in_env not available"}

    metadata = task_info.get("metadata", {})
    score = 0
    feedback = []

    profile = _query(
        exec_in_env,
        "SELECT first_name, last_name, about_me, phone_no, time_zone "
        "FROM user_details WHERE email = 'admin@socioboard.local' LIMIT 1",
    )
    if not profile:
        return {"passed": False, "score": 0, "feedback": "Admin user not found in DB"}

    parts = profile.split("\t")
    first_name = parts[0].strip() if len(parts) > 0 else ""
    last_name = parts[1].strip() if len(parts) > 1 else ""
    about_me = parts[2].strip() if len(parts) > 2 else ""
    phone_no = parts[3].strip() if len(parts) > 3 else ""
    timezone = parts[4].strip() if len(parts) > 4 else ""

    if first_name == metadata.get("expected_first_name", "Marcus"):
        score += 5
        feedback.append("First name updated.")
    else:
        feedback.append(f"First name is '{first_name}'.")

    if last_name == metadata.get("expected_last_name", "Whitfield"):
        score += 5
        feedback.append("Last name updated.")
    else:
        feedback.append(f"Last name is '{last_name}'.")

    if metadata.get("expected_about_fragment", "") in about_me and metadata.get("expected_about_fragment_2", "") in about_me:
        score += 10
        feedback.append("About text updated.")
    else:
        feedback.append("About text missing expected fragments.")

    if timezone == metadata.get("expected_timezone", "America/New_York"):
        score += 5
        feedback.append("Timezone updated.")
    else:
        feedback.append(f"Timezone is '{timezone}'.")

    if metadata.get("expected_phone", "") in phone_no:
        score += 5
        feedback.append("Phone updated.")
    else:
        feedback.append(f"Phone is '{phone_no}'.")

    teams = metadata.get("teams", [])
    for team_name in teams:
        safe_team = team_name.replace("'", "\\'")
        count = _query(
            exec_in_env,
            f"SELECT COUNT(*) FROM team_informations WHERE team_name = '{safe_team}'",
        )
        if count and int(count) > 0:
            score += 6
            feedback.append(f"Team '{team_name}' exists.")
        else:
            feedback.append(f"Team '{team_name}' missing.")

    member_email = metadata.get("member_email", "john.smith@socioboard.local")
    for team_name in metadata.get("john_smith_teams", []):
        if _member_check(exec_in_env, team_name, member_email):
            score += 10
            feedback.append(f"{member_email} is in '{team_name}'.")
        else:
            feedback.append(f"{member_email} missing from '{team_name}'.")

    for team_name in metadata.get("john_smith_excluded_teams", []):
        if not _member_check(exec_in_env, team_name, member_email):
            score += 5
            feedback.append(f"{member_email} correctly excluded from '{team_name}'.")
        else:
            feedback.append(f"{member_email} wrongly added to '{team_name}'.")

    if _rss_submitted(exec_in_env):
        score += 10
        feedback.append("RSS feed was submitted through the UI.")
    else:
        feedback.append("No RSS submission detected in the Socioboard access log.")

    passed = score >= 70
    return {"passed": passed, "score": score, "feedback": " | ".join(feedback)}
