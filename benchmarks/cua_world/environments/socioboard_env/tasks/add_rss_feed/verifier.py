#!/usr/bin/env python3
"""Verifier for add_rss_feed task.

Two-step verification:
1. Check Apache access log for POST /getRss after task start baseline.
   This confirms the agent actually submitted the RSS form through the UI
   (the form submits via AJAX POST to /getRss on the PHP backend).
2. Verify the feed URL returns articles via the Socioboard feeds API.
   This confirms the correct BBC URL was used (not just any form submission).

Note: Socioboard does not persist RSS feed subscriptions in the database;
feeds are fetched on-demand. The Apache log check is the authoritative signal
that the agent interacted with the RSS Content Manager UI.
"""

import json
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Script to check Apache log for agent's POST /getRss request
LOG_CHECK_SCRIPT = '''import subprocess, json, sys

# Read baseline line count recorded during setup_task.sh
try:
    with open('/tmp/rss_log_baseline') as f:
        baseline = int(f.read().strip())
except Exception:
    baseline = 0

# Get log lines after the baseline (i.e., after task started)
tail_result = subprocess.run(
    ['sudo', 'tail', '-n', '+' + str(baseline + 1),
     '/var/log/apache2/socioboard_access.log'],
    capture_output=True, text=True
)

lines_after = tail_result.stdout
found = 'POST /getRss' in lines_after

print(json.dumps({
    "found_getRss": found,
    "baseline": baseline,
    "lines_checked": len(lines_after.splitlines())
}))
'''

# Script to verify the RSS feed URL returns articles via feeds API
RSS_VERIFY_SCRIPT = '''import subprocess, json, tempfile, os, sys, urllib.parse

admin_email = "admin@socioboard.local"
admin_pass = "Admin2024!"
rss_url = "__RSS_URL__"

# Login to get JWT
login_body = {"user": admin_email, "password": admin_pass}
with tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=False) as f:
    json.dump(login_body, f)
    login_tmp = f.name

result = subprocess.run(
    ["curl", "-s", "-X", "POST", "-H", "Content-Type: application/json",
     "-d", "@" + login_tmp, "http://127.0.0.1:3000/v1/login"],
    capture_output=True, text=True, timeout=30
)
os.unlink(login_tmp)

try:
    login_data = json.loads(result.stdout)
    token = login_data.get("accessToken", "")
except Exception as e:
    print(json.dumps({"success": False, "error": "Login failed: " + str(e)}))
    sys.exit(0)

if not token:
    print(json.dumps({"success": False, "error": "No token in login response"}))
    sys.exit(0)

# Call feeds API with the RSS URL
encoded_url = urllib.parse.quote(rss_url, safe="")
feeds_result = subprocess.run(
    ["curl", "-s", "-m", "20",
     "-H", "x-access-token: " + token,
     "-H", "Content-Type: application/json",
     "http://127.0.0.1:3002/v1/trends/getRssFeeds?rssUrl=" + encoded_url],
    capture_output=True, text=True, timeout=35
)

try:
    feeds_data = json.loads(feeds_result.stdout)
    code = feeds_data.get("code", 0)
    articles = feeds_data.get("response", [])
    article_count = len(articles) if isinstance(articles, list) else 0
    first_title = articles[0].get("title", "") if articles else ""
    print(json.dumps({
        "success": code == 200 and article_count > 0,
        "code": code,
        "article_count": article_count,
        "first_title": first_title
    }))
except Exception as e:
    print(json.dumps({"success": False, "error": str(e), "raw": feeds_result.stdout[:200]}))
'''


def verify_add_rss_feed(traj, env_info, task_info):
    """Verify that the BBC Technology RSS feed was added through the UI.

    Step 1: Check Apache access log for POST /getRss after task start.
    Step 2: Verify the feed URL returns articles.
    """
    exec_in_env = env_info.get('exec_in_env')
    if not exec_in_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "exec_in_env not available in env_info"
        }

    metadata = task_info.get('metadata', {})
    feed_url = metadata.get('feed_url', 'https://feeds.bbci.co.uk/news/technology/rss.xml')
    feed_name = metadata.get('feed_name', 'BBC Technology News')

    # --- Step 1: Check Apache log for agent's form submission ---
    write_cmd = (
        "python3 - << 'PYEOF'\n"
        "import sys\n"
        f"with open('/tmp/log_check.py','w') as f:\n"
        f"    f.write({repr(LOG_CHECK_SCRIPT)})\n"
        "print('written')\n"
        "PYEOF"
    )
    try:
        exec_in_env(write_cmd)
        log_output = exec_in_env("python3 /tmp/log_check.py 2>/dev/null")
        log_output = log_output.strip() if log_output else "{}"
        logger.info(f"Log check output: {log_output}")
        log_data = json.loads(log_output)
    except Exception as e:
        logger.warning(f"Apache log check failed: {e}")
        log_data = {"found_getRss": False, "baseline": 0, "lines_checked": 0}

    agent_interacted = log_data.get("found_getRss", False)
    logger.info(
        f"Agent interaction: {agent_interacted} "
        f"(baseline={log_data.get('baseline')}, "
        f"lines_after={log_data.get('lines_checked')})"
    )

    if not agent_interacted:
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                "No RSS form submission detected in Apache logs. "
                "The agent must navigate to Discovery > RSS Content Manager, "
                "enter the Feed Name and Feed URL, and click 'Add Feed'."
            )
        }

    # --- Step 2: Verify feed URL returns articles ---
    script_content = RSS_VERIFY_SCRIPT.replace('__RSS_URL__', feed_url)
    write_cmd2 = (
        "python3 - << 'PYEOF'\n"
        "import sys\n"
        f"with open('/tmp/rss_verify.py','w') as f:\n"
        f"    f.write({repr(script_content)})\n"
        "print('written')\n"
        "PYEOF"
    )
    try:
        exec_in_env(write_cmd2)
        output = exec_in_env("python3 /tmp/rss_verify.py 2>/dev/null")
        output = output.strip() if output else "{}"
        logger.info(f"RSS verify output: {output[:300]}")
        result_data = json.loads(output)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"RSS feed verification failed: {e}"
        }

    if result_data.get('success') and result_data.get('article_count', 0) > 0:
        article_count = result_data['article_count']
        first_title = result_data.get('first_title', '')
        return {
            "passed": True,
            "score": 100,
            "feedback": (
                f"RSS feed '{feed_name}' added via UI and returns {article_count} articles. "
                f"First article: '{first_title[:60]}'"
            )
        }
    else:
        error = result_data.get('error', '')
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                f"RSS form was submitted but feed validation failed. "
                f"Code: {result_data.get('code')}, "
                f"Articles: {result_data.get('article_count', 0)}"
                + (f", Error: {error}" if error else "")
            )
        }
