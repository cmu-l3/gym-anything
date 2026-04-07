#!/usr/bin/env python3
"""
Verifier for timewrap_behavioral_overlay task.

Verifies the agent correctly authored an SPL query with time-series overlay
capabilities (timechart + timewrap) and operationalized it into a Report
and Dashboard.

Scoring System (Total 100 points, Pass Threshold 70):
- Report Exists named DoD_Failed_Auth_Overlay (15 points)
- Valid Index & Filter (security_logs, fail*) (15 points)
- Uses Timechart span=1h (15 points)
- Uses Timewrap 1d/d/24h (25 points)
- Dashboard Exists named Authentication_Baselines (15 points)
- Dashboard Panel references the timewrap logic/report (15 points)
"""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_timewrap_behavioral_overlay(traj, env_info, task_info):
    """Verify that the agent created the day-over-day overlay report and dashboard."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve analysis from environment
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
    
    score = 0
    feedback_parts = []
    subscores = {}
    
    # Extract variables
    report_found = analysis.get('report_found', False)
    search_query = analysis.get('report_search_query', '').lower()
    dash_found = analysis.get('dashboard_found', False)
    dash_xml = analysis.get('dashboard_xml', '').lower()

    # 1. Report Exists (15 pts)
    if report_found:
        score += 15
        feedback_parts.append("Report 'DoD_Failed_Auth_Overlay' created")
        subscores['report_exists'] = True
    else:
        feedback_parts.append("FAIL: Report 'DoD_Failed_Auth_Overlay' not found")
        subscores['report_exists'] = False

    # Check search query contents if report exists
    if report_found and search_query:
        # 2. Valid Index & Filter (15 pts)
        has_index = 'security_logs' in search_query
        has_fail_filter = re.search(r'fail', search_query) is not None
        if has_index and has_fail_filter:
            score += 15
            feedback_parts.append("Valid index and filter logic applied")
            subscores['valid_filter'] = True
        else:
            feedback_parts.append("FAIL: Search must query security_logs for failed authentications")
            subscores['valid_filter'] = False

        # 3. Uses Timechart with hourly span (15 pts)
        has_timechart = 'timechart' in search_query
        has_hourly = re.search(r'span\s*=\s*(1h|60m)', search_query) is not None
        if has_timechart and has_hourly:
            score += 15
            feedback_parts.append("Timechart with hourly span used")
            subscores['uses_timechart'] = True
        elif has_timechart:
            # Partial credit for timechart without explicit span
            score += 5
            feedback_parts.append("Timechart used (but missing span=1h)")
            subscores['uses_timechart'] = False
        else:
            feedback_parts.append("FAIL: Search does not use timechart command")
            subscores['uses_timechart'] = False

        # 4. Uses Timewrap (25 pts)
        # Matches timewrap 1d, timewrap d, timewrap 24h, timewrap 1day
        has_timewrap = re.search(r'timewrap\s+([1]?d(ay)?|24h)', search_query) is not None
        if has_timewrap:
            score += 25
            feedback_parts.append("Timewrap command correctly applied for 1-day overlay")
            subscores['uses_timewrap'] = True
        elif 'timewrap' in search_query:
            score += 10
            feedback_parts.append("Timewrap used (but incorrect cycle argument)")
            subscores['uses_timewrap'] = False
        else:
            feedback_parts.append("FAIL: Search does not use timewrap command")
            subscores['uses_timewrap'] = False
    else:
        # No search query to evaluate
        subscores['valid_filter'] = False
        subscores['uses_timechart'] = False
        subscores['uses_timewrap'] = False

    # 5. Dashboard Exists (15 pts)
    if dash_found:
        score += 15
        feedback_parts.append("Dashboard 'Authentication_Baselines' created")
        subscores['dashboard_exists'] = True
    else:
        feedback_parts.append("FAIL: Dashboard 'Authentication_Baselines' not found")
        subscores['dashboard_exists'] = False

    # 6. Dashboard Panel references logic (15 pts)
    if dash_found and dash_xml:
        # Check if the panel XML either references the report by name, or contains the raw timewrap query
        refs_report = 'dod_failed_auth_overlay' in dash_xml
        refs_timewrap = 'timewrap' in dash_xml
        
        has_panel = '<panel' in dash_xml
        
        if has_panel and (refs_report or refs_timewrap):
            score += 15
            feedback_parts.append("Dashboard panel successfully linked to timewrap logic")
            subscores['dashboard_panel_linked'] = True
        else:
            feedback_parts.append("FAIL: Dashboard must contain a panel displaying the timewrap data")
            subscores['dashboard_panel_linked'] = False
    else:
        subscores['dashboard_panel_linked'] = False

    # Evaluate Pass Threshold (70 points)
    # 70 points ensures they at least created the report with the correct SPL (15+15+15+25 = 70)
    # Dashboard adds up to 30 points of buffer/full completion.
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
        "details": {
            "search_query_found": search_query,
            "dashboard_xml_preview": dash_xml[:200] if dash_xml else ""
        }
    }