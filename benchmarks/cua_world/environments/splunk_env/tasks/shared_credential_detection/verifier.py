#!/usr/bin/env python3
import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def normalize_name(name):
    """Normalize object names to be case-insensitive and handle spaces/underscores equally."""
    return name.lower().replace(' ', '_').replace('-', '_')

def verify_shared_credential_detection(traj, env_info, task_info):
    """
    Verifies the creation of the IAM continuous detection pipeline in Splunk:
    1. Event type 'successful_auth'
    2. Scheduled alert 'Shared_Credential_Violation' with DC aggregation and >= 3 threshold
    3. Dashboard 'IAM_Security_Posture' with >= 2 panels
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/shared_credential_detection_result.json", tmp.name)
        with open(tmp.name) as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    analysis = data.get('analysis', {})
    
    # Normalize keys for robust lookup
    event_types = {normalize_name(k): k for k in analysis.get('event_types', [])}
    searches = {normalize_name(k): v for k, v in analysis.get('searches', {}).items()}
    dashboards = {normalize_name(k): v for k, v in analysis.get('dashboards', {}).items()}

    score = 0
    feedback = []
    
    # 1. Event Type Exists (20 pts)
    target_et = normalize_name("successful_auth")
    if target_et in event_types:
        score += 20
        feedback.append("Event type 'successful_auth' created.")
    else:
        feedback.append("FAIL: Event type 'successful_auth' not found.")
        
    # 2. Alert Exists & Scheduled (20 pts)
    target_alert = normalize_name("Shared_Credential_Violation")
    alert_obj = searches.get(target_alert)
    if alert_obj:
        is_sched = str(alert_obj.get('is_scheduled', '0')) == '1' or bool(alert_obj.get('cron_schedule'))
        if is_sched:
            score += 20
            feedback.append("Alert 'Shared_Credential_Violation' exists and is scheduled.")
        else:
            score += 10
            feedback.append("Alert 'Shared_Credential_Violation' exists but is NOT scheduled (partial credit).")
    else:
        feedback.append("FAIL: Alert 'Shared_Credential_Violation' not found.")
        
    # 3. Alert Logic: Aggregation (20 pts)
    # 4. Alert Logic: Threshold (15 pts)
    if alert_obj:
        spl = alert_obj.get('search', '')
        
        # Look for dc(src_ip) or distinct_count(src_ip) or values(src_ip)
        has_agg = bool(re.search(r'(?i)(dc|distinct_count)\s*\(\s*src_ip\s*\)', spl)) or \
                  bool(re.search(r'(?i)values\s*\(\s*src_ip\s*\)', spl))
        
        if has_agg:
            score += 20
            feedback.append("Alert SPL uses distinct count aggregation on src_ip.")
        else:
            feedback.append("FAIL: Alert SPL does not appear to aggregate distinct src_ips.")
            
        # Look for threshold check like >= 3, > 2, etc.
        has_thresh = bool(re.search(r'(?i)(?:>|>=)\s*[23]', spl))
        if has_thresh:
            score += 15
            feedback.append("Alert SPL enforces >= 3 threshold.")
        else:
            feedback.append("FAIL: Alert SPL missing >= 3 threshold check.")
    else:
        feedback.append("FAIL: Cannot verify SPL since alert was not found.")
        
    # 5. Dashboard Exists & Layout (25 pts)
    target_dash = normalize_name("IAM_Security_Posture")
    dash_xml = dashboards.get(target_dash)
    if dash_xml:
        panel_count = len(re.findall(r'<panel\b', dash_xml, re.IGNORECASE))
        if panel_count >= 2:
            score += 25
            feedback.append(f"Dashboard 'IAM_Security_Posture' exists with {panel_count} panels.")
        else:
            score += 10
            feedback.append(f"Dashboard 'IAM_Security_Posture' exists but has only {panel_count} panels (needs >= 2).")
    else:
        feedback.append("FAIL: Dashboard 'IAM_Security_Posture' not found.")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }