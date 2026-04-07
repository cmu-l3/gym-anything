#!/usr/bin/env python3
"""
Verifier for datacenter_thermal_analysis task.

Scoring (100 pts, pass >= 60):
  10 pts  Dashboard 'Datacenter Thermal Analysis' exists
   5 pts  Dashboard has >= 3 graphs
  10 pts  Graph 'Temperature with Thresholds' found
  10 pts  Raw machine_temperature metric in thresholds graph
  10 pts  threshold() at value 80 present
  10 pts  threshold() at value 100 present
  10 pts  Graph 'Thermal-CPU Correlation' found
  10 pts  Both machine_temperature and ec2_instance_1 CPU in correlation graph
  10 pts  scale() function applied to CPU metric
  10 pts  Graph 'Temperature Rate of Change' found
   5 pts  derivative() wrapping machine_temperature
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

DASHBOARD_NAME = "Datacenter Thermal Analysis"
RESULT_PATH = "/tmp/datacenter_thermal_analysis_result.json"

GRAPH1_TITLE = "Temperature with Thresholds"
GRAPH2_TITLE = "Thermal-CPU Correlation"
GRAPH3_TITLE = "Temperature Rate of Change"

METRIC_TEMP = "machine_temperature"
METRIC_CPU = "ec2_instance_1"


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


def verify_datacenter_thermal_analysis(trajectory, env_info, task_info):
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
        return {"passed": False, "score": 0, "feedback": f"Could not load result file: {e}"}

    dashboards = result.get("dashboards", {})

    # 2. Check Dashboard Existence (10 pts)
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
        return {"passed": False, "score": score, "feedback": f"Dashboard JSON parse error: {dashboard_state['parse_error']}"}

    graphs = _get_graphs(dashboard_state)

    # 3. Check graph count (5 pts)
    if len(graphs) >= 3:
        score += 5
        feedback_parts.append(f"[+5] Dashboard has {len(graphs)} graphs (>= 3)")
    else:
        feedback_parts.append(f"[-] Expected >= 3 graphs, found {len(graphs)}")

    # ---------------------------------------------------------------------
    # GRAPH 1: Temperature with Thresholds
    # ---------------------------------------------------------------------
    g1 = _find_graph(graphs, GRAPH1_TITLE)
    if g1:
        score += 10
        feedback_parts.append(f"[+10] Graph '{GRAPH1_TITLE}' found")
        targets = g1[1]
        t_str = " ".join(targets).lower()

        if METRIC_TEMP in t_str:
            score += 10
            feedback_parts.append(f"[+10] Metric '{METRIC_TEMP}' present")
        else:
            feedback_parts.append(f"[-] Metric '{METRIC_TEMP}' missing in {GRAPH1_TITLE}")

        # Check for threshold 80
        if re.search(r'threshold\([^,]*80\b', t_str):
            score += 10
            feedback_parts.append("[+10] threshold(80) function found")
        else:
            feedback_parts.append("[-] threshold(80) function missing")

        # Check for threshold 100
        if re.search(r'threshold\([^,]*100\b', t_str):
            score += 10
            feedback_parts.append("[+10] threshold(100) function found")
        else:
            feedback_parts.append("[-] threshold(100) function missing")
    else:
        feedback_parts.append(f"[-] Graph '{GRAPH1_TITLE}' not found")

    # ---------------------------------------------------------------------
    # GRAPH 2: Thermal-CPU Correlation
    # ---------------------------------------------------------------------
    g2 = _find_graph(graphs, GRAPH2_TITLE)
    if g2:
        score += 10
        feedback_parts.append(f"[+10] Graph '{GRAPH2_TITLE}' found")
        targets = g2[1]
        t_str = " ".join(targets).lower()

        if METRIC_TEMP in t_str and METRIC_CPU in t_str:
            score += 10
            feedback_parts.append(f"[+10] Both {METRIC_TEMP} and {METRIC_CPU} present")
        else:
            feedback_parts.append(f"[-] Missing required metrics in {GRAPH2_TITLE}")

        # Check for scale(..., 1.5)
        if re.search(r'scale\(.*ec2_instance_1.*1\.5', t_str) or ('scale' in t_str and '1.5' in t_str):
            score += 10
            feedback_parts.append("[+10] scale(1.5) applied to CPU metric")
        else:
            feedback_parts.append("[-] scale(..., 1.5) function missing")
    else:
        feedback_parts.append(f"[-] Graph '{GRAPH2_TITLE}' not found")

    # ---------------------------------------------------------------------
    # GRAPH 3: Temperature Rate of Change
    # ---------------------------------------------------------------------
    g3 = _find_graph(graphs, GRAPH3_TITLE)
    if g3:
        score += 10
        feedback_parts.append(f"[+10] Graph '{GRAPH3_TITLE}' found")
        targets = g3[1]
        t_str = " ".join(targets).lower()

        if 'derivative' in t_str and METRIC_TEMP in t_str:
            score += 5
            feedback_parts.append(f"[+5] derivative() applied to {METRIC_TEMP}")
        else:
            feedback_parts.append("[-] derivative() function missing or not applied correctly")
    else:
        feedback_parts.append(f"[-] Graph '{GRAPH3_TITLE}' not found")

    # Pass/Fail determination
    # Max score = 10 + 5 + (10+10+10+10) + (10+10+10) + (10+5) = 100
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }