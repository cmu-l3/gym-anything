#!/usr/bin/env python3
"""
Verifier for flapping_alert_noise_reduction task.

Scoring (100 pts, pass >= 70):
  10 pts  Dashboard 'Alert Noise Reduction' exists
  10 pts  Dashboard has >= 3 graphs
  10 pts  Graph 'Sustained EC2 Load (>85%)' found
  10 pts  EC2 target uses removeBelowValue(..., 85)
  10 pts  EC2 target uses movingAverage(..., 5)
  10 pts  Graph 'Sustained RDS Load (>60%)' found
  10 pts  RDS target uses removeBelowValue(..., 60)
  10 pts  RDS target uses movingAverage(..., 4)
   5 pts  Graph 'Instance 1 Noise Differential' found
  10 pts  Differential target uses diffSeries() with movingAverage
   5 pts  Differential target order is correct (raw metric minus smoothed)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

DASHBOARD_NAME = "Alert Noise Reduction"
RESULT_PATH = "/tmp/flapping_alert_noise_reduction_result.json"

GRAPH1_TITLE = "Sustained EC2 Load (>85%)"
GRAPH2_TITLE = "Sustained RDS Load (>60%)"
GRAPH3_TITLE = "Instance 1 Noise Differential"

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

def _find_graph(graphs, expected_title):
    """Find a graph by exact title, then case-insensitive. Returns (title, targets) or None."""
    for title, targets in graphs:
        if title == expected_title:
            return title, targets
    for title, targets in graphs:
        if expected_title.lower() in title.lower():
            return title, targets
    return None

def _clean_target(t):
    """Normalize target string for easier substring matching."""
    return t.lower().replace(" ", "").replace('"', '').replace("'", "")

def verify_flapping_alert_noise_reduction(trajectory, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    score = 0
    feedback_parts = []

    # 1. Load result file
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
            "feedback": f"Could not load result file: {e}"
        }

    dashboards = result.get("dashboards", {})

    # 2. Check Dashboard Exists (10 pts)
    if DASHBOARD_NAME not in dashboards:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Dashboard '{DASHBOARD_NAME}' not found. Present: {list(dashboards.keys())}"
        }
    score += 10
    feedback_parts.append(f"[+10] Dashboard '{DASHBOARD_NAME}' exists")

    dashboard_state = dashboards[DASHBOARD_NAME]
    if "parse_error" in dashboard_state:
        return {
            "passed": False,
            "score": score,
            "feedback": f"Dashboard JSON parse error: {dashboard_state['parse_error']}"
        }

    graphs = _get_graphs(dashboard_state)

    # 3. Check >= 3 graphs (10 pts)
    if len(graphs) >= 3:
        score += 10
        feedback_parts.append(f"[+10] Dashboard has {len(graphs)} graphs")
    else:
        feedback_parts.append(f"[-] Expected 3 graphs, found {len(graphs)}")

    # 4. Check Graph 1: Sustained EC2 Load (>85%)
    g1 = _find_graph(graphs, GRAPH1_TITLE)
    if g1:
        score += 10
        feedback_parts.append(f"[+10] Graph '{GRAPH1_TITLE}' found")
        targets = g1[1]
        
        has_rm_below = False
        has_ma = False
        for t in targets:
            ct = _clean_target(t)
            if "removebelowvalue" in ct and "85" in ct and "ec2_instance" in ct:
                has_rm_below = True
            if "movingaverage" in ct and "5" in ct and "ec2_instance" in ct:
                has_ma = True
                
        if has_rm_below:
            score += 10
            feedback_parts.append("[+10] EC2 target uses removeBelowValue(..., 85)")
        else:
            feedback_parts.append("[-] EC2 target missing removeBelowValue with threshold 85")
            
        if has_ma:
            score += 10
            feedback_parts.append("[+10] EC2 target uses movingAverage(..., 5)")
        else:
            feedback_parts.append("[-] EC2 target missing movingAverage with window 5")
    else:
        feedback_parts.append(f"[-] Graph '{GRAPH1_TITLE}' not found")

    # 5. Check Graph 2: Sustained RDS Load (>60%)
    g2 = _find_graph(graphs, GRAPH2_TITLE)
    if g2:
        score += 10
        feedback_parts.append(f"[+10] Graph '{GRAPH2_TITLE}' found")
        targets = g2[1]
        
        has_rm_below = False
        has_ma = False
        for t in targets:
            ct = _clean_target(t)
            if "removebelowvalue" in ct and "60" in ct and "rds_database" in ct:
                has_rm_below = True
            if "movingaverage" in ct and "4" in ct and "rds_database" in ct:
                has_ma = True
                
        if has_rm_below:
            score += 10
            feedback_parts.append("[+10] RDS target uses removeBelowValue(..., 60)")
        else:
            feedback_parts.append("[-] RDS target missing removeBelowValue with threshold 60")
            
        if has_ma:
            score += 10
            feedback_parts.append("[+10] RDS target uses movingAverage(..., 4)")
        else:
            feedback_parts.append("[-] RDS target missing movingAverage with window 4")
    else:
        feedback_parts.append(f"[-] Graph '{GRAPH2_TITLE}' not found")

    # 6. Check Graph 3: Instance 1 Noise Differential
    g3 = _find_graph(graphs, GRAPH3_TITLE)
    if g3:
        score += 5
        feedback_parts.append(f"[+5] Graph '{GRAPH3_TITLE}' found")
        targets = g3[1]
        
        has_diff = False
        has_correct_order = False
        for t in targets:
            ct = _clean_target(t)
            if "diffseries" in ct and "movingaverage" in ct and "ec2_instance_1" in ct:
                has_diff = True
                # Check order: we want diffSeries(raw_metric, movingAverage(raw_metric, 5))
                idx_diff = ct.find("diffseries(")
                idx_raw = ct.find("ec2_instance_1")
                idx_ma = ct.find("movingaverage(")
                
                # The raw metric should appear before the moving average function
                if -1 < idx_diff < idx_raw < idx_ma:
                    has_correct_order = True
                
        if has_diff:
            score += 10
            feedback_parts.append("[+10] Differential target uses diffSeries() and movingAverage()")
        else:
            feedback_parts.append("[-] Differential target missing diffSeries or movingAverage combination")
            
        if has_correct_order:
            score += 5
            feedback_parts.append("[+5] Differential target order is correct (raw - smoothed)")
        elif has_diff:
            feedback_parts.append("[-] Differential target order is inverted (should be raw minus smoothed)")
    else:
        feedback_parts.append(f"[-] Graph '{GRAPH3_TITLE}' not found")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }