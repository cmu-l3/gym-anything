#!/usr/bin/env python3
"""Verifier for first_time_seen_ip_detection task.

Criteria:
1. Baseline Report Exists (15 pts) -> name matches exactly "Baseline_Known_User_IPs"
2. Baseline Output Logic (20 pts) -> contains `outputlookup` and `known_user_ips.csv`
3. Detection Alert Exists (15 pts) -> name matches exactly "First_Time_Seen_Login_Alert"
4. Detection Input Logic (20 pts) -> contains `inputlookup` or `lookup` targeting `known_user_ips.csv`
5. Index & Event Filtering (15 pts) -> both searches query `security_logs` and filter for successful auths.
6. Valid SPL Syntax (15 pts) -> Both strings pass Splunk's native search parser validation.

Pass threshold: 70 points (which ensures both reports are created with correct lookup mechanisms).
"""

import json, tempfile, os, logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_first_time_seen_ip_detection(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/first_time_seen_ip_detection_result.json", tmp.name)
        with open(tmp.name) as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(tmp.name): os.unlink(tmp.name)

    analysis = data.get('analysis', {})
    baseline_report = analysis.get('baseline_report')
    detection_alert = analysis.get('detection_alert')

    score = 0
    feedback = []

    # 1. Baseline Report Exists
    if baseline_report:
        score += 15
        feedback.append("Baseline report 'Baseline_Known_User_IPs' exists.")
    else:
        feedback.append("FAIL: Baseline report 'Baseline_Known_User_IPs' not found.")
        
    # 2. Baseline Output Logic
    if baseline_report:
        search_lower = baseline_report.get('search', '').lower()
        if 'outputlookup' in search_lower and 'known_user_ips.csv' in search_lower:
            score += 20
            feedback.append("Baseline report uses outputlookup correctly.")
        else:
            feedback.append("FAIL: Baseline report missing 'outputlookup' or 'known_user_ips.csv'.")
    
    # 3. Detection Alert Exists
    if detection_alert:
        score += 15
        feedback.append("Detection alert 'First_Time_Seen_Login_Alert' exists.")
    else:
        feedback.append("FAIL: Detection alert 'First_Time_Seen_Login_Alert' not found.")
        
    # 4. Detection Input Logic
    if detection_alert:
        search_lower = detection_alert.get('search', '').lower()
        if ('inputlookup' in search_lower or 'lookup' in search_lower) and 'known_user_ips.csv' in search_lower:
            score += 20
            feedback.append("Detection alert uses lookup/inputlookup correctly.")
        else:
            feedback.append("FAIL: Detection alert missing 'lookup'/'inputlookup' or 'known_user_ips.csv'.")
            
    # 5. Index & Event Filtering
    if baseline_report and detection_alert:
        b_search = baseline_report.get('search', '').lower()
        d_search = detection_alert.get('search', '').lower()
        b_has_sec = 'security_logs' in b_search
        d_has_sec = 'security_logs' in d_search
        b_has_succ = any(x in b_search for x in ['accepted', 'success'])
        d_has_succ = any(x in d_search for x in ['accepted', 'success'])
        
        if b_has_sec and d_has_sec and b_has_succ and d_has_succ:
            score += 15
            feedback.append("Both searches query security_logs for successful logins.")
        else:
            feedback.append("FAIL: Both searches must query 'security_logs' and filter for successful logins (e.g., 'Accepted').")
    else:
        feedback.append("FAIL: Missing one or both searches for index checking.")

    # 6. Valid SPL Syntax
    if baseline_report and detection_alert:
        b_valid = baseline_report.get('is_valid_spl', False)
        d_valid = detection_alert.get('is_valid_spl', False)
        if b_valid and d_valid:
            score += 15
            feedback.append("Both searches have valid SPL syntax.")
        else:
            feedback.append(f"FAIL: Invalid SPL detected (Baseline valid: {b_valid}, Alert valid: {d_valid}).")
    else:
        feedback.append("FAIL: Missing one or both searches for syntax validation.")

    passed = score >= 70 and baseline_report is not None and detection_alert is not None
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }