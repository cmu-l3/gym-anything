#!/usr/bin/env python3
"""Verifier for soc_executive_dashboard task.

Checks for ANY new dashboard with >=3 panels referencing security_logs,
and ANY new scheduled alert with a numeric threshold condition.

Scoring (each criterion = 20 points, total = 100):
1. At least one new dashboard was created
2. Best dashboard has >=3 panels
3. Best dashboard panel searches reference security_logs index
4. At least one new scheduled alert was created
5. Best new scheduled alert search contains a numeric threshold condition
"""

import json, tempfile, os, re, logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

POINTS_PER_CRITERION = 20
PASS_THRESHOLD = 80


def has_numeric_threshold(search_text):
    low = search_text.lower()
    patterns = [
        r'where\s+count\s*[><=]+\s*\d+',
        r'count\s*[><=]+\s*\d+',
        r'where\s+\w+\s*[><=]+\s*\d+',
    ]
    for p in patterns:
        if re.search(p, low):
            return True
    return False


def verify_soc_executive_dashboard(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/soc_executive_dashboard_result.json", tmp.name)
        with open(tmp.name) as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(tmp.name): os.unlink(tmp.name)

    analysis = data.get('analysis', {})
    new_dashboards = analysis.get('new_dashboards', [])
    new_alerts = analysis.get('new_alerts', [])

    score = 0
    feedback = []
    subscores = {}

    # Criterion 1: new dashboard created
    best_dash = max(new_dashboards, key=lambda d: d.get('panel_count', 0)) if new_dashboards else {}
    if new_dashboards:
        score += POINTS_PER_CRITERION
        feedback.append(f"New dashboard(s) created: {[d['name'] for d in new_dashboards[:3]]}")
        subscores['dashboard_created'] = True
    else:
        feedback.append("FAIL: No new dashboard created")
        subscores['dashboard_created'] = False

    # Criterion 2: dashboard has >=3 panels
    panel_count = best_dash.get('panel_count', 0) if best_dash else 0
    if panel_count >= 3:
        score += POINTS_PER_CRITERION
        feedback.append(f"Dashboard '{best_dash.get('name','')}' has {panel_count} panels (>=3)")
        subscores['dashboard_has_3_panels'] = True
    elif panel_count > 0:
        feedback.append(f"FAIL: Dashboard has {panel_count} panel(s), need at least 3")
        subscores['dashboard_has_3_panels'] = False
    else:
        feedback.append("FAIL: No dashboard panels found")
        subscores['dashboard_has_3_panels'] = False

    # Criterion 3: dashboard references security_logs
    refs_sec = best_dash.get('refs_security_logs', False) if best_dash else False
    if refs_sec:
        score += POINTS_PER_CRITERION
        feedback.append("Dashboard panel searches reference security_logs index")
        subscores['dashboard_refs_security_logs'] = True
    else:
        feedback.append("FAIL: Dashboard panels must reference security_logs index")
        subscores['dashboard_refs_security_logs'] = False

    # Criterion 4: new scheduled alert created
    scheduled_alerts = [a for a in new_alerts if a.get('is_scheduled', False)]
    best_alert = max(scheduled_alerts, key=lambda a: 1 if has_numeric_threshold(a.get('search','')) else 0) if scheduled_alerts else {}
    if scheduled_alerts:
        score += POINTS_PER_CRITERION
        feedback.append(f"Scheduled alert created: '{best_alert.get('name','')}'")
        subscores['scheduled_alert_created'] = True
    else:
        feedback.append("FAIL: No new scheduled alert created")
        subscores['scheduled_alert_created'] = False

    # Criterion 5: alert has numeric threshold
    has_threshold = has_numeric_threshold(best_alert.get('search', '')) if best_alert else False
    if has_threshold:
        score += POINTS_PER_CRITERION
        feedback.append("Alert search contains numeric threshold condition (count > N)")
        subscores['alert_has_threshold'] = True
    else:
        feedback.append("FAIL: Alert search must contain a threshold (e.g., 'where count > 50')")
        subscores['alert_has_threshold'] = False

    return {
        "passed": score >= PASS_THRESHOLD,
        "score": score,
        "feedback": " | ".join(feedback),
        "subscores": subscores,
        "details": {
            "best_dashboard_name": best_dash.get('name', '') if best_dash else '',
            "dashboard_panel_count": panel_count,
            "best_alert_name": best_alert.get('name', '') if best_alert else '',
            "alert_cron": best_alert.get('cron_schedule', '') if best_alert else '',
            "total_new_dashboards": len(new_dashboards),
            "total_new_alerts": len(new_alerts),
        }
    }
