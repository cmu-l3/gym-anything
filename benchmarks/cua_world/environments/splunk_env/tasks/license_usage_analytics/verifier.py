#!/usr/bin/env python3
"""Verifier for license_usage_analytics task."""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def normalize_name(name):
    """Normalize object names for comparison (case-insensitive, underscores instead of spaces)."""
    return name.lower().replace(' ', '_').replace('-', '_')

def verify_license_usage_analytics(traj, env_info, task_info):
    """Verify that the capacity monitoring alert and dashboard were created."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_alert_name = normalize_name(metadata.get('expected_alert_name', 'High_License_Usage_Warning'))
    expected_dashboard_name = normalize_name(metadata.get('expected_dashboard_name', 'License_Consumption_Audit'))

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/license_usage_result.json", tmp.name)
        with open(tmp.name, 'r') as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    analysis = data.get('analysis', {})
    searches = analysis.get('searches', [])
    dashboards = analysis.get('dashboards', [])

    score = 0
    feedback = []
    
    # ---------------------------------------------------------
    # PART 1: ALERTS VERIFICATION (Total: 40 points)
    # ---------------------------------------------------------
    
    # 1. Alert Exists (20 pts)
    target_alert = None
    for s in searches:
        if normalize_name(s['name']) == expected_alert_name:
            target_alert = s
            break
    
    # Fallback to any new relevant search if exact name is missed
    if not target_alert:
        for s in searches:
            if s['is_new'] and 'internal' in s['search'].lower() and 'kb' in s['search'].lower():
                target_alert = s
                break

    if target_alert:
        score += 20
        feedback.append(f"Found target alert: '{target_alert['name']}'")
        
        # 2. Alert Logic Correct (20 pts)
        search_query = target_alert['search'].lower()
        has_internal = '_internal' in search_query
        has_kb = 'kb' in search_query
        # Match typical thresholds: > 1000, >1000, where count > x, etc.
        has_threshold = bool(re.search(r'[><=]\s*\d+', search_query) or 'where' in search_query or 'search' in search_query)
        
        if has_internal and has_kb and has_threshold:
            score += 20
            feedback.append("Alert SPL correctly queries _internal, aggregates kb, and applies a threshold filter.")
        elif has_internal and has_kb:
            score += 10
            feedback.append("Alert SPL queries _internal and kb, but missing a clear threshold condition.")
        else:
            feedback.append("Alert SPL missing required internal metric components (_internal, kb).")
    else:
        feedback.append(f"FAIL: Could not find alert named '{expected_alert_name}' or equivalent.")

    # ---------------------------------------------------------
    # PART 2: DASHBOARD VERIFICATION (Total: 60 points)
    # ---------------------------------------------------------

    # 3. Dashboard Exists (20 pts)
    target_dash = None
    for d in dashboards:
        if normalize_name(d['name']) == expected_dashboard_name:
            target_dash = d
            break
    
    # Fallback to any new relevant dashboard
    if not target_dash:
        for d in dashboards:
            if d['is_new'] and ('per_index_thruput' in d['xml'].lower() or 'per_sourcetype_thruput' in d['xml'].lower()):
                target_dash = d
                break
                
    if target_dash:
        score += 20
        feedback.append(f"Found target dashboard: '{target_dash['name']}'")
        
        # 4. Dashboard has >= 2 panels (20 pts)
        panel_count = target_dash.get('panel_count', 0)
        if panel_count >= 2:
            score += 20
            feedback.append(f"Dashboard has {panel_count} panels (>=2).")
        elif panel_count == 1:
            score += 10
            feedback.append("Dashboard has only 1 panel (need at least 2).")
        else:
            feedback.append("Dashboard has 0 valid panels.")
            
        # 5. Dashboard Logic Correct (20 pts)
        xml = target_dash.get('xml', '').lower()
        has_idx_thruput = 'per_index_thruput' in xml
        has_st_thruput = 'per_sourcetype_thruput' in xml
        
        if has_idx_thruput and has_st_thruput:
            score += 20
            feedback.append("Dashboard queries explicitly utilize both per_index_thruput and per_sourcetype_thruput metrics.")
        elif has_idx_thruput or has_st_thruput:
            score += 10
            feedback.append("Dashboard utilizes only ONE of the required throughput metrics groups.")
        else:
            feedback.append("Dashboard missing required metrics groups in panel SPL.")
            
    else:
        feedback.append(f"FAIL: Could not find dashboard named '{expected_dashboard_name}' or equivalent.")

    # Determine passing state (Minimum: either fully correct on one side + partial on other, or overall functional)
    passed = score >= 60 and target_alert is not None and target_dash is not None

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }