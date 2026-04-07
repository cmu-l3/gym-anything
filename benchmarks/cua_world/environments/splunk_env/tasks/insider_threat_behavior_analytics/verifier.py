#!/usr/bin/env python3
"""Verifier for insider_threat_behavior_analytics task.

Scoring (Total = 100):
1. Dashboard Exists (15 pts) - The dashboard was created.
2. Time Picker Input (15 pts) - Dashboard contains a time picker input.
3. Token Wiring (20 pts) - The panel searches use the time picker tokens (e.g. $token.earliest$).
4. Concurrent Logic (25 pts) - Panel 1 correctly implements distinct count and 15m binning with a >1 threshold.
5. Off-Hours Logic (25 pts) - Panel 2 correctly implements date_hour filtering for hours 0-4.
"""

import json
import tempfile
import os
import re
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

POINTS_PER_CRITERION = {
    "dashboard_exists": 15,
    "time_picker_exists": 15,
    "token_wiring": 20,
    "concurrent_logic": 25,
    "off_hours_logic": 25
}

def check_concurrent_logic(query):
    query = query.lower()
    if 'makeresults' in query:
        return False
    if 'security_logs' not in query:
        return False
    
    # Needs temporal binning / timechart
    has_binning = bool(re.search(r'(bin|timechart|bucket).*span=15m', query))
    if not has_binning:
        return False
        
    # Needs distinct count of IPs
    has_dc = bool(re.search(r'(dc|distinct_count)\s*\(', query))
    if not has_dc:
        return False
        
    # Needs filtering for >= 2 or > 1
    has_filter = bool(re.search(r'(>|>=)\s*[12]', query)) or bool(re.search(r'[12]\s*(<|<=)', query))
    if not has_filter:
        return False
        
    return True

def check_off_hours_logic(query):
    query = query.lower()
    if 'makeresults' in query:
        return False
    if 'security_logs' not in query:
        return False
        
    # Look for date_hour filtering (< 5, <= 4, IN(0,1,2,3,4)) or strftime logic
    has_date_hour = bool(re.search(r'date_hour\s*(<|<=|in|=)\s*[0-5]', query))
    has_strftime = bool(re.search(r'strftime', query)) and bool(re.search(r'(<|<=|in|=)\s*[0-5]', query))
    
    return has_date_hour or has_strftime

def extract_xml_components(xml_string):
    try:
        root = ET.fromstring(xml_string)
    except ET.ParseError:
        return None
        
    inputs = []
    for inp in root.findall('.//input'):
        inputs.append(inp.attrib.get('type', ''))
        
    searches = []
    for search in root.findall('.//search'):
        query_elem = search.find('query')
        if query_elem is not None and query_elem.text:
            earliest = search.find('earliest')
            latest = search.find('latest')
            searches.append({
                "query": query_elem.text,
                "earliest": earliest.text if earliest is not None else "",
                "latest": latest.text if latest is not None else ""
            })
            
    return {"inputs": inputs, "searches": searches}

def verify_insider_threat_behavior_analytics(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/insider_threat_behavior_analytics_result.json", tmp.name)
        with open(tmp.name) as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    analysis = data.get('analysis', {})
    found_target = analysis.get('found_target', False)
    target_xml = analysis.get('target_dashboard_xml', '')
    new_dashboards = analysis.get('new_dashboards', [])

    score = 0
    feedback = []
    subscores = {}

    # Criterion 1: Dashboard Exists
    best_xml = ""
    if found_target and target_xml:
        score += POINTS_PER_CRITERION["dashboard_exists"]
        feedback.append("Target dashboard 'Insider_Threat_Analytics' exists")
        subscores['dashboard_exists'] = True
        best_xml = target_xml
    elif new_dashboards:
        score += POINTS_PER_CRITERION["dashboard_exists"]
        best_xml = new_dashboards[0].get('xml_data', '')
        feedback.append(f"Dashboard created (used fallback matching: {new_dashboards[0].get('name')})")
        subscores['dashboard_exists'] = True
    else:
        feedback.append("FAIL: No new dashboard created")
        subscores['dashboard_exists'] = False
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback), "subscores": subscores}

    components = extract_xml_components(best_xml)
    if not components:
        feedback.append("FAIL: Could not parse dashboard XML")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback), "subscores": subscores}

    # Criterion 2: Time Picker Input
    if 'time' in components['inputs']:
        score += POINTS_PER_CRITERION["time_picker_exists"]
        feedback.append("Time picker input found")
        subscores['time_picker_exists'] = True
    else:
        feedback.append("FAIL: No time picker input found")
        subscores['time_picker_exists'] = False

    searches = components['searches']
    
    # Criterion 3: Token Wiring
    wired = False
    for s in searches:
        if s['earliest'] and s['latest'] and '$' in s['earliest'] and '$' in s['latest']:
            wired = True
            break
            
    if wired:
        score += POINTS_PER_CRITERION["token_wiring"]
        feedback.append("Time picker tokens wired to search panels")
        subscores['token_wiring'] = True
    else:
        feedback.append("FAIL: Searches are not using tokenized earliest/latest times")
        subscores['token_wiring'] = False

    # Criterion 4: Concurrent Logic
    concurrent_passed = False
    for s in searches:
        if check_concurrent_logic(s['query']):
            concurrent_passed = True
            break
            
    if concurrent_passed:
        score += POINTS_PER_CRITERION["concurrent_logic"]
        feedback.append("Concurrent IP logic (Panel 1) correctly implemented")
        subscores['concurrent_logic'] = True
    else:
        feedback.append("FAIL: Concurrent IP logic not found or incorrect (needs bin span=15m, dc(ip), and filter >=2)")
        subscores['concurrent_logic'] = False

    # Criterion 5: Off-Hours Logic
    off_hours_passed = False
    for s in searches:
        if check_off_hours_logic(s['query']):
            off_hours_passed = True
            break
            
    if off_hours_passed:
        score += POINTS_PER_CRITERION["off_hours_logic"]
        feedback.append("Off-hours logic (Panel 2) correctly implemented")
        subscores['off_hours_logic'] = True
    else:
        feedback.append("FAIL: Off-hours logic not found or incorrect (needs date_hour filtering)")
        subscores['off_hours_logic'] = False

    # Pass Threshold is 75 points, and at least one core behavioral logic must be correctly written
    passed = score >= 75 and (concurrent_passed or off_hours_passed)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "subscores": subscores
    }