#!/usr/bin/env python3
"""Verifier for optimize_dashboard_base_searches task.

Verifies that the agent successfully refactored a Simple XML dashboard to use a base search.
Scoring:
1. Dashboard Exists (10 points)
2. Global Base Search Created with ID (30 points)
3. Base Search Queries expected index (10 points)
4. Panels use post-process base searches (30 points)
5. Panel integrity maintained / not deleted (20 points)

Pass threshold is 70 points.
"""

import json
import tempfile
import os
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_optimize_dashboard_base_searches(traj, env_info, task_info):
    """Verify that the dashboard XML was correctly refactored for performance."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy exported results from container
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
    dashboard_found = analysis.get('dashboard_found', False)
    xml_data = analysis.get('xml_data', '')

    score = 0
    feedback = []
    
    # -------------------------------------------------------------------------
    # Criterion 1: Dashboard Exists (10 points)
    # -------------------------------------------------------------------------
    if dashboard_found and xml_data:
        score += 10
        feedback.append("Dashboard 'Security_Executive_Overview' found.")
    else:
        feedback.append("FAIL: Dashboard not found or empty.")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

    try:
        root = ET.fromstring(xml_data)
    except ET.ParseError as e:
        feedback.append(f"FAIL: Invalid XML structure in dashboard: {e}")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

    # -------------------------------------------------------------------------
    # Criterion 2: Global Base Search Created (30 points)
    # -------------------------------------------------------------------------
    all_searches = root.findall('.//search')
    base_search_id = None
    base_search_query = ""

    # Finding any search that defines an 'id' attribute (this acts as the base)
    for s in all_searches:
        if 'id' in s.attrib:
            base_search_id = s.attrib['id']
            query_elem = s.find('query')
            if query_elem is not None and query_elem.text:
                base_search_query = query_elem.text
            break

    if base_search_id:
        score += 30
        feedback.append(f"Global base search found with id '{base_search_id}'.")
    else:
        feedback.append("FAIL: No base search with an 'id' attribute was found.")

    # -------------------------------------------------------------------------
    # Criterion 3: Base Search Queries Logs (10 points)
    # -------------------------------------------------------------------------
    if base_search_query and 'index=security_logs' in base_search_query.lower():
        score += 10
        feedback.append("Base search correctly queries 'index=security_logs'.")
    elif base_search_query:
        feedback.append("FAIL: Base search does not query 'index=security_logs'.")
    else:
        feedback.append("FAIL: Base search has no valid <query> element.")

    # -------------------------------------------------------------------------
    # Criterion 4: Post-Process Searches Used (30 points)
    # -------------------------------------------------------------------------
    panel_searches = root.findall('.//panel//search')
    panels_using_base = 0
    
    for s in panel_searches:
        if 'base' in s.attrib and s.attrib['base'] == base_search_id:
            panels_using_base += 1

    if panels_using_base >= 3:
        score += 30
        feedback.append(f"{panels_using_base} panels successfully use the base search (>=3 required).")
    elif panels_using_base > 0:
        score += (panels_using_base * 10)  # Partial credit
        feedback.append(f"Partial: Only {panels_using_base} panels use the base search.")
    else:
        feedback.append("FAIL: No panels use the defined base search.")

    # -------------------------------------------------------------------------
    # Criterion 5: Panel Integrity Maintained (20 points)
    # -------------------------------------------------------------------------
    total_panels = len(root.findall('.//panel'))
    if total_panels >= 4:
        score += 20
        feedback.append(f"Panel integrity maintained ({total_panels} panels exist).")
    else:
        feedback.append(f"FAIL: Only {total_panels} panels found. Ensure you didn't delete visualizations.")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "base_search_id": base_search_id,
            "panels_using_base": panels_using_base,
            "total_panels": total_panels
        }
    }