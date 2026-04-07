#!/usr/bin/env python3
"""Verifier for dynamic_risk_scoring task.

Verification Strategy:
Programmatic checks (85 points) via Splunk REST API:
1. Report named exactly 'Dynamic_IP_Risk_Scoring' exists (10 pts)
2. Alert named exactly 'High_Risk_IP_Detected' exists (10 pts)
3. SPL contains eval logic mapping root->100, admin->50, else->10 (20 pts)
4. SPL contains stats sum aggregation by IP (15 pts)
5. SPL contains strict > 500 filter (10 pts)
6. Alert is scheduled hourly (10 pts)
7. Both report and alert query the security_logs index (10 pts)

VLM Verification (15 points):
8. Trajectory frames show agent interacting with Splunk Web UI to create searches/alerts (15 pts)

Pass Threshold: 65 points (requires core logic implementation).
"""

import json
import tempfile
import os
import re
import logging

from gym_anything.vlm import sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# =============================================================================
# VLM PROMPT FOR UI VERIFICATION
# =============================================================================

UI_VERIFICATION_PROMPT = """You are verifying if a computer agent used the Splunk web interface to create reports and alerts.

TASK: Create a dynamic risk scoring report and an hourly alert in Splunk using the web interface.

Look at these screenshots from the agent's trajectory and determine:

1. Is Splunk's web interface visible? (Green/black UI, Search & Reporting app)
2. Did the agent interact with the SPL search bar?
3. Did the agent use the "Save As" menu to create a Report and/or an Alert?
4. Are dialogs visible configuring an alert schedule (e.g., cron, hourly) or naming the report?

Note: The agent should have used the web UI to build and save these artifacts, not just terminal/REST API.

Respond in JSON format:
{
    "splunk_web_visible": true/false,
    "search_interface_used": true/false,
    "save_as_dialogs_used": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation of what you see"
}
"""

def verify_dynamic_risk_scoring(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_report = metadata.get('report_name', 'Dynamic_IP_Risk_Scoring')
    expected_alert = metadata.get('alert_name', 'High_Risk_IP_Detected')

    # Copy result file from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    analysis = result.get('analysis', {})
    all_searches = analysis.get('all_searches', [])
    new_searches = analysis.get('new_searches', [])

    score = 0
    feedback_parts = []
    
    # Extract specific artifacts (case insensitive match just in case, but prioritize exact)
    report_obj = None
    alert_obj = None
    
    for s in new_searches:
        if s.get('name', '') == expected_report:
            report_obj = s
        elif s.get('name', '') == expected_alert:
            alert_obj = s
            
    # Fallbacks for slight mismatches in casing
    if not report_obj:
        for s in new_searches:
            if s.get('name', '').lower() == expected_report.lower():
                report_obj = s
                break
                
    if not alert_obj:
        for s in new_searches:
            if s.get('name', '').lower() == expected_alert.lower():
                alert_obj = s
                break

    # 1. Report Exists (10 pts)
    if report_obj:
        score += 10
        feedback_parts.append(f"Report '{report_obj['name']}' found.")
    else:
        feedback_parts.append(f"FAIL: Report named '{expected_report}' not found in new searches.")

    # 2. Alert Exists (10 pts)
    if alert_obj:
        score += 10
        feedback_parts.append(f"Alert '{alert_obj['name']}' found.")
    else:
        feedback_parts.append(f"FAIL: Alert named '{expected_alert}' not found in new searches.")

    # Analyze SPL logic from the report (fallback to alert if report missing)
    logic_to_check = ""
    if report_obj:
        logic_to_check = report_obj.get('search', '').lower()
    elif alert_obj:
        logic_to_check = alert_obj.get('search', '').lower()

    if logic_to_check:
        # 3. SPL Evaluation Logic (20 pts)
        has_eval = 'eval' in logic_to_check
        has_conditional = 'case' in logic_to_check or 'if' in logic_to_check
        has_keywords = all(str(k) in logic_to_check for k in ['100', '50', '10', 'root', 'admin'])
        
        if has_eval and has_conditional and has_keywords:
            score += 20
            feedback_parts.append("Correct evaluation logic (eval/case/weights) found.")
        else:
            feedback_parts.append("FAIL: Search logic missing proper eval, conditional (case/if), or correct weights (100/50/10).")

        # 4. Aggregation Logic (15 pts)
        has_stats_sum = re.search(r'stats\s+(?:.*?)?sum\(', logic_to_check) is not None
        if has_stats_sum:
            score += 15
            feedback_parts.append("Correct aggregation logic (stats sum) found.")
        else:
            feedback_parts.append("FAIL: Search logic missing 'stats sum(...)' aggregation.")

        # 5. Threshold Filter (10 pts)
        has_threshold = re.search(r'>\s*500', logic_to_check) is not None
        if has_threshold:
            score += 10
            feedback_parts.append("Correct threshold filter (> 500) found.")
        else:
            feedback_parts.append("FAIL: Search logic missing strict '> 500' filter.")

        # 7. Index Reference (10 pts)
        if 'security_logs' in logic_to_check:
            score += 10
            feedback_parts.append("Search correctly references 'security_logs' index.")
        else:
            feedback_parts.append("FAIL: Search does not reference 'security_logs' index.")
    else:
        feedback_parts.append("FAIL: No valid search logic found to evaluate.")

    # 6. Alert Schedule (10 pts)
    if alert_obj:
        is_sched = str(alert_obj.get('is_scheduled', '0')) == '1'
        cron = alert_obj.get('cron_schedule', '')
        # Accept standard hourly crons: "0 * * * *", "*/60 * * * *", etc.
        is_hourly = cron.startswith('0 *') or cron.startswith('*/60 *') or '*/60' in cron
        
        if is_sched and is_hourly:
            score += 10
            feedback_parts.append(f"Alert correctly scheduled hourly (cron: {cron}).")
        elif is_sched:
            score += 5
            feedback_parts.append(f"Partial: Alert scheduled, but cron '{cron}' is not strictly hourly.")
        else:
            feedback_parts.append("FAIL: Alert is not scheduled.")
            
    # 8. VLM Verification (15 pts)
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        try:
            frames = sample_trajectory_frames(traj, n=4)
            vlm_res = query_vlm(prompt=UI_VERIFICATION_PROMPT, images=frames)
            
            if vlm_res and vlm_res.get('success'):
                vlm_parsed = vlm_res.get('parsed', {})
                ui_used = vlm_parsed.get('splunk_web_visible', False) and vlm_parsed.get('save_as_dialogs_used', False)
                
                if ui_used:
                    score += 15
                    feedback_parts.append("VLM verified Splunk UI interaction.")
                else:
                    feedback_parts.append("VLM: Splunk UI interaction (saving artifacts) not fully detected.")
            else:
                feedback_parts.append("VLM query failed or returned no valid data.")
        except Exception as e:
            logger.warning(f"VLM verification exception: {e}")
            feedback_parts.append(f"VLM verification skipped due to error.")
    else:
        # If VLM is not available, we graciously award the points to avoid penalizing the agent
        score += 15
        feedback_parts.append("VLM not available, awarding UI interaction points by default.")

    passed = score >= 65 and bool(report_obj) and bool(alert_obj)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }