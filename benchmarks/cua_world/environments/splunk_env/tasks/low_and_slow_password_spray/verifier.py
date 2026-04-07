#!/usr/bin/env python3
"""
Verifier for low_and_slow_password_spray task.

Scoring Criteria (Total 100, Pass >= 70):
1. Alert Exists (20 pts): Saved search named 'Password_Spray_Detection' created.
2. Scheduled (10 pts): Alert has scheduling enabled.
3. Distinct Count Logic (20 pts): Alert query uses 'dc(user)' or 'distinct_count(user)'.
4. Ratio/Threshold Logic (20 pts): Alert query contains '5' and '3' to represent the distinct user and ratio filters.
5. Dashboard Exists (15 pts): Dashboard named 'Password_Spray_Dashboard' created.
6. Multiple Panels (15 pts): Dashboard contains >= 2 panels.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def normalize_name(name):
    """Normalize object name for comparison."""
    return name.lower().replace(' ', '_').replace('-', '_')

def verify_password_spray(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_alert = normalize_name(metadata.get('alert_name', 'Password_Spray_Detection'))
    expected_dash = normalize_name(metadata.get('dashboard_name', 'Password_Spray_Dashboard'))

    # Retrieve output from container
    tmp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/password_spray_result.json", tmp_file.name)
        with open(tmp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(tmp_file.name):
            os.unlink(tmp_file.name)

    analysis = result.get('analysis', {})
    new_searches = analysis.get('new_searches', [])
    new_dashboards = analysis.get('new_dashboards', [])

    score = 0
    feedback_parts = []
    subscores = {
        "alert_exists": False,
        "is_scheduled": False,
        "dc_logic": False,
        "threshold_logic": False,
        "dashboard_exists": False,
        "multiple_panels": False
    }

    # Find the target alert
    target_search = None
    for s in new_searches:
        if normalize_name(s.get('name', '')) == expected_alert:
            target_search = s
            break

    # If exact name not found, check if ANY new search has the required logic (partial credit mitigation)
    if not target_search and new_searches:
        for s in new_searches:
            search_str = s.get('search', '').lower()
            if 'dc(user)' in search_str or 'distinct_count(user)' in search_str:
                target_search = s
                break

    # Evaluate Search Criteria
    if target_search:
        search_name = normalize_name(target_search.get('name', ''))
        search_str = target_search.get('search', '').lower()

        # 1. Alert Exists
        if search_name == expected_alert:
            score += 20
            feedback_parts.append("Alert 'Password_Spray_Detection' created")
            subscores["alert_exists"] = True
        else:
            feedback_parts.append(f"Alert name mismatch (expected {expected_alert}, got {search_name})")

        # 2. Scheduled
        if target_search.get('is_scheduled', False):
            score += 10
            feedback_parts.append("Alert is scheduled")
            subscores["is_scheduled"] = True
        else:
            feedback_parts.append("Alert is NOT scheduled")

        # 3. Distinct Count Logic
        if 'dc(user)' in search_str or 'distinct_count(user)' in search_str:
            score += 20
            feedback_parts.append("Alert uses distinct count logic on users")
            subscores["dc_logic"] = True
        else:
            feedback_parts.append("Alert lacks 'dc(user)' or 'distinct_count(user)' logic")

        # 4. Threshold/Ratio Logic (Look for presence of '5' and '3' alongside count/dc)
        if '5' in search_str and '3' in search_str:
            score += 20
            feedback_parts.append("Alert applies proper thresholds (users >= 5, ratio < 3)")
            subscores["threshold_logic"] = True
        else:
            feedback_parts.append("Alert lacks required thresholds (5 users, 3 ratio)")
    else:
        feedback_parts.append("FAIL: No matching alert or advanced logic search created")

    # Find the target dashboard
    target_dash = None
    for d in new_dashboards:
        if normalize_name(d.get('name', '')) == expected_dash:
            target_dash = d
            break
            
    # Fallback to any new dashboard if exact name missed
    if not target_dash and new_dashboards:
        target_dash = max(new_dashboards, key=lambda x: x.get('panel_count', 0))

    # Evaluate Dashboard Criteria
    if target_dash:
        dash_name = normalize_name(target_dash.get('name', ''))
        panel_count = target_dash.get('panel_count', 0)

        # 5. Dashboard Exists
        if dash_name == expected_dash:
            score += 15
            feedback_parts.append("Dashboard 'Password_Spray_Dashboard' created")
            subscores["dashboard_exists"] = True
        else:
            feedback_parts.append(f"Dashboard name mismatch (expected {expected_dash}, got {dash_name})")

        # 6. Multiple Panels
        if panel_count >= 2:
            score += 15
            feedback_parts.append(f"Dashboard has multiple panels ({panel_count})")
            subscores["multiple_panels"] = True
        else:
            feedback_parts.append(f"Dashboard has insufficient panels ({panel_count} < 2)")
    else:
        feedback_parts.append("FAIL: No new dashboard created")

    # Pass condition: at least 70 points AND both the alert and dashboard exist with correct names
    passed = score >= 70 and subscores["alert_exists"] and subscores["dashboard_exists"]

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
        "details": {
            "searches_created": len(new_searches),
            "dashboards_created": len(new_dashboards),
            "target_search": target_search.get('search', '') if target_search else None
        }
    }