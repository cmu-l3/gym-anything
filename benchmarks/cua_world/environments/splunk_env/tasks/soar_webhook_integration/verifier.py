#!/usr/bin/env python3
"""Verifier for soar_webhook_integration task.

Evaluates configuration based on Splunk's internal REST API exports.
Checks multiple properties to guarantee completion without ambiguity:
1. Alert existence and index targeting (15 points)
2. Alert schedule properties (10 points)
3. Webhook action enablement and URL matching (20 points)
4. Throttling/Suppression enabled (10 points)
5. Throttling applied to a field (15 points)
6. Throttling duration set to 1 hour (10 points)
7. Dashboard existence and XML query matching (20 points)
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def is_truthy(val):
    """Handles Splunk's varied truthy responses ('1', 1, 'true', True)"""
    return str(val).lower() in ['1', 'true', 'yes']

def verify_soar_webhook_integration(traj, env_info, task_info):
    """Verify that the webhook alert and health dashboard were configured properly."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read export JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    analysis = result.get('analysis', {})
    
    found_alert = analysis.get('found_alert', False)
    alert_is_new = analysis.get('alert_is_new', False)
    alert_data = analysis.get('alert_data', {})
    
    found_dashboard = analysis.get('found_dashboard', False)
    dashboard_is_new = analysis.get('dashboard_is_new', False)
    dashboard_data = analysis.get('dashboard_data', {})

    score = 0
    feedback_parts = []
    
    # Check 1: Alert Created and uses security logs (15 pts)
    search_query = alert_data.get('search', '').lower()
    if found_alert and alert_is_new:
        if 'security_logs' in search_query:
            score += 15
            feedback_parts.append("Alert created and targets security_logs (+15)")
        else:
            feedback_parts.append("FAIL: Alert created but does not target 'security_logs' index")
    else:
        feedback_parts.append("FAIL: Alert 'Brute_Force_Webhook_Alert' not found or wasn't newly created")

    # Check 2: Frequent Schedule (10 pts)
    is_scheduled = is_truthy(alert_data.get('is_scheduled'))
    cron = alert_data.get('cron_schedule', '')
    if is_scheduled and '*/5' in cron:
        score += 10
        feedback_parts.append("Alert is scheduled every 5 mins (+10)")
    elif is_scheduled:
        feedback_parts.append(f"FAIL: Alert scheduled, but cron '{cron}' is not every 5 mins (*/5 * * * *)")
    else:
        feedback_parts.append("FAIL: Alert is not scheduled")

    # Check 3: Webhook Action (20 pts)
    action_webhook = is_truthy(alert_data.get('action_webhook'))
    webhook_url = alert_data.get('webhook_url', '')
    if action_webhook and '10.0.0.50:8080/soar_webhook' in webhook_url:
        score += 20
        feedback_parts.append("Webhook action configured with correct URL (+20)")
    elif action_webhook:
        feedback_parts.append(f"FAIL: Webhook enabled but URL is incorrect ('{webhook_url}')")
    else:
        feedback_parts.append("FAIL: Webhook action not enabled")

    # Check 4: Throttling Enabled (10 pts)
    suppress = is_truthy(alert_data.get('suppress'))
    if suppress:
        score += 10
        feedback_parts.append("Throttling enabled (+10)")
    else:
        feedback_parts.append("FAIL: Throttling (Suppression) is not enabled")

    # Check 5: Throttling Field (15 pts)
    suppress_fields = alert_data.get('suppress_fields', '')
    if suppress and len(str(suppress_fields).strip()) > 0:
        score += 15
        feedback_parts.append(f"Throttling grouped by field '{suppress_fields}' (+15)")
    else:
        feedback_parts.append("FAIL: Throttling enabled but no grouping field specified")

    # Check 6: Throttling Duration (10 pts)
    suppress_period = str(alert_data.get('suppress_period', '')).strip().lower()
    valid_periods = ['1h', '60m', '3600', '3600s', '60m@m']
    if suppress and suppress_period in valid_periods:
        score += 10
        feedback_parts.append(f"Throttling duration correct: {suppress_period} (+10)")
    elif suppress:
        feedback_parts.append(f"FAIL: Throttling duration '{suppress_period}' is not 1 hour")

    # Check 7: Health Dashboard (20 pts)
    if found_dashboard and dashboard_is_new:
        xml = dashboard_data.get('eai_data', '').lower()
        has_internal = 'index=_internal' in xml or 'index="_internal"' in xml
        has_scheduler = 'sourcetype=scheduler' in xml or 'sourcetype="scheduler"' in xml
        has_alert_name = 'brute_force_webhook_alert' in xml
        
        if has_internal and has_scheduler and has_alert_name:
            score += 20
            feedback_parts.append("Dashboard created with correct internal log search (+20)")
        else:
            feedback_parts.append("FAIL: Dashboard created but panel XML does not contain the required index=_internal/scheduler/alert name search")
    else:
        feedback_parts.append("FAIL: Dashboard 'SOAR_Integration_Health' not found or wasn't newly created")

    # Requirements for passing
    # To pass, Webhook URL, Dashboard, and at least some Throttle configuration must be present
    key_criteria_met = (
        action_webhook and
        found_dashboard and
        suppress
    )
    
    passed = score >= 75 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "found_alert": found_alert,
            "found_dashboard": found_dashboard,
            "alert_score": score
        }
    }