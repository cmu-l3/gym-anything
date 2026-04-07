#!/usr/bin/env python3
"""Verifier for noc_trellis_wallboard task.

Programmatic Verification of the Simple XML definition:
1. Dashboard Exists (20 pts)
2. Trellis Enabled on a Single Value panel (20 pts)
3. Trellis Split By 'host' (20 pts)
4. Color Thresholding enabled (20 pts)
5. Stacked Trend Chart referencing 'timechart' (20 pts)

Anti-gaming: The XML must reference the 'system_logs' index.
"""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

POINTS_PER_CRITERION = 20
PASS_THRESHOLD = 80

def verify_noc_wallboard(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Retrieve and parse result file
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", tmp.name)
        with open(tmp.name, 'r') as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    analysis = data.get('analysis', {})
    dashboard_found = analysis.get('dashboard_found', False)
    xml = analysis.get('dashboard_xml', '')
    
    score = 0
    feedback = []
    subscores = {}

    # Anti-gaming check
    if dashboard_found and 'system_logs' not in xml.lower():
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "FAIL: Dashboard was created but searches do not query 'system_logs' index.",
            "subscores": {"anti_gaming_failed": True}
        }

    # Criterion 1: Dashboard Exists
    if dashboard_found:
        score += POINTS_PER_CRITERION
        feedback.append("Dashboard 'NOC_System_Health_Wallboard' found.")
        subscores['dashboard_exists'] = True
    else:
        new_dashes = [d['name'] for d in analysis.get('new_dashboards', [])]
        if new_dashes:
            feedback.append(f"FAIL: Dashboard not found. Found other new dashboards: {new_dashes}")
        else:
            feedback.append("FAIL: Dashboard 'NOC_System_Health_Wallboard' not found.")
        subscores['dashboard_exists'] = False
        return {"passed": False, "score": score, "feedback": " | ".join(feedback), "subscores": subscores}

    # Criterion 2: Trellis Enabled
    # Matches <option name="trellis.enabled">1</option> or true
    has_trellis = bool(re.search(r'<option name="trellis\.enabled">\s*(1|true)\s*</option>', xml, re.IGNORECASE))
    if has_trellis:
        score += POINTS_PER_CRITERION
        feedback.append("Trellis layout is enabled.")
        subscores['trellis_enabled'] = True
    else:
        feedback.append("FAIL: Trellis layout is not enabled in the XML.")
        subscores['trellis_enabled'] = False

    # Criterion 3: Trellis Split By host
    # Matches <option name="trellis.splitBy">host</option>
    has_split_by = bool(re.search(r'<option name="trellis\.splitBy">\s*host\s*</option>', xml, re.IGNORECASE))
    if has_split_by:
        score += POINTS_PER_CRITERION
        feedback.append("Trellis is correctly split by 'host'.")
        subscores['trellis_split_by'] = True
    else:
        feedback.append("FAIL: Trellis is not split by 'host'.")
        subscores['trellis_split_by'] = False

    # Criterion 4: Color Thresholding Enabled
    # Matches <option name="useColors">1</option> or <colorPalette
    has_colors = bool(re.search(r'<option name="useColors">\s*(1|true)\s*</option>', xml, re.IGNORECASE)) or '<colorPalette' in xml
    if has_colors:
        score += POINTS_PER_CRITERION
        feedback.append("Color usage is enabled for Single Value.")
        subscores['color_enabled'] = True
    else:
        feedback.append("FAIL: Color thresholding/usage is not enabled.")
        subscores['color_enabled'] = False

    # Criterion 5: Stacked Trend Chart
    has_chart = '<chart>' in xml.lower()
    has_timechart = 'timechart' in xml.lower()
    has_stacked = bool(re.search(r'<option name="charting\.chart\.stackMode">\s*stacked(100)?\s*</option>', xml, re.IGNORECASE))
    
    if has_chart and has_timechart and has_stacked:
        score += POINTS_PER_CRITERION
        feedback.append("Stacked chart panel with timechart command found.")
        subscores['stacked_chart'] = True
    else:
        missing = []
        if not has_chart: missing.append("chart panel")
        if not has_timechart: missing.append("timechart SPL command")
        if not has_stacked: missing.append("stacked chart mode")
        feedback.append(f"FAIL: Missing elements for the trend panel: {', '.join(missing)}")
        subscores['stacked_chart'] = False

    passed = score >= PASS_THRESHOLD

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "subscores": subscores,
        "details": {
            "xml_length": len(xml),
            "score": score
        }
    }