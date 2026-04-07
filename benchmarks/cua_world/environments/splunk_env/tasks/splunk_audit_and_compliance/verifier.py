#!/usr/bin/env python3
"""
Verifier for splunk_audit_and_compliance task.

This task is verified strictly using the Splunk REST API payload captured by the export script.
It checks both the dashboard requirements and the scheduled alert requirements.

Criteria (Total 100 pts, Pass threshold 70 pts):
1. Dashboard Exists & is new (15 pts)
2. Dashboard Panels >= 3 (15 pts)
3. Dashboard explicitly filters 'splunk-system-user' (20 pts)
4. Alert Exists & is new (15 pts)
5. Alert Logic queries _audit AND contains export keywords (20 pts)
6. Alert is scheduled (15 pts)
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_splunk_audit_and_compliance(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/splunk_audit_task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    analysis = result.get('analysis', {})
    dashboard = analysis.get('dashboard', {})
    alert = analysis.get('alert', {})

    score = 0
    feedback_parts = []
    subscores = {}

    # ---------------------------------------------------------
    # DASHBOARD EVALUATION (Total: 50 pts)
    # ---------------------------------------------------------
    
    # 1. Dashboard Exists (15 pts)
    if dashboard.get('found') and dashboard.get('is_new'):
        score += 15
        feedback_parts.append(f"Dashboard '{dashboard.get('actual_name')}' created successfully")
        subscores['dashboard_exists'] = True
    elif dashboard.get('found'):
        feedback_parts.append("FAIL: Dashboard found but it existed before task started (not created by agent)")
        subscores['dashboard_exists'] = False
    else:
        feedback_parts.append("FAIL: Dashboard 'Splunk_Usage_Audit' not found")
        subscores['dashboard_exists'] = False

    # 2. Dashboard Panels (15 pts)
    panels = dashboard.get('panels', 0)
    if dashboard.get('found') and panels >= 3:
        score += 15
        feedback_parts.append(f"Dashboard has {panels} panels (Requirement: >= 3)")
        subscores['dashboard_panels'] = True
    elif dashboard.get('found'):
        feedback_parts.append(f"FAIL: Dashboard has {panels} panels (Requirement: >= 3)")
        subscores['dashboard_panels'] = False
    else:
        subscores['dashboard_panels'] = False

    # 3. Filters System User (20 pts)
    if dashboard.get('found') and dashboard.get('filters_system_user'):
        score += 20
        feedback_parts.append("Dashboard successfully filters 'splunk-system-user'")
        subscores['dashboard_filters'] = True
    elif dashboard.get('found'):
        feedback_parts.append("FAIL: Dashboard XML does not explicitly filter 'splunk-system-user'")
        subscores['dashboard_filters'] = False
    else:
        subscores['dashboard_filters'] = False

    # ---------------------------------------------------------
    # ALERT EVALUATION (Total: 50 pts)
    # ---------------------------------------------------------

    # 4. Alert Exists (15 pts)
    if alert.get('found') and alert.get('is_new'):
        score += 15
        feedback_parts.append(f"Alert '{alert.get('actual_name')}' created successfully")
        subscores['alert_exists'] = True
    elif alert.get('found'):
        feedback_parts.append("FAIL: Alert found but it existed before task started (not created by agent)")
        subscores['alert_exists'] = False
    else:
        feedback_parts.append("FAIL: Scheduled alert 'Data_Exfiltration_Via_Search' not found")
        subscores['alert_exists'] = False

    # 5. Alert Logic (20 pts)
    queries_audit = alert.get('queries_audit', False)
    has_export = alert.get('has_export_kw', False)

    if alert.get('found'):
        if queries_audit and has_export:
            score += 20
            feedback_parts.append("Alert logic correctly queries _audit and detects export commands")
            subscores['alert_logic'] = True
        elif queries_audit:
            feedback_parts.append("FAIL: Alert queries _audit but misses required export keywords (outputcsv, outputlookup, export)")
            subscores['alert_logic'] = False
        elif has_export:
            feedback_parts.append("FAIL: Alert detects export keywords but does NOT query the _audit index")
            subscores['alert_logic'] = False
        else:
            feedback_parts.append("FAIL: Alert search logic is completely missing required index and keywords")
            subscores['alert_logic'] = False
    else:
        subscores['alert_logic'] = False

    # 6. Alert Scheduled (15 pts)
    if alert.get('found') and alert.get('is_scheduled'):
        score += 15
        feedback_parts.append("Alert is properly configured to run on a schedule")
        subscores['alert_scheduled'] = True
    elif alert.get('found'):
        feedback_parts.append("FAIL: Alert is saved as a standard search, not a scheduled alert")
        subscores['alert_scheduled'] = False
    else:
        subscores['alert_scheduled'] = False

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
        "details": {
            "dashboard_panels": panels,
            "alert_search_preview": alert.get('search_preview', '')
        }
    }