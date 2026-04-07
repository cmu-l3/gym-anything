#!/usr/bin/env python3
"""Verifier for temporal_access_anomaly_detection task.

Verifies the creation of a temporal heatmap dashboard and an off-hours successful login alert.
Checks the existence of the objects, their Splunk SPL logic for temporal bounds, and scheduling properties.

Scoring System (100 pts total, 60 to pass):
- Dashboard Created (20 pts)
- Dashboard Temporal SPL (20 pts)
- Alert Created (20 pts)
- Alert Success Logic (15 pts)
- Alert Temporal Logic (15 pts)
- Alert Scheduled (10 pts)
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def normalize_name(name):
    return name.lower().replace(' ', '_').replace('-', '_')

def verify_temporal_access_anomaly(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from environment
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/temporal_access_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    analysis = result.get('analysis', {})
    new_dashboards = analysis.get('new_dashboards', [])
    new_searches = analysis.get('new_searches', [])

    metadata = task_info.get('metadata', {})
    expected_dashboard_name = normalize_name(metadata.get('dashboard_name', 'Authentication_Temporal_Heatmap'))
    expected_alert_name = normalize_name(metadata.get('alert_name', 'Off_Hours_Success_Alert'))

    score = 0
    feedback_parts = []
    subscores = {
        "dashboard_created": False,
        "dashboard_temporal_spl": False,
        "alert_created": False,
        "alert_success_logic": False,
        "alert_temporal_logic": False,
        "alert_scheduled": False
    }

    # ==========================================
    # 1. Evaluate Dashboard
    # ==========================================
    target_dashboard = None
    
    # Try exact match first
    for d in new_dashboards:
        if normalize_name(d.get('name', '')) == expected_dashboard_name:
            target_dashboard = d
            break
            
    # Fallback to any new dashboard if none matched exactly
    if not target_dashboard and new_dashboards:
        target_dashboard = new_dashboards[-1]

    if target_dashboard:
        score += 20
        subscores["dashboard_created"] = True
        actual_name = target_dashboard.get('name', '')
        feedback_parts.append(f"Dashboard created: '{actual_name}'")

        # Check SPL for temporal logic
        xml_data = target_dashboard.get('xml_data', '').lower()
        has_temporal_fields = ('date_wday' in xml_data and 'date_hour' in xml_data)
        has_strftime = ('strftime' in xml_data)
        
        if has_temporal_fields or has_strftime:
            score += 20
            subscores["dashboard_temporal_spl"] = True
            feedback_parts.append("Dashboard SPL contains valid temporal formatting logic")
        else:
            feedback_parts.append("FAIL: Dashboard SPL missing temporal fields (e.g., date_wday/date_hour or strftime)")
    else:
        feedback_parts.append("FAIL: No new dashboard created")

    # ==========================================
    # 2. Evaluate Alert
    # ==========================================
    target_alert = None
    
    # Try exact match first
    for a in new_searches:
        if normalize_name(a.get('name', '')) == expected_alert_name:
            target_alert = a
            break
            
    # Fallback to any new alert if none matched exactly
    if not target_alert and new_searches:
        target_alert = new_searches[-1]

    if target_alert:
        score += 20
        subscores["alert_created"] = True
        actual_alert_name = target_alert.get('name', '')
        feedback_parts.append(f"Alert created: '{actual_alert_name}'")

        alert_spl = target_alert.get('search', '').lower()
        
        # Check Success Logic
        has_success_logic = ('accepted' in alert_spl or 'success' in alert_spl or 'session opened' in alert_spl)
        if has_success_logic:
            score += 15
            subscores["alert_success_logic"] = True
            feedback_parts.append("Alert SPL correctly filters for successful authentications")
        else:
            feedback_parts.append("FAIL: Alert SPL does not contain success keywords (e.g., 'Accepted password')")

        # Check Temporal Logic
        has_temporal_spl = ('date_wday' in alert_spl or 'date_hour' in alert_spl or 'strftime' in alert_spl or 'time' in alert_spl)
        has_numeric_bounds = ('<' in alert_spl or '>' in alert_spl or 'in(' in alert_spl or '!=' in alert_spl or '=' in alert_spl)
        
        if has_temporal_spl and has_numeric_bounds:
            score += 15
            subscores["alert_temporal_logic"] = True
            feedback_parts.append("Alert SPL contains temporal bounding constraints")
        else:
            feedback_parts.append("FAIL: Alert SPL lacks explicit time-bounding conditions (e.g., date_hour < 5)")

        # Check Scheduling
        is_scheduled = target_alert.get('is_scheduled', False)
        cron = target_alert.get('cron_schedule', '')
        
        if is_scheduled and cron:
            score += 10
            subscores["alert_scheduled"] = True
            feedback_parts.append(f"Alert properly scheduled (cron: {cron})")
        else:
            feedback_parts.append("FAIL: Alert is not scheduled or lacks a cron expression")
            
    else:
        feedback_parts.append("FAIL: No new scheduled alert created")

    # ==========================================
    # Final Evaluation
    # ==========================================
    passed = (score >= 60 and subscores["dashboard_created"] and subscores["alert_created"])
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
        "details": {
            "dashboard_found": target_dashboard is not None,
            "alert_found": target_alert is not None
        }
    }