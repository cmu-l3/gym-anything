#!/usr/bin/env python3
"""Verifier for impossible_travel_detection task.

Verification Strategy (REST API Object Introspection):
1. Verifies the creation of the exact 'Impossible_Travel_Detection' report.
2. Parses the underlying SPL to confirm the usage of `iplocation`.
3. Parses the underlying SPL to confirm aggregation by user.
4. Parses the underlying SPL to confirm >1 country filter logic.
5. Verifies the creation of the exact 'Geo_Security_Monitoring' dashboard.
6. Parses the dashboard XML to verify ≥2 panels and the use of the `geostats` command.

Pass Threshold: 60 points, with the geographical (iplocation) & filter logic explicitly required.
"""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_impossible_travel(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy exported result JSON from the container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/impossible_travel_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    analysis = result.get('analysis', {})
    
    score = 0
    feedback_parts = []
    subscores = {}

    # --- Criterion 1: Report Created (15 pts) ---
    report_found = analysis.get('report_found', False)
    is_new_report = analysis.get('is_new_report', False)
    report_search = analysis.get('report_search', '').lower()

    if report_found and is_new_report:
        score += 15
        feedback_parts.append("Report 'Impossible_Travel_Detection' exists and was newly created.")
        subscores['report_created'] = True
    elif report_found:
        score += 5
        feedback_parts.append("Report found, but wasn't newly created (possible pre-existing state manipulation).")
        subscores['report_created'] = False
    else:
        feedback_parts.append("FAIL: Report 'Impossible_Travel_Detection' not found.")
        subscores['report_created'] = False

    # --- Criterion 2: Uses `iplocation` (15 pts) ---
    has_iplocation = 'iplocation' in report_search
    if has_iplocation:
        score += 15
        feedback_parts.append("Report search successfully uses 'iplocation'.")
        subscores['uses_iplocation'] = True
    else:
        feedback_parts.append("FAIL: Report search is missing the 'iplocation' command.")
        subscores['uses_iplocation'] = False

    # --- Criterion 3: Aggregates by User (20 pts) ---
    # Look for "by user", "by <space> user", or "transaction <space> user"
    groups_by_user = bool(re.search(r'\b(by|transaction)\s+user\b', report_search))
    if groups_by_user:
        score += 20
        feedback_parts.append("Report search correctly aggregates data by 'user'.")
        subscores['groups_by_user'] = True
    else:
        feedback_parts.append("FAIL: Report search does not appear to group/aggregate by 'user'.")
        subscores['groups_by_user'] = False

    # --- Criterion 4: Multi-country logic (20 pts) ---
    # Look for > 1, >= 2, >1, >=2
    has_multi_country_filter = bool(re.search(r'>\s*1|>=\s*2', report_search))
    if has_multi_country_filter:
        score += 20
        feedback_parts.append("Report search properly filters for multiple countries (> 1).")
        subscores['multi_country_filter'] = True
    else:
        feedback_parts.append("FAIL: Report search lacks filter logic for >1 distinct countries.")
        subscores['multi_country_filter'] = False

    # --- Criterion 5: Dashboard Created (15 pts) ---
    dashboard_found = analysis.get('dashboard_found', False)
    is_new_dashboard = analysis.get('is_new_dashboard', False)
    
    if dashboard_found and is_new_dashboard:
        score += 15
        feedback_parts.append("Dashboard 'Geo_Security_Monitoring' exists and was newly created.")
        subscores['dashboard_created'] = True
    elif dashboard_found:
        score += 5
        feedback_parts.append("Dashboard found, but wasn't newly created.")
        subscores['dashboard_created'] = False
    else:
        feedback_parts.append("FAIL: Dashboard 'Geo_Security_Monitoring' not found.")
        subscores['dashboard_created'] = False

    # --- Criterion 6: Dashboard Panels and Geostats (15 pts) ---
    panels = analysis.get('dashboard_panels', 0)
    has_geostats = analysis.get('dashboard_has_geostats', False)
    
    if panels >= 2 and has_geostats:
        score += 15
        feedback_parts.append(f"Dashboard has {panels} panels and utilizes the 'geostats' command.")
        subscores['dashboard_geostats_panels'] = True
    elif panels >= 2:
        score += 5
        feedback_parts.append(f"Dashboard has {panels} panels but is missing 'geostats' map visualization.")
        subscores['dashboard_geostats_panels'] = False
    elif has_geostats:
        score += 5
        feedback_parts.append("Dashboard has 'geostats', but has less than 2 panels.")
        subscores['dashboard_geostats_panels'] = False
    else:
        feedback_parts.append("FAIL: Dashboard lacks required multiple panels and geostats command.")
        subscores['dashboard_geostats_panels'] = False

    # --- Final Scoring Logic ---
    # Require minimum score of 60 AND both explicit constraints (iplocation & multi-country logic)
    passed = score >= 60 and subscores['uses_iplocation'] and subscores['multi_country_filter']
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
        "details": {
            "panels": panels,
            "has_geostats": has_geostats,
            "report_spl_preview": report_search[:150] if report_search else None
        }
    }