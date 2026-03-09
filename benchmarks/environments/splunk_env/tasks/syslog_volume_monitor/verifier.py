#!/usr/bin/env python3
"""Verifier for syslog_volume_monitor task.

Checks for ANY new scheduled report referencing system_logs with time analysis,
and ANY new dashboard with panels.

Scoring (each criterion = 20 points, total = 100):
1. At least one new saved search was created
2. Best new search references system_logs index
3. Best new search uses time-based analysis (timechart, stats by time, etc.)
4. Best new search is scheduled
5. At least one new dashboard was created with >=2 panels
"""

import json, tempfile, os, re, logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

POINTS_PER_CRITERION = 20
PASS_THRESHOLD = 80


def uses_time_analysis(search_text):
    low = search_text.lower()
    time_patterns = ['timechart', 'stats count by _time', 'span=', 'bin _time',
                     'anomalydetection', 'streamstats', 'bucket _time',
                     'stats count by date_', 'earliest=']
    return any(p in low for p in time_patterns)


def score_search(s):
    sc = 0
    low = s.get('search', '').lower()
    if 'system_logs' in low: sc += 1
    if uses_time_analysis(s.get('search', '')): sc += 1
    if s.get('is_scheduled', False): sc += 1
    return sc


def verify_syslog_volume_monitor(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/syslog_volume_monitor_result.json", tmp.name)
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
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback), "subscores": subscores, "details": {}}

    best = max(new_searches, key=score_search)
    best_search = best.get('search', '')

    # Criterion 2: references system_logs
    if 'system_logs' in best_search.lower():
        score += POINTS_PER_CRITERION
        feedback.append(f"Report '{best['name']}' references system_logs")
        subscores['references_system_logs'] = True
    else:
        feedback.append(f"FAIL: Report must reference index=system_logs")
        subscores['references_system_logs'] = False

    # Criterion 3: uses time analysis
    if uses_time_analysis(best_search):
        score += POINTS_PER_CRITERION
        feedback.append("Report uses time-based analysis (timechart/span/etc.)")
        subscores['uses_time_analysis'] = True
    else:
        feedback.append("FAIL: Report must use temporal analysis (e.g., timechart, span=1h)")
        subscores['uses_time_analysis'] = False

    # Criterion 4: is scheduled
    if best.get('is_scheduled', False):
        score += POINTS_PER_CRITERION
        feedback.append(f"Report is scheduled (cron='{best.get('cron_schedule','')}')")
        subscores['is_scheduled'] = True
    else:
        feedback.append("FAIL: Report must be scheduled")
        subscores['is_scheduled'] = False

    # Criterion 5: dashboard with >=2 panels
    best_dash = max(new_dashboards, key=lambda d: d.get('panel_count', 0)) if new_dashboards else {}
    panel_count = best_dash.get('panel_count', 0) if best_dash else 0
    if panel_count >= 2:
        score += POINTS_PER_CRITERION
        feedback.append(f"Dashboard '{best_dash.get('name','')}' created with {panel_count} panels")
        subscores['dashboard_with_panels'] = True
    elif new_dashboards:
        feedback.append(f"FAIL: Dashboard exists but has only {panel_count} panel(s), need >=2")
        subscores['dashboard_with_panels'] = False
    else:
        feedback.append("FAIL: No operational dashboard created")
        subscores['dashboard_with_panels'] = False

    return {
        "passed": score >= PASS_THRESHOLD,
        "score": score,
        "feedback": " | ".join(feedback),
        "subscores": subscores,
        "details": {
            "best_search_name": best.get('name', ''),
            "best_dashboard_name": best_dash.get('name', '') if best_dash else '',
            "search_preview": best_search[:200],
            "total_new": len(new_searches),
        }
    }
