#!/usr/bin/env python3
"""Verifier for create_security_app task.

Verifies the creation of a complete Splunk app package, including:
1. App directory/namespace existence
2. Correct App label
3. Saved search created inside the app's namespace
4. Saved search has valid detection logic
5. Dashboard created inside the app's namespace containing a panel
"""

import json
import tempfile
import os
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_app(traj, env_info, task_info):
    """Verify that the agent successfully built and configured the Splunk app."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_app_name = metadata.get('app_name', 'ssh_security_monitor')
    expected_app_label = metadata.get('app_label', 'SSH Security Monitor')
    expected_search_name = metadata.get('search_name', 'SSH_Failed_Login_Summary')
    expected_dashboard_name = metadata.get('dashboard_name', 'ssh_overview')
    expected_index = metadata.get('target_index', 'security_logs')

    # Copy result file from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/create_app_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    analysis = result.get('analysis', {})
    app_info = analysis.get('app', {})
    saved_searches = analysis.get('saved_searches', [])
    dashboards = analysis.get('dashboards', [])

    score = 0
    feedback_parts = []
    
    # ---------------------------------------------------------
    # Criterion 1: App exists and is enabled (20 points)
    # ---------------------------------------------------------
    app_exists = app_info.get('exists', False)
    app_disabled = app_info.get('disabled', True)
    
    if app_exists and not app_disabled:
        score += 20
        feedback_parts.append(f"App '{expected_app_name}' exists and is enabled")
    elif app_exists:
        score += 10
        feedback_parts.append(f"App '{expected_app_name}' exists but is disabled")
    else:
        feedback_parts.append(f"FAIL: App '{expected_app_name}' does not exist")
        # If the app doesn't exist, the rest of the checks will inherently fail
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts)
        }

    # ---------------------------------------------------------
    # Criterion 2: App has correct label (20 points)
    # ---------------------------------------------------------
    app_label = app_info.get('label', '')
    if app_label.lower() == expected_app_label.lower():
        score += 20
        feedback_parts.append(f"App label is correct ('{app_label}')")
    elif app_label:
        score += 10
        feedback_parts.append(f"App label found ('{app_label}'), but expected '{expected_app_label}'")
    else:
        feedback_parts.append("FAIL: App label is missing")

    # ---------------------------------------------------------
    # Criterion 3: Saved search exists in app namespace (20 points)
    # ---------------------------------------------------------
    target_search = None
    for s in saved_searches:
        if s.get('name', '').lower() == expected_search_name.lower():
            target_search = s
            break

    if target_search:
        score += 20
        feedback_parts.append(f"Saved search '{expected_search_name}' exists in app namespace")
    else:
        feedback_parts.append(f"FAIL: Saved search '{expected_search_name}' missing from app namespace")

    # ---------------------------------------------------------
    # Criterion 4: Saved search logic is valid (20 points)
    # ---------------------------------------------------------
    if target_search:
        search_query = target_search.get('search', '').lower()
        has_index = expected_index in search_query
        has_failure_kw = any(kw in search_query for kw in ['fail', 'invalid', 'error'])
        
        if has_index and has_failure_kw:
            score += 20
            feedback_parts.append(f"Saved search properly queries '{expected_index}' for failures")
        elif has_index:
            score += 10
            feedback_parts.append(f"Saved search queries '{expected_index}' but misses failure keywords")
        else:
            feedback_parts.append(f"FAIL: Saved search logic is incorrect (missing '{expected_index}')")

    # ---------------------------------------------------------
    # Criterion 5: Dashboard exists with a valid panel (20 points)
    # ---------------------------------------------------------
    target_dashboard = None
    for d in dashboards:
        if d.get('name', '').lower() == expected_dashboard_name.lower():
            target_dashboard = d
            break

    if target_dashboard:
        xml = target_dashboard.get('xml', '')
        # Check for panel element
        has_panel = bool(re.search(r'<panel\b', xml, re.IGNORECASE))
        # Check if the panel references the security logs (query logic)
        refs_index = expected_index in xml.lower()
        
        if has_panel and refs_index:
            score += 20
            feedback_parts.append(f"Dashboard '{expected_dashboard_name}' exists with valid security panel")
        elif has_panel:
            score += 15
            feedback_parts.append(f"Dashboard exists with a panel, but doesn't explicitly reference '{expected_index}'")
        else:
            score += 10
            feedback_parts.append("Dashboard exists but lacks a <panel> element")
    else:
        feedback_parts.append(f"FAIL: Dashboard '{expected_dashboard_name}' missing from app namespace")

    # ---------------------------------------------------------
    # Final Evaluation
    # ---------------------------------------------------------
    passed = score >= 60 and app_exists and (target_search is not None or target_dashboard is not None)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "app_found": app_exists,
            "searches_in_app": len(saved_searches),
            "dashboards_in_app": len(dashboards)
        }
    }