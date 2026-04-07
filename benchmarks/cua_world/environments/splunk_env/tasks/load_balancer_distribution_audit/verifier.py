#!/usr/bin/env python3
"""
Verifier for load_balancer_distribution_audit task.

Evaluation Criteria (Total 100 points, Pass >= 80):
1. Alert 'Unbalanced_Load_Alert' exists and is scheduled. (20 pts)
2. Alert logic properly uses 'tutorial' index, groups by 'host', and thresholds at >40%. (20 pts)
3. Dashboard 'Web_Infrastructure_Health' exists. (20 pts)
4. Dashboard has a Distribution panel grouping by 'host'. (20 pts)
5. Dashboard has an Error Rate panel filtering for errors (status >= 400) and grouping by 'host'. (20 pts)

Anti-Gaming Check:
- Fast completion times (< 10 seconds) fail immediately.
"""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_load_balancer_audit(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_alert_name = metadata.get('alert_name', 'Unbalanced_Load_Alert').lower()
    expected_dashboard_name = metadata.get('dashboard_name', 'Web_Infrastructure_Health').lower()

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/load_balancer_audit_result.json", tmp.name)
        with open(tmp.name) as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(tmp.name): 
            os.unlink(tmp.name)

    duration = data.get('task_duration_seconds', 0)
    if duration < 10:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Task completed suspiciously fast ({duration}s). Anti-gaming triggered."
        }

    analysis = data.get('analysis', {})
    new_alerts = analysis.get('new_alerts', [])
    new_dashboards = analysis.get('new_dashboards', [])

    score = 0
    feedback = []

    # ==========================================
    # 1. Alert Exists & Scheduled (20 points)
    # ==========================================
    target_alert = None
    for alert in new_alerts:
        if expected_alert_name in alert.get('name', '').lower().replace(' ', '_'):
            target_alert = alert
            break
            
    if not target_alert and new_alerts:
        # Fallback to the first new alert if exact name wasn't matched but one was created
        target_alert = new_alerts[0]

    if target_alert:
        if target_alert.get('is_scheduled'):
            score += 20
            feedback.append(f"Alert '{target_alert['name']}' exists and is scheduled.")
        else:
            score += 10
            feedback.append(f"Alert '{target_alert['name']}' exists but is NOT scheduled.")
    else:
        feedback.append(f"FAIL: Expected alert '{expected_alert_name}' was not created.")

    # ==========================================
    # 2. Alert Logic Correctness (20 points)
    # ==========================================
    if target_alert:
        search_query = target_alert.get('search', '').lower()
        has_index = 'tutorial' in search_query
        groups_by_host = 'by host' in search_query or 'by "host"' in search_query
        
        # Checking for standard >40 or >0.4 or >.4 checks
        threshold_pattern = r'>\s*(?:40|0\.4|\.4)'
        has_threshold = bool(re.search(threshold_pattern, search_query))

        if has_index and groups_by_host and has_threshold:
            score += 20
            feedback.append("Alert logic contains index=tutorial, groups by host, and thresholds at 40%.")
        else:
            partial = 0
            if has_index: partial += 5
            if groups_by_host: partial += 5
            if has_threshold: partial += 10
            score += partial
            feedback.append(f"Alert logic partial match (+{partial} pts). Needed index=tutorial, 'by host', and '> 40'. Got: {search_query}")
    else:
        feedback.append("FAIL: Cannot evaluate alert logic without the alert.")

    # ==========================================
    # 3. Dashboard Exists (20 points)
    # ==========================================
    target_dashboard = None
    for dash in new_dashboards:
        if expected_dashboard_name in dash.get('name', '').lower().replace(' ', '_'):
            target_dashboard = dash
            break
            
    if not target_dashboard and new_dashboards:
        target_dashboard = new_dashboards[0]

    if target_dashboard:
        score += 20
        feedback.append(f"Dashboard '{target_dashboard['name']}' exists.")
    else:
        feedback.append(f"FAIL: Expected dashboard '{expected_dashboard_name}' was not created.")

    # ==========================================
    # 4 & 5. Dashboard Panels (40 points total)
    # ==========================================
    dist_panel_found = False
    error_panel_found = False

    if target_dashboard:
        panel_searches = target_dashboard.get('panel_searches', [])
        
        for p_search in panel_searches:
            p_search_lower = p_search.lower()
            
            if 'tutorial' in p_search_lower and ('by host' in p_search_lower or 'by "host"' in p_search_lower):
                # Check if it's the error panel
                # Error logic: status >= 400, status > 399, status=4*, status in (400, 404, 500), etc.
                error_pattern = r'status\s*(?:>=|>|in|=)\s*["\']?(?:4\d\d|5\d\d|4\*|5\*|399)["\']?'
                
                if re.search(error_pattern, p_search_lower) or 'error' in p_search_lower:
                    if not error_panel_found:
                        error_panel_found = True
                        score += 20
                        feedback.append("Dashboard error rate panel detected.")
                else:
                    if not dist_panel_found:
                        dist_panel_found = True
                        score += 20
                        feedback.append("Dashboard distribution panel detected.")
                        
    if not dist_panel_found:
        feedback.append("FAIL: Dashboard is missing the 'Traffic Distribution' panel (or it doesn't group by host).")
    if not error_panel_found:
        feedback.append("FAIL: Dashboard is missing the 'Server Error Counts' panel (status >= 400).")

    passed = score >= 80
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }