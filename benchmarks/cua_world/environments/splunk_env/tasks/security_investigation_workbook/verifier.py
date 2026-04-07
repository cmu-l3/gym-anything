#!/usr/bin/env python3
"""Verifier for security_investigation_workbook task.

Verification Strategy:
1. Dashboard Exists: Verifies a dashboard named 'Security_Investigation_Workbook' exists (20 pts).
2. Form Inputs: Checks XML for at least 2 <input> tags (20 pts).
3. Panel Count: Checks XML for at least 3 <panel> tags (20 pts).
4. Token Substitution: Checks XML for token patterns ($token$) (20 pts).
5. Data Sources: Ensures the dashboard queries security_logs or web_logs (20 pts).

Pass threshold: 60 points (must include dashboard existence).
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def normalize_name(name):
    return name.lower().replace(' ', '_').replace('-', '_')


def verify_security_investigation_workbook(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('dashboard_name', 'Security_Investigation_Workbook')
    expected_name_norm = normalize_name(expected_name)
    min_inputs = metadata.get('min_inputs', 2)
    min_panels = metadata.get('min_panels', 3)

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

    dashboard_analysis = result.get('dashboard_analysis', {})
    
    score = 0
    feedback_parts = []
    subscores = {}

    found_dashboard = dashboard_analysis.get('found_dashboard', False)
    dashboard_name = dashboard_analysis.get('dashboard_name', '')
    is_new = dashboard_analysis.get('is_new', False)
    
    # 1. Dashboard Exists & Name Match (20 pts)
    # Agent might misname it slightly but we heavily reward exact matches
    if found_dashboard and normalize_name(dashboard_name) == expected_name_norm:
        score += 20
        feedback_parts.append(f"Dashboard '{expected_name}' found")
        subscores['dashboard_exists'] = True
    elif found_dashboard:
        score += 10
        feedback_parts.append(f"Found a dashboard but name mismatch (got: '{dashboard_name}')")
        subscores['dashboard_exists'] = True
    else:
        feedback_parts.append(f"FAIL: Dashboard '{expected_name}' not found")
        subscores['dashboard_exists'] = False
        return {
            "passed": False, 
            "score": score, 
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }
        
    # Check if newly created
    if not is_new:
        feedback_parts.append("WARNING: Dashboard existed before task started (may be re-used)")

    # 2. Form Inputs (20 pts)
    input_count = dashboard_analysis.get('input_count', 0)
    if input_count >= min_inputs:
        score += 20
        feedback_parts.append(f"Form inputs sufficient ({input_count} >= {min_inputs})")
        subscores['form_inputs'] = True
    elif input_count > 0:
        score += 10
        feedback_parts.append(f"Partial: Only {input_count} form input(s) found (need {min_inputs})")
        subscores['form_inputs'] = False
    else:
        feedback_parts.append("FAIL: No form inputs found (not an interactive dashboard)")
        subscores['form_inputs'] = False

    # 3. Panel Count (20 pts)
    panel_count = dashboard_analysis.get('panel_count', 0)
    if panel_count >= min_panels:
        score += 20
        feedback_parts.append(f"Panels sufficient ({panel_count} >= {min_panels})")
        subscores['panel_count'] = True
    elif panel_count > 0:
        score += 10
        feedback_parts.append(f"Partial: Only {panel_count} panel(s) found (need {min_panels})")
        subscores['panel_count'] = False
    else:
        feedback_parts.append("FAIL: No panels found")
        subscores['panel_count'] = False

    # 4. Token Substitution (20 pts)
    token_usage_count = dashboard_analysis.get('token_usage_count', 0)
    if token_usage_count >= 2:
        score += 20
        feedback_parts.append(f"Dynamic tokens used ({token_usage_count} detected)")
        subscores['tokens_used'] = True
    elif token_usage_count > 0:
        score += 10
        feedback_parts.append(f"Partial: Minimal token usage detected")
        subscores['tokens_used'] = False
    else:
        feedback_parts.append("FAIL: No token substitution (e.g., $token_name$) detected in dashboard")
        subscores['tokens_used'] = False

    # 5. References correct indexes (20 pts)
    references_logs = dashboard_analysis.get('references_logs', False)
    if references_logs:
        score += 20
        feedback_parts.append("Dashboard queries target indexes (security_logs/web_logs)")
        subscores['references_logs'] = True
    else:
        feedback_parts.append("FAIL: Dashboard does not reference required indexes")
        subscores['references_logs'] = False

    passed = score >= 60 and subscores.get('dashboard_exists', False)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
        "details": dashboard_analysis
    }