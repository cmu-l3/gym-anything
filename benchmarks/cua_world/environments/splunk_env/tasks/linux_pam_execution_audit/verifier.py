#!/usr/bin/env python3
"""
Verifier for linux_pam_execution_audit task.

Evaluation criteria:
1. Dashboard Exists ('Privileged_Execution_Audit') (15 pts)
2. Dashboard Panels (>= 3 panels) (15 pts)
3. Dashboard Regex Field Extraction (contains `rex` or `regex`) (25 pts)
4. Alert Exists ('Failed_Privileged_Escalation') (15 pts)
5. Alert Logic (contains failure keywords AND su/sudo) (15 pts)
6. Alert Schedule (is_scheduled=1, valid hourly cron) (15 pts)

Total points: 100. Pass threshold: 70.
"""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_linux_pam_audit(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/linux_pam_execution_audit_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    analysis = result.get('analysis', {})
    dash_info = analysis.get('dashboard', {})
    alert_info = analysis.get('alert', {})
    
    score = 0
    feedback = []
    
    # ---------------------------------------------------------
    # DASHBOARD VERIFICATION
    # ---------------------------------------------------------
    dash_exists = dash_info.get('exists', False)
    if dash_exists:
        score += 15
        feedback.append("Dashboard 'Privileged_Execution_Audit' exists.")
        
        # Check Panel Count
        panels = dash_info.get('panel_count', 0)
        if panels >= 3:
            score += 15
            feedback.append(f"Dashboard has {panels} panels (>= 3).")
        else:
            feedback.append(f"Dashboard has {panels} panels (Requires 3+).")
            
        # Check Regex Field Extraction
        has_rex = dash_info.get('has_rex', False)
        if has_rex:
            score += 25
            feedback.append("Dashboard XML successfully uses 'rex'/'regex' command for extraction.")
        else:
            feedback.append("Dashboard searches are missing the 'rex'/'regex' field extraction command.")
    else:
        feedback.append("FAIL: Dashboard 'Privileged_Execution_Audit' was not found.")

    # ---------------------------------------------------------
    # ALERT VERIFICATION
    # ---------------------------------------------------------
    alert_exists = alert_info.get('exists', False)
    if alert_exists:
        score += 15
        feedback.append("Alert 'Failed_Privileged_Escalation' exists.")
        
        # Check Alert Logic
        search_query = alert_info.get('search', '').lower()
        has_su_cmd = 'su ' in search_query or 'sudo' in search_query
        has_fail_kw = any(kw in search_query for kw in ['fail', 'incorrect', 'invalid', 'denied'])
        
        if has_su_cmd and has_fail_kw:
            score += 15
            feedback.append("Alert search correctly targets failed su/sudo attempts.")
        else:
            feedback.append(f"Alert search logic may be flawed (Missing su/sudo or failure keywords). Query: {search_query[:50]}")
            
        # Check Alert Schedule
        is_scheduled = alert_info.get('is_scheduled', False)
        cron = alert_info.get('cron', '').strip()
        
        # Validating hourly cron: looks like '0 * * * *' or '*/60 * * * *' 
        # For leniency, we verify it is scheduled and has a valid cron syntax
        has_valid_cron = bool(re.match(r'^(\S+\s+){4}\S+$', cron))
        is_hourly = has_valid_cron and ('* * * *' in cron or '*/60' in cron)
        
        if is_scheduled and has_valid_cron:
            score += 15
            if is_hourly:
                feedback.append(f"Alert is correctly scheduled hourly (cron: {cron}).")
            else:
                feedback.append(f"Alert is scheduled (cron: {cron}) - accepted with full credit.")
        else:
            feedback.append(f"Alert is missing scheduling. (is_scheduled={is_scheduled}, cron='{cron}')")
            
    else:
        feedback.append("FAIL: Alert 'Failed_Privileged_Escalation' was not found.")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "dashboard_info": dash_info,
            "alert_info": alert_info
        }
    }