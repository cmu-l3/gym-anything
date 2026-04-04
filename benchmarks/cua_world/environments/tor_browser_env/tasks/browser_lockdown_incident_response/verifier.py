#!/usr/bin/env python3
"""Verifier for browser_lockdown_incident_response task.

A digital forensics analyst performs a 6-step emergency browser lockdown procedure
for a compromised field operative's Tor Browser. Tests the most complex multi-feature
workflow in the benchmark.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

TASK_NAME = "browser_lockdown_incident_response"


def verify_browser_lockdown_incident_response(traj, env_info, task_info):
    """
    Scoring (100 points):

    Step 1 — Security hardening:
    1. Security level = Safest (slider=4)                        - 20 pts  [REQUIRED]

    Step 2 — Evidence capture:
    2. incident_screenshot.png exists on Desktop                 - 15 pts
    3. Screenshot file is newly created after task start         - 5 pts

    Step 3 — History export + config:
    4. check.torproject.org in browser history                   - 10 pts
    5. privacy.clearOnShutdown.history = true in prefs.js        - 10 pts

    Step 4 — Data clearing:
    6. Browser history cleared (< 5 visits remaining)            - 10 pts

    Step 5 — Configuration lock:
    7. browser.privatebrowsing.autostart = true in prefs.js      - 15 pts

    Step 6 — Incident report:
    8. incident_report.txt exists on Desktop                     - 10 pts
    9. Report is newly created and contains 'LOCKDOWN'           - 5 pts

    Pass threshold: 60+ points AND criterion 1 (Safest security) met
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        try:
            copy_from_env(f"/tmp/{TASK_NAME}_result.json", tmp.name)
            with open(tmp.name, 'r', encoding='utf-8-sig') as f:
                result = json.load(f)
        except Exception as e:
            logger.error(f"Failed to read result: {e}")
            return {"passed": False, "score": 0, "feedback": f"Result file not found: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    logger.info(f"Result: {json.dumps(result, indent=2)}")

    if not result.get('prefs_file_exists', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Tor Browser prefs.js not found — browser not used"
        }

    score = 0
    feedback_parts = []

    # Criterion 1: Security level = Safest [REQUIRED for pass]
    slider = result.get('security_slider', 1)
    security_level = result.get('security_level', 'standard')
    if slider == 4 and security_level == 'safest':
        score += 20
        feedback_parts.append("Security level = Safest (20/20)")
    elif slider == 2:
        score += 10
        feedback_parts.append("Security level = Safer (10/20) — need Safest")
    else:
        feedback_parts.append(f"Security level = {security_level} (0/20) — need Safest")

    # Criterion 2: incident_screenshot.png exists on Desktop
    ss_exists = result.get('screenshot_exists', False)
    ss_size = result.get('screenshot_size', 0)
    if ss_exists and ss_size > 1000:
        score += 15
        feedback_parts.append(f"incident_screenshot.png exists ({ss_size}B) (15/15)")
    elif ss_exists:
        score += 7
        feedback_parts.append(f"incident_screenshot.png exists but may be empty ({ss_size}B) (7/15)")
    else:
        feedback_parts.append("incident_screenshot.png NOT found on Desktop (0/15)")

    # Criterion 3: Screenshot is newly created
    if result.get('screenshot_is_new', False):
        score += 5
        feedback_parts.append("Screenshot created after task start (5/5)")
    else:
        feedback_parts.append("Screenshot predates task start (0/5)")

    # Criterion 4: check.torproject.org in history (step 3 requires visiting it)
    # Note: if history was cleared, this is still recorded as having been visited
    # since places.sqlite may retain URL data even after clearing visits
    if result.get('history_has_check_torproject', False):
        score += 10
        feedback_parts.append("Visited check.torproject.org (10/10)")
    else:
        # History was cleared — check if there was evidence it was visited
        # (if history_cleared=true and count=0, agent may have done both steps)
        if result.get('history_cleared', False):
            score += 5
            feedback_parts.append("History cleared — check.torproject.org visit cannot be confirmed (5/10)")
        else:
            feedback_parts.append("check.torproject.org NOT in history (0/10)")

    # Criterion 5: privacy.clearOnShutdown.history = true
    if result.get('clear_history_on_shutdown', False):
        score += 10
        feedback_parts.append("privacy.clearOnShutdown.history = true (10/10)")
    else:
        feedback_parts.append("privacy.clearOnShutdown.history NOT set (0/10)")

    # Criterion 6: Browser history cleared
    if result.get('history_cleared', False):
        score += 10
        history_count = result.get('history_count', 0)
        feedback_parts.append(f"Browser history cleared ({history_count} visits remaining) (10/10)")
    else:
        history_count = result.get('history_count', 0)
        feedback_parts.append(f"Browser history NOT cleared ({history_count} visits remain) (0/10)")

    # Criterion 7: browser.privatebrowsing.autostart = true
    if result.get('autostart_private_browsing', False):
        score += 15
        feedback_parts.append("browser.privatebrowsing.autostart = true (15/15)")
    else:
        feedback_parts.append("browser.privatebrowsing.autostart NOT set (0/15)")

    # Criterion 8: incident_report.txt exists
    report_exists = result.get('report_exists', False)
    report_size = result.get('report_size', 0)
    if report_exists and report_size > 0:
        score += 10
        feedback_parts.append(f"incident_report.txt exists ({report_size}B) (10/10)")
    else:
        feedback_parts.append("incident_report.txt NOT found on Desktop (0/10)")

    # Criterion 9: Report is new and contains 'LOCKDOWN'
    report_new = result.get('report_is_new', False)
    report_has_lockdown = result.get('report_has_lockdown', False)
    if report_exists and report_new and report_has_lockdown:
        score += 5
        feedback_parts.append("Report is new and contains 'LOCKDOWN' text (5/5)")
    elif report_exists and report_new:
        score += 2
        feedback_parts.append("Report is new but missing 'LOCKDOWN' text (2/5)")
    else:
        feedback_parts.append("Report not new or doesn't contain required text (0/5)")

    # Pass: score >= 60 AND security level = Safest
    security_ok = (slider == 4)
    passed = score >= 60 and security_ok

    feedback = " | ".join(feedback_parts)
    logger.info(f"Score: {score}/100, Passed: {passed}")

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": feedback,
        "subscores": {
            "security_safest": 20 if (slider == 4) else (10 if slider == 2 else 0),
            "screenshot_exists": 15 if (ss_exists and ss_size > 1000) else (7 if ss_exists else 0),
            "screenshot_new": 5 if result.get('screenshot_is_new') else 0,
            "visited_torproject": 10 if result.get('history_has_check_torproject') else (5 if result.get('history_cleared') else 0),
            "clear_on_shutdown": 10 if result.get('clear_history_on_shutdown') else 0,
            "history_cleared": 10 if result.get('history_cleared') else 0,
            "autostart_private": 15 if result.get('autostart_private_browsing') else 0,
            "report_exists": 10 if (report_exists and report_size > 0) else 0,
            "report_content": 5 if (report_exists and report_new and report_has_lockdown) else (2 if (report_exists and report_new) else 0),
        }
    }
