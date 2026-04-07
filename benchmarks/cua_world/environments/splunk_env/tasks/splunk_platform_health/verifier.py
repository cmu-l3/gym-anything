#!/usr/bin/env python3
"""Verifier for splunk_platform_health task.

REQUIREMENTS:
1. Dashboard 'Splunk_Platform_Health' exists.
2. Dashboard has >= 4 panels.
3. Dashboard queries reference Splunk internal indexes (_internal, _introspection, _audit).
4. Saved search 'Splunk_Indexing_Anomaly_Detection' exists.
5. Saved search logic references Splunk internal indexes.
"""

import json
import tempfile
import os
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

POINTS_PER_CRITERION = 20
PASS_THRESHOLD = 60

def uses_internal_indexes(text):
    """Check if the text references any of Splunk's internal indexes."""
    if not text:
        return False
    text_lower = text.lower()
    internal_indexes = ['_internal', '_introspection', '_audit']
    
    for idx in internal_indexes:
        # Match "index=_internal", "index="_internal"", or just the index name in a typical SPL context
        if idx in text_lower:
            return True
    return False

def verify_splunk_platform_health(traj, env_info, task_info):
    """Verify that the platform health monitoring dashboard and anomaly search were created."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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
    dashboard = analysis.get('dashboard', {})
    saved_search = analysis.get('saved_search', {})
    
    score = 0
    feedback_parts = []
    subscores = {
        "dashboard_exists": False,
        "dashboard_min_panels": False,
        "dashboard_uses_internals": False,
        "saved_search_exists": False,
        "saved_search_uses_internals": False
    }

    # Criterion 1: Dashboard Exists
    if dashboard and dashboard.get('name'):
        score += POINTS_PER_CRITERION
        feedback_parts.append(f"Dashboard found: '{dashboard.get('name')}'")
        subscores["dashboard_exists"] = True
    else:
        feedback_parts.append("FAIL: Dashboard 'Splunk_Platform_Health' not found")

    # Criterion 2: Dashboard has >= 4 panels
    if subscores["dashboard_exists"]:
        panel_count = dashboard.get('panel_count', 0)
        if panel_count >= 4:
            score += POINTS_PER_CRITERION
            feedback_parts.append(f"Dashboard has sufficient panels ({panel_count} >= 4)")
            subscores["dashboard_min_panels"] = True
        else:
            feedback_parts.append(f"FAIL: Dashboard only has {panel_count} panels (requires at least 4)")
            
    # Criterion 3: Dashboard references internal indexes
    if subscores["dashboard_exists"]:
        xml_content = dashboard.get('xml', '')
        if uses_internal_indexes(xml_content):
            score += POINTS_PER_CRITERION
            feedback_parts.append("Dashboard queries reference internal Splunk indexes")
            subscores["dashboard_uses_internals"] = True
        else:
            feedback_parts.append("FAIL: Dashboard does not appear to query _internal, _introspection, or _audit")

    # Criterion 4: Saved Search Exists
    if saved_search and saved_search.get('name'):
        score += POINTS_PER_CRITERION
        feedback_parts.append(f"Saved search found: '{saved_search.get('name')}'")
        subscores["saved_search_exists"] = True
    else:
        feedback_parts.append("FAIL: Saved search 'Splunk_Indexing_Anomaly_Detection' not found")

    # Criterion 5: Saved Search references internal indexes
    if subscores["saved_search_exists"]:
        search_query = saved_search.get('search', '')
        if uses_internal_indexes(search_query):
            score += POINTS_PER_CRITERION
            feedback_parts.append("Saved search queries reference internal Splunk indexes")
            subscores["saved_search_uses_internals"] = True
        else:
            feedback_parts.append("FAIL: Saved search does not query _internal, _introspection, or _audit")

    # Provide a bonus/modifier if they literally did nothing
    if score == 0:
        feedback_parts.append("CRITICAL FAIL: No expected artifacts were created.")

    return {
        "passed": score >= PASS_THRESHOLD,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
        "details": {
            "found_dashboard_name": dashboard.get('name', ''),
            "panel_count": dashboard.get('panel_count', 0),
            "found_search_name": saved_search.get('name', ''),
            "search_query_preview": saved_search.get('search', '')[:100] if saved_search.get('search') else ""
        }
    }