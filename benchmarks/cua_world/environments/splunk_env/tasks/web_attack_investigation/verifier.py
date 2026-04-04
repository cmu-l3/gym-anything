#!/usr/bin/env python3
"""Verifier for web_attack_investigation task.

Checks for ANY new cross-index saved report and ANY new dashboard with panels,
regardless of what the agent named them.

Scoring (each criterion = 20 points, total = 100):
1. At least one new saved search was created
2. Best new search is cross-index (queries both web and security log sources)
3. At least one new dashboard was created
4. Best new dashboard has >=2 panels
5. Best new dashboard panel searches reference security or web log indexes
"""

import json, tempfile, os, re, logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

POINTS_PER_CRITERION = 20
PASS_THRESHOLD = 80


def is_cross_index(search_text):
    low = search_text.lower()
    has_web = 'web_logs' in low or 'apache' in low
    has_security = 'security_logs' in low or 'ssh' in low
    if 'index=*' in low or 'index = *' in low:
        return True
    return has_web and has_security


def verify_web_attack_investigation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/web_attack_investigation_result.json", tmp.name)
        with open(tmp.name) as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(tmp.name): os.unlink(tmp.name)

    analysis = data.get('analysis', {})
    new_searches = analysis.get('new_searches', [])
    new_dashboards = analysis.get('new_dashboards', [])

    score = 0
    feedback = []
    subscores = {}

    # Criterion 1: new search created
    if new_searches:
        score += POINTS_PER_CRITERION
        feedback.append(f"New report(s) created: {[s['name'] for s in new_searches[:3]]}")
        subscores['new_report_created'] = True
    else:
        feedback.append("FAIL: No new saved searches or reports created")
        subscores['new_report_created'] = False

    # Criterion 2: best new search is cross-index
    best_search = max(new_searches, key=lambda s: 1 if is_cross_index(s.get('search','')) else 0) if new_searches else {}
    cross_idx = is_cross_index(best_search.get('search', '')) if best_search else False
    if cross_idx:
        score += POINTS_PER_CRITERION
        feedback.append(f"Report '{best_search.get('name','')}' correlates across web and security log sources")
        subscores['report_cross_index'] = True
    else:
        feedback.append("FAIL: Report must query BOTH web_logs and security_logs (or use index=*)")
        subscores['report_cross_index'] = False

    # Criterion 3: new dashboard created
    if new_dashboards:
        score += POINTS_PER_CRITERION
        feedback.append(f"New dashboard(s) created: {[d['name'] for d in new_dashboards[:3]]}")
        subscores['new_dashboard_created'] = True
    else:
        feedback.append("FAIL: No new dashboard created")
        subscores['new_dashboard_created'] = False

    # Criterion 4: best dashboard has >=2 panels
    best_dash = max(new_dashboards, key=lambda d: d.get('panel_count', 0)) if new_dashboards else {}
    panel_count = best_dash.get('panel_count', 0) if best_dash else 0
    if panel_count >= 2:
        score += POINTS_PER_CRITERION
        feedback.append(f"Dashboard '{best_dash.get('name','')}' has {panel_count} panels (>=2)")
        subscores['dashboard_has_multiple_panels'] = True
    elif panel_count == 1:
        feedback.append(f"FAIL: Dashboard has only 1 panel, need at least 2")
        subscores['dashboard_has_multiple_panels'] = False
    else:
        feedback.append("FAIL: Dashboard has no panels or none found")
        subscores['dashboard_has_multiple_panels'] = False

    # Criterion 5: dashboard references log indexes
    refs_logs = best_dash.get('refs_logs', False) if best_dash else False
    if refs_logs:
        score += POINTS_PER_CRITERION
        feedback.append("Dashboard panel searches reference security/web log indexes")
        subscores['dashboard_refs_logs'] = True
    else:
        feedback.append("FAIL: Dashboard panels must reference security_logs or web_logs")
        subscores['dashboard_refs_logs'] = False

    return {
        "passed": score >= PASS_THRESHOLD,
        "score": score,
        "feedback": " | ".join(feedback),
        "subscores": subscores,
        "details": {
            "best_search_name": best_search.get('name', ''),
            "best_dashboard_name": best_dash.get('name', ''),
            "best_dashboard_panels": panel_count,
            "total_new_searches": len(new_searches),
            "total_new_dashboards": len(new_dashboards),
        }
    }
