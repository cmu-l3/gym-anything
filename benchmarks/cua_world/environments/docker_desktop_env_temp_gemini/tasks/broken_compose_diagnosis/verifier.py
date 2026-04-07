#!/usr/bin/env python3
"""Verifier for broken_compose_diagnosis task.

Scoring (100 points):
- All 3 services running (30 pts): flask + nginx + db all in running state
- Nginx accessible HTTP 200 (25 pts): http://localhost:8080 responds
- Flask MYSQL_HOST is 'db' (25 pts): env var corrected from localhost to db
- Flask on backnet (10 pts): flask container joined the backnet network
- Volumes section present (10 pts): top-level volumes: key in docker-compose.yml

Pass threshold: 70 points
Mandatory: all 3 services must be running for pass=True
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_broken_compose_diagnosis(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_from_env("/tmp/broken_compose_diagnosis_result.json", tmp.name)
            with open(tmp.name) as f:
                result = json.load(f)
        finally:
            try:
                os.unlink(tmp.name)
            except Exception:
                pass
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found — export script may have failed"}
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0, "feedback": f"Invalid JSON in result: {e}"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error copying result: {e}"}

    score = 0
    feedback_parts = []
    details = {}

    flask_running = result.get("flask_running", False)
    nginx_running = result.get("nginx_running", False)
    db_running = result.get("db_running", False)

    # Criterion 1: All 3 services running (30 pts, partial credit)
    services_up = sum([flask_running, nginx_running, db_running])
    if services_up == 3:
        score += 30
        feedback_parts.append("All 3 services running (+30)")
    elif services_up == 2:
        score += 15
        feedback_parts.append(f"2/3 services running (+15): flask={flask_running}, nginx={nginx_running}, db={db_running}")
    elif services_up == 1:
        score += 5
        feedback_parts.append(f"1/3 services running (+5)")
    else:
        feedback_parts.append("No services running (+0)")
    details["services_up"] = services_up

    # Criterion 2: Nginx accessible HTTP 200 (25 pts)
    http_code = result.get("nginx_http_code", "000")
    if http_code in ("200", "301", "302"):
        score += 25
        feedback_parts.append(f"Nginx accessible HTTP {http_code} (+25)")
    else:
        feedback_parts.append(f"Nginx not accessible (got HTTP {http_code}) (+0)")
    details["nginx_http_code"] = http_code

    # Criterion 3: Flask MYSQL_HOST corrected to 'db' (25 pts)
    flask_mysql_host = result.get("flask_mysql_host", "").strip().lower()
    if flask_mysql_host == "db":
        score += 25
        feedback_parts.append("Flask MYSQL_HOST=db (correct) (+25)")
    elif flask_mysql_host == "localhost" or flask_mysql_host == "":
        feedback_parts.append(f"Flask MYSQL_HOST still wrong: '{flask_mysql_host}' (+0)")
    else:
        # Partial credit for something other than localhost
        score += 10
        feedback_parts.append(f"Flask MYSQL_HOST changed to '{flask_mysql_host}', but expected 'db' (+10)")
    details["flask_mysql_host"] = flask_mysql_host

    # Criterion 4: Flask on backnet (10 pts)
    flask_on_backnet = result.get("flask_on_backnet", False)
    if flask_on_backnet:
        score += 10
        feedback_parts.append("Flask joined backnet network (+10)")
    else:
        feedback_parts.append("Flask not on backnet (+0)")
    details["flask_on_backnet"] = flask_on_backnet

    # Criterion 5: Volumes section present (10 pts)
    has_volumes = result.get("has_volumes_section", False)
    if has_volumes:
        score += 10
        feedback_parts.append("Volumes section present in compose (+10)")
    else:
        feedback_parts.append("Missing top-level volumes: section (+0)")
    details["has_volumes_section"] = has_volumes

    # Pass requires all 3 services running AND score >= 70
    all_running = flask_running and nginx_running and db_running
    passed = all_running and score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": details
    }
