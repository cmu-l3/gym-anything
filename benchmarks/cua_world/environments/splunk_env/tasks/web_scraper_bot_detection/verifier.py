#!/usr/bin/env python3
"""Verifier for web_scraper_bot_detection task."""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

POINTS_PER_CRITERION = 20
PASS_THRESHOLD = 60

def normalize_name(name):
    """Normalize object names for comparison (case-insensitive, convert spaces to underscores)."""
    return name.lower().replace(' ', '_').replace('-', '_')

def check_ip_aggregation(spl):
    """Check if SPL search aggregates by an IP field."""
    spl_lower = spl.lower()
    return re.search(r'(?:stats|chart|timechart)\s+.*?by\s+[a-z_]*ip', spl_lower) is not None

def check_multi_metric(spl):
    """Check if SPL search calculates both count (requests) and sum (bytes)."""
    spl_lower = spl.lower()
    has_count = 'count' in spl_lower or ' c ' in spl_lower or 'c(' in spl_lower
    has_sum = 'sum(' in spl_lower
    return has_count and has_sum

def check_threshold(spl):
    """Check if SPL search applies a post-aggregation threshold filter > 200."""
    spl_lower = spl.lower()
    return re.search(r'>\s*200', spl_lower) is not None or re.search(r'>=\s*201', spl_lower) is not None

def check_real_data(spl):
    """Check if SPL search uses real data instead of generator functions like makeresults."""
    spl_lower = spl.lower()
    if 'makeresults' in spl_lower:
        return False
    return True

def verify_web_scraper_bot_detection(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_report_name = normalize_name(metadata.get('expected_report_name', 'Aggressive_Scraper_Report'))
    expected_dashboard_name = normalize_name(metadata.get('expected_dashboard_name', 'Bot_Activity_Dashboard'))

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", tmp.name)
        with open(tmp.name, 'r') as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    analysis = data.get('analysis', {})
    new_searches = analysis.get('new_searches', [])
    new_dashboards = analysis.get('new_dashboards', [])

    score = 0
    feedback = []
    subscores = {}

    # Identify the best matching report
    best_report = None
    for s in new_searches:
        if normalize_name(s.get('name', '')) == expected_report_name:
            best_report = s
            break
    if not best_report and new_searches:
        # Fallback to the latest search created if exact name is missed
        best_report = new_searches[-1]

    # Criterion 1: Report exists and queries real data (20 pts)
    if best_report:
        spl = best_report.get('search', '')
        if check_real_data(spl):
            score += POINTS_PER_CRITERION
            feedback.append(f"Report '{best_report.get('name')}' created using real data")
            subscores['report_exists'] = True
        else:
            feedback.append("FAIL: Report uses 'makeresults' instead of querying real data")
            subscores['report_exists'] = False
    else:
        feedback.append("FAIL: No new saved report created")
        subscores['report_exists'] = False

    # Proceed with SPL checks if a valid report exists
    spl = best_report.get('search', '') if best_report else ""

    # Criterion 2: Aggregates by IP (20 pts)
    if spl and check_ip_aggregation(spl):
        score += POINTS_PER_CRITERION
        feedback.append("SPL aggregates by IP successfully")
        subscores['aggregates_by_ip'] = True
    else:
        feedback.append("FAIL: SPL does not aggregate by an IP field")
        subscores['aggregates_by_ip'] = False

    # Criterion 3: Multi-metric (20 pts)
    if spl and check_multi_metric(spl):
        score += POINTS_PER_CRITERION
        feedback.append("SPL calculates multiple metrics (count and sum)")
        subscores['multi_metric'] = True
    else:
        feedback.append("FAIL: SPL does not compute both request count and byte volume")
        subscores['multi_metric'] = False

    # Criterion 4: Threshold filter (20 pts)
    if spl and check_threshold(spl):
        score += POINTS_PER_CRITERION
        feedback.append("SPL applies correct >200 threshold filter")
        subscores['threshold_filter'] = True
    else:
        feedback.append("FAIL: SPL does not apply a >200 post-aggregation threshold")
        subscores['threshold_filter'] = False

    # Criterion 5: Dashboard valid with >= 2 panels (20 pts)
    best_dash = None
    for d in new_dashboards:
        if normalize_name(d.get('name', '')) == expected_dashboard_name:
            best_dash = d
            break
    if not best_dash and new_dashboards:
        # Fallback to the dashboard with the most panels if exact name is missed
        best_dash = max(new_dashboards, key=lambda x: x.get('panel_count', 0))

    if best_dash:
        panels = best_dash.get('panel_count', 0)
        if panels >= 2:
            score += POINTS_PER_CRITERION
            feedback.append(f"Dashboard '{best_dash.get('name')}' created with {panels} panels")
            subscores['dashboard_valid'] = True
        else:
            feedback.append(f"FAIL: Dashboard has {panels} panels (needs at least 2)")
            subscores['dashboard_valid'] = False
    else:
        feedback.append("FAIL: No new dashboard created")
        subscores['dashboard_valid'] = False

    passed = score >= PASS_THRESHOLD

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "subscores": subscores,
        "details": {
            "spl_query": spl,
            "new_reports_count": len(new_searches),
            "new_dashboards_count": len(new_dashboards)
        }
    }