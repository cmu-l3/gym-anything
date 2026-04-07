#!/usr/bin/env python3
"""
Verifier for botnet_brute_force_detection task.

Verification Strategy (100 points total, Pass Threshold = 60):
1. Alert Exists (15 pts): A new saved search named "Distributed_Brute_Force_Alert" exists.
2. Alert Logic (25 pts): Search contains 'security_logs', aggregates 'by user', and uses 'dc'/'distinct_count'.
3. Alert Schedule (10 pts): Alert is configured with an hourly cron schedule.
4. Dashboard Exists (15 pts): A new dashboard named "Botnet_Targeting_Dashboard" exists.
5. Dashboard Panels (15 pts): Dashboard XML contains at least 2 panel elements.
6. Dashboard Geo-intel (20 pts): Dashboard XML contains the 'iplocation' command.
"""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def normalize_name(name):
    """Normalize artifact name for comparison."""
    return name.lower().replace(' ', '_').replace('-', '_')

def verify_botnet_detection(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Extract expected names from metadata
    metadata = task_info.get('metadata', {})
    expected_alert_name = normalize_name(metadata.get('alert_name', 'Distributed_Brute_Force_Alert'))
    expected_dash_name = normalize_name(metadata.get('dashboard_name', 'Botnet_Targeting_Dashboard'))

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/botnet_task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    analysis = result.get('analysis', {})
    target_alert = analysis.get('target_alert')
    target_dashboard = analysis.get('target_dashboard')
    
    score = 0
    feedback_parts = []
    subscores = {}

    # ==========================================
    # 1. Alert Exists (15 pts)
    # ==========================================
    if target_alert:
        actual_name = normalize_name(target_alert.get('name', ''))
        if actual_name == expected_alert_name:
            score += 15
            feedback_parts.append("Alert 'Distributed_Brute_Force_Alert' found.")
            subscores['alert_exists'] = True
        else:
            feedback_parts.append(f"Alert found but incorrectly named ('{actual_name}'). Partial credit.")
            score += 5
            subscores['alert_exists'] = False
    else:
        feedback_parts.append("FAIL: No new alert found.")
        subscores['alert_exists'] = False

    # ==========================================
    # 2. Alert Logic (25 pts)
    # ==========================================
    if target_alert:
        search_query = target_alert.get('search', '').lower()
        has_index = 'security_logs' in search_query
        has_by_user = 'by user' in search_query
        has_dc = 'dc(' in search_query or 'distinct_count(' in search_query
        
        logic_score = 0
        if has_index: logic_score += 5
        if has_by_user: logic_score += 10
        if has_dc: logic_score += 10
        
        score += logic_score
        
        if logic_score == 25:
            feedback_parts.append("Alert logic correctly aggregates distinct IPs by user.")
            subscores['alert_logic_correct'] = True
        else:
            feedback_parts.append(f"Alert logic incomplete (Index: {has_index}, By User: {has_by_user}, Distinct Count: {has_dc}).")
            subscores['alert_logic_correct'] = False
    else:
        subscores['alert_logic_correct'] = False

    # ==========================================
    # 3. Alert Schedule (10 pts)
    # ==========================================
    if target_alert:
        is_scheduled = target_alert.get('is_scheduled', False)
        cron = target_alert.get('cron_schedule', '').strip()
        
        if is_scheduled and (cron.startswith('0 ') or cron.startswith('*/60 ') or cron == '@hourly'):
            score += 10
            feedback_parts.append("Hourly cron schedule configured properly.")
            subscores['alert_schedule_correct'] = True
        elif is_scheduled and cron:
            score += 5
            feedback_parts.append(f"Alert scheduled but cron ({cron}) may not be hourly.")
            subscores['alert_schedule_correct'] = False
        else:
            feedback_parts.append("Alert is not scheduled.")
            subscores['alert_schedule_correct'] = False
    else:
        subscores['alert_schedule_correct'] = False

    # ==========================================
    # 4. Dashboard Exists (15 pts)
    # ==========================================
    if target_dashboard:
        actual_dash_name = normalize_name(target_dashboard.get('name', ''))
        if actual_dash_name == expected_dash_name:
            score += 15
            feedback_parts.append("Dashboard 'Botnet_Targeting_Dashboard' found.")
            subscores['dashboard_exists'] = True
        else:
            feedback_parts.append(f"Dashboard found but incorrectly named ('{actual_dash_name}'). Partial credit.")
            score += 5
            subscores['dashboard_exists'] = False
    else:
        feedback_parts.append("FAIL: No new dashboard found.")
        subscores['dashboard_exists'] = False

    # ==========================================
    # 5. Dashboard Panels (15 pts)
    # ==========================================
    if target_dashboard:
        panels = target_dashboard.get('panel_count', 0)
        if panels >= 2:
            score += 15
            feedback_parts.append(f"Dashboard contains {panels} panels (>=2).")
            subscores['dashboard_panels'] = True
        elif panels == 1:
            score += 5
            feedback_parts.append("Dashboard contains only 1 panel (expected >= 2).")
            subscores['dashboard_panels'] = False
        else:
            feedback_parts.append("Dashboard contains no panels.")
            subscores['dashboard_panels'] = False
    else:
        subscores['dashboard_panels'] = False

    # ==========================================
    # 6. Dashboard Geo-intel (20 pts)
    # ==========================================
    if target_dashboard:
        has_iplocation = target_dashboard.get('has_iplocation', False)
        if has_iplocation:
            score += 20
            feedback_parts.append("Dashboard successfully utilizes 'iplocation' command.")
            subscores['dashboard_geo'] = True
        else:
            feedback_parts.append("FAIL: Dashboard does not utilize 'iplocation' command.")
            subscores['dashboard_geo'] = False
    else:
        subscores['dashboard_geo'] = False

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
        "details": {
            "target_alert_name": target_alert.get('name', 'None') if target_alert else 'None',
            "target_dashboard_name": target_dashboard.get('name', 'None') if target_dashboard else 'None',
            "dashboard_panel_count": target_dashboard.get('panel_count', 0) if target_dashboard else 0
        }
    }