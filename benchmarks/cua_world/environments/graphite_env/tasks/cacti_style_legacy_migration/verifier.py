#!/usr/bin/env python3
"""
Verifier for cacti_style_legacy_migration task.

Scoring System (100 pts, pass >= 65):
  10 pts  Dashboard "NOC Legacy View" exists
   5 pts  Dashboard has >= 3 graphs
  10 pts  Graph "CPU Utilization (Cacti)" found
  15 pts  cactiStyle applied to CPU wildcard metric
  10 pts  Graph "Traffic & I/O (Styled)" found
  10 pts  Green color applied to network bytes
  10 pts  Blue color applied to disk bytes
  10 pts  Graph "Temperature with Baseline" found
  10 pts  lineWidth = 3 applied to temperature metric
  10 pts  aggregateLine with "avg" applied to temperature metric
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

DASHBOARD_NAME = "NOC Legacy View"
RESULT_PATH = "/tmp/cacti_style_legacy_migration_result.json"

def _get_graphs(dashboard_state):
    """Return list of (title, targets_list) from dashboard state dict."""
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

def verify_cacti_style_legacy_migration(trajectory, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    score = 0
    feedback_parts = []

    # 1. Load exported result JSON from the container
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

    # 2. Check Dashboard Existence
    if DASHBOARD_NAME not in dashboards:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Dashboard '{DASHBOARD_NAME}' not found. Dashboards present: {list(dashboards.keys())}",
        }
    
    score += 10
    feedback_parts.append(f"[+10] Dashboard '{DASHBOARD_NAME}' exists")

    dashboard_state = dashboards[DASHBOARD_NAME]
    if "parse_error" in dashboard_state:
        return {
            "passed": False,
            "score": score,
            "feedback": f"Dashboard JSON parse error: {dashboard_state['parse_error']}",
        }

    graphs = _get_graphs(dashboard_state)

    # 3. Check graph count
    if len(graphs) >= 3:
        score += 5
        feedback_parts.append(f"[+5] Dashboard contains {len(graphs)} graphs")
    else:
        feedback_parts.append(f"[-] Dashboard only contains {len(graphs)} graphs (expected 3)")

    # 4. Check Graph 1: CPU Utilization (Cacti)
    g1_targets = None
    for title, targets in graphs:
        if "cpu utilization (cacti)" in title.lower():
            g1_targets = targets
            score += 10
            feedback_parts.append("[+10] Graph 'CPU Utilization (Cacti)' found")
            break
            
    if g1_targets:
        has_cacti = False
        for t in g1_targets:
            tl = t.lower()
            if "cactistyle" in tl and "cpu" in tl and "ec2_instance" in tl:
                has_cacti = True
                break
        if has_cacti:
            score += 15
            feedback_parts.append("[+15] cactiStyle applied to CPU metrics")
        else:
            feedback_parts.append("[-] cactiStyle not properly applied to CPU metrics")

    # 5. Check Graph 2: Traffic & I/O (Styled)
    g2_targets = None
    for title, targets in graphs:
        if "traffic" in title.lower() and "styled" in title.lower():
            g2_targets = targets
            score += 10
            feedback_parts.append("[+10] Graph 'Traffic & I/O (Styled)' found")
            break
            
    if g2_targets:
        has_green_net = False
        has_blue_disk = False
        
        for t in g2_targets:
            tl = t.lower()
            if "color(" in tl and "network" in tl and ("'green'" in tl or '"green"' in tl):
                has_green_net = True
            if "color(" in tl and "disk" in tl and ("'blue'" in tl or '"blue"' in tl):
                has_blue_disk = True
                
        if has_green_net:
            score += 10
            feedback_parts.append("[+10] Green color applied to network metric")
        else:
            feedback_parts.append("[-] Green color not applied to network metric")
            
        if has_blue_disk:
            score += 10
            feedback_parts.append("[+10] Blue color applied to disk metric")
        else:
            feedback_parts.append("[-] Blue color not applied to disk metric")

    # 6. Check Graph 3: Temperature with Baseline
    g3_targets = None
    for title, targets in graphs:
        if "temperature" in title.lower() and "baseline" in title.lower():
            g3_targets = targets
            score += 10
            feedback_parts.append("[+10] Graph 'Temperature with Baseline' found")
            break
            
    if g3_targets:
        has_linewidth = False
        has_aggline = False
        
        for t in g3_targets:
            tl = t.lower()
            if "linewidth(" in tl and "temperature" in tl and "3" in tl:
                has_linewidth = True
            if "aggregateline(" in tl and "temperature" in tl and ("'avg'" in tl or '"avg"' in tl):
                has_aggline = True
                
        if has_linewidth:
            score += 10
            feedback_parts.append("[+10] lineWidth=3 applied to temperature")
        else:
            feedback_parts.append("[-] lineWidth=3 not applied to temperature")
            
        if has_aggline:
            score += 10
            feedback_parts.append("[+10] aggregateLine(avg) applied to temperature")
        else:
            feedback_parts.append("[-] aggregateLine with avg not applied to temperature")

    passed = score >= 65
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }