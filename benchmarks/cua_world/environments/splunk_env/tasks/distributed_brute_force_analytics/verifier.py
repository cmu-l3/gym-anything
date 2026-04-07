#!/usr/bin/env python3
"""Verifier for distributed_brute_force_analytics task.

Criteria evaluated programmatically using the exported REST API results:
1. Report Exists & Named Correctly (15 pts)
2. SPL: Queries security_logs (10 pts)
3. SPL: Calculates Distinct IPs using dc() or distinct_count() (15 pts)
4. SPL: Subnet String Manipulation using rex, replace, split, etc. (15 pts)
5. SPL: Global Percentage Logic using eventstats (15 pts)
6. SPL: Distributed Attack Filter for distinct IPs > 1 (10 pts)
7. Dashboard Exists & Named Correctly (10 pts)
8. Dashboard Valid Panels (>= 2 panels) (10 pts)

Threshold: 70 pts.
"""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_distributed_brute_force_analytics(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_report_name = metadata.get('expected_report_name', 'Subnet_Attack_Aggregation')
    expected_dashboard_name = metadata.get('expected_dashboard_name', 'Distributed_Brute_Force_Monitoring')

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/dist_bf_result.json", tmp.name)
        with open(tmp.name) as f:
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

    # Find target report (case insensitive normalize)
    def norm_name(n): return n.lower().replace(" ", "_").strip()
    
    target_report = None
    for s in new_searches:
        if norm_name(s['name']) == norm_name(expected_report_name):
            target_report = s
            break
            
    if not target_report and new_searches:
        # Fallback to the latest new search if the name is wrong
        target_report = new_searches[-1]
        
    # --- Criterion 1: Report Exists & Named Correctly (15 pts) ---
    if target_report and norm_name(target_report['name']) == norm_name(expected_report_name):
        score += 15
        feedback.append(f"Found report with exact name '{target_report['name']}'")
        subscores['report_named_correctly'] = True
    elif target_report:
        feedback.append(f"Found a new report, but named '{target_report['name']}' instead of '{expected_report_name}'")
        subscores['report_named_correctly'] = False
    else:
        feedback.append(f"FAIL: No new reports were created.")
        subscores['report_named_correctly'] = False
        
    search_query = target_report['search'] if target_report else ""
    
    # --- Criterion 2: SPL Queries security_logs (10 pts) ---
    if search_query and re.search(r'(?i)index\s*=\s*"?security_logs"?', search_query):
        score += 10
        feedback.append("SPL references 'security_logs' index")
        subscores['queries_security_logs'] = True
    else:
        feedback.append("FAIL: SPL does not correctly query the 'security_logs' index")
        subscores['queries_security_logs'] = False

    # --- Criterion 3: SPL Calculates Distinct IPs (15 pts) ---
    if search_query and re.search(r'(?i)(?:dc|distinct_count)\s*\(', search_query):
        score += 15
        feedback.append("SPL utilizes distinct count function (dc or distinct_count)")
        subscores['calculates_distinct_ips'] = True
    else:
        feedback.append("FAIL: SPL does not use distinct count to aggregate IPs")
        subscores['calculates_distinct_ips'] = False

    # --- Criterion 4: SPL Subnet String Manipulation (15 pts) ---
    if search_query and re.search(r'(?i)(replace|rex|split|substr|extract)', search_query):
        score += 15
        feedback.append("SPL utilizes string manipulation functions for subnet extraction")
        subscores['subnet_string_manipulation'] = True
    else:
        feedback.append("FAIL: SPL is missing string manipulation functions (rex/replace) for subnet grouping")
        subscores['subnet_string_manipulation'] = False

    # --- Criterion 5: SPL Global Percentage Logic (15 pts) ---
    if search_query and re.search(r'(?i)eventstats', search_query):
        score += 15
        feedback.append("SPL leverages 'eventstats' for calculating global percentage baselines")
        subscores['global_percentage_logic'] = True
    else:
        feedback.append("FAIL: SPL does not use 'eventstats' to calculate a global aggregate metric")
        subscores['global_percentage_logic'] = False

    # --- Criterion 6: SPL Distributed Attack Filter (10 pts) ---
    if search_query and re.search(r'(?i)(?:where|search).*?>\s*1', search_query):
        score += 10
        feedback.append("SPL includes a filter threshold (> 1) to identify distributed attacks")
        subscores['distributed_attack_filter'] = True
    else:
        feedback.append("FAIL: SPL lacks a threshold filter checking for > 1 distinct IP")
        subscores['distributed_attack_filter'] = False

    # --- Find target dashboard ---
    target_dash = None
    for d in new_dashboards:
        if norm_name(d['name']) == norm_name(expected_dashboard_name):
            target_dash = d
            break
            
    if not target_dash and new_dashboards:
        target_dash = new_dashboards[-1]

    # --- Criterion 7: Dashboard Exists (10 pts) ---
    if target_dash and norm_name(target_dash['name']) == norm_name(expected_dashboard_name):
        score += 10
        feedback.append(f"Dashboard '{target_dash['name']}' created successfully")
        subscores['dashboard_exists'] = True
    elif target_dash:
        feedback.append(f"Dashboard created but named '{target_dash['name']}' instead of '{expected_dashboard_name}'")
        subscores['dashboard_exists'] = False
    else:
        feedback.append("FAIL: No new dashboards were created")
        subscores['dashboard_exists'] = False

    # --- Criterion 8: Dashboard Valid Panels (10 pts) ---
    if target_dash and target_dash.get('panel_count', 0) >= 2:
        score += 10
        feedback.append(f"Dashboard has correct number of panels ({target_dash['panel_count']})")
        subscores['dashboard_valid_panels'] = True
    elif target_dash:
        feedback.append(f"FAIL: Dashboard has {target_dash.get('panel_count', 0)} panels, expected at least 2")
        subscores['dashboard_valid_panels'] = False
    else:
        subscores['dashboard_valid_panels'] = False

    passed = score >= 70
    if passed:
        feedback.append("SUCCESS: Passed the 70 point threshold for advanced analytics creation")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "subscores": subscores,
        "details": {
            "search_query": search_query,
            "dashboard_name": target_dash['name'] if target_dash else None,
            "panel_count": target_dash.get('panel_count', 0) if target_dash else 0
        }
    }