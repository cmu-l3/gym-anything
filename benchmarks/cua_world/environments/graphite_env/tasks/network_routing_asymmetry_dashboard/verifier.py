#!/usr/bin/env python3
"""
Verifier for network_routing_asymmetry_dashboard task.

Scoring (100 pts, pass >= 60):
  10 pts: Dashboard named "Network Routing Asymmetry" exists
  10 pts: Graph "Raw Path Speeds" exists
  10 pts: Graph "Smoothed Asymmetry Alert" exists
  10 pts: Graph 1 aliases ("Path A" and "Path B") correctly assigned
  15 pts: Graph 2 has diffSeries
  15 pts: Graph 2 has absolute()
  15 pts: Graph 2 has movingAverage with window 5
  15 pts: Graph 2 has threshold(20, "Critical Limit", "red")
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

DASHBOARD_NAME = "Network Routing Asymmetry"
GRAPH_1_TITLE = "Raw Path Speeds"
GRAPH_2_TITLE = "Smoothed Asymmetry Alert"
RESULT_PATH = "/tmp/network_routing_asymmetry_dashboard_result.json"

def _get_graphs(dashboard_state):
    graphs = []
    raw_graphs = dashboard_state.get("graphs", [])
    for entry in raw_graphs:
        if not isinstance(entry, (list, tuple)) or len(entry) < 2:
            continue
        params = entry[1] if isinstance(entry[1], dict) else {}
        title = params.get("title", "")
        targets = params.get("target", [])
        if isinstance(targets, str):
            targets = [targets]
        graphs.append((title, [str(t) for t in targets]))
    return graphs

def _find_graph(graphs, expected_title):
    for title, targets in graphs:
        if title == expected_title:
            return title, targets
    for title, targets in graphs:
        if expected_title.lower() in title.lower():
            return title, targets
    return None, None

def verify_network_routing_asymmetry_dashboard(trajectory, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}
    
    score = 0
    feedback = []

    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            tmp_path = tmp.name
        copy_from_env(RESULT_PATH, tmp_path)
        with open(tmp_path) as f:
            result = json.load(f)
        os.unlink(tmp_path)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not load result file: {e}",
        }

    dashboards = result.get("dashboards", {})

    # Check 1: Dashboard exists (10 pts)
    if DASHBOARD_NAME not in dashboards:
        dash_found = None
        for k in dashboards:
            if k.lower() == DASHBOARD_NAME.lower():
                dash_found = k
                break
        if dash_found:
            dashboard_state = dashboards[dash_found]
            score += 10
            feedback.append(f"[+10] Dashboard '{dash_found}' found (case-insensitive match)")
        else:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Dashboard '{DASHBOARD_NAME}' not found. Present: {list(dashboards.keys())}"
            }
    else:
        dashboard_state = dashboards[DASHBOARD_NAME]
        score += 10
        feedback.append(f"[+10] Dashboard '{DASHBOARD_NAME}' exists")

    if "parse_error" in dashboard_state:
        return {
            "passed": False,
            "score": score,
            "feedback": f"Dashboard JSON parse error: {dashboard_state['parse_error']}"
        }

    graphs = _get_graphs(dashboard_state)

    # Check 2: Graph 1 exists & has correct targets (20 pts)
    g1_title, g1_targets = _find_graph(graphs, GRAPH_1_TITLE)
    if g1_targets is not None:
        score += 10
        feedback.append(f"[+10] Graph '{GRAPH_1_TITLE}' found")
        
        has_path_a = False
        has_path_b = False
        for t in g1_targets:
            tl = t.lower()
            if "speed_sensor_1" in tl and "alias(" in tl and re.search(r"path\s*a", tl):
                has_path_a = True
            if "speed_sensor_2" in tl and "alias(" in tl and re.search(r"path\s*b", tl):
                has_path_b = True
                
        if has_path_a and has_path_b:
            score += 10
            feedback.append("[+10] Graph 1 has Path A and Path B aliased correctly")
        else:
            feedback.append("[-] Graph 1 missing proper alias mapping for Path A and/or Path B")
    else:
        feedback.append(f"[-] Graph '{GRAPH_1_TITLE}' not found")

    # Check 3: Graph 2 exists & has correct analytical targets (60 pts)
    g2_title, g2_targets = _find_graph(graphs, GRAPH_2_TITLE)
    if g2_targets is not None:
        score += 10
        feedback.append(f"[+10] Graph '{GRAPH_2_TITLE}' found")
        
        has_diff = False
        has_abs = False
        has_ma = False
        has_threshold = False
        
        for t in g2_targets:
            tl = t.lower().replace(" ", "")
            # check diffSeries
            if "diffseries(" in tl and "speed_sensor_1" in tl and "speed_sensor_2" in tl:
                has_diff = True
            
            # check absolute
            if "absolute(" in tl:
                has_abs = True
                
            # check movingAverage(..., 5) using regex 
            if re.search(r"movingaverage\(.*?,['\"]?5['\"]?\)", tl):
                has_ma = True
                
            # check threshold(20, "Critical Limit", "red")
            if "threshold(" in tl and "20" in tl and "criticallimit" in tl and "red" in tl:
                has_threshold = True

        if has_diff:
            score += 15
            feedback.append("[+15] Graph 2 contains diffSeries with both sensors")
        else:
            feedback.append("[-] Graph 2 missing diffSeries with both sensors")
            
        if has_abs:
            score += 15
            feedback.append("[+15] Graph 2 applies absolute()")
        else:
            feedback.append("[-] Graph 2 missing absolute()")
            
        if has_ma:
            score += 15
            feedback.append("[+15] Graph 2 applies movingAverage(..., 5)")
        else:
            feedback.append("[-] Graph 2 missing movingAverage with window 5")
            
        if has_threshold:
            score += 15
            feedback.append("[+15] Graph 2 contains threshold(20, 'Critical Limit', 'red')")
        else:
            feedback.append("[-] Graph 2 missing proper threshold target")
    else:
        feedback.append(f"[-] Graph '{GRAPH_2_TITLE}' not found")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }