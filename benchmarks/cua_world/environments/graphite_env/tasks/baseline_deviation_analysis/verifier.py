#!/usr/bin/env python3
"""
Verifier for baseline_deviation_analysis task.

Scoring (100 pts, pass >= 60):
  10 pts  Dashboard "Baseline Deviation Analysis" exists
   5 pts  Dashboard has >= 3 graphs
   5 pts  Graph titled "CPU Deviation from Baseline" found
  12 pts  Graph 1 contains diffSeries function
  10 pts  Graph 1 contains movingAverage with window 50
   3 pts  Graph 1 references ec2_instance_1.cpu.utilization
   5 pts  Graph titled "Instance 1 CPU Fleet Share" found
  12 pts  Graph 2 contains asPercent function
   8 pts  Graph 2 contains sumSeries aggregating EC2 fleet
   5 pts  Graph titled "Smoothed Traffic Rate" found
  12 pts  Graph 3 contains exponentialMovingAverage
   5 pts  Graph 3 EMA window is 20
   8 pts  Graph 3 contains alias function
"""

import json
import os
import tempfile

DASHBOARD_NAME = "Baseline Deviation Analysis"
RESULT_PATH = "/tmp/baseline_deviation_analysis_result.json"

GRAPH_1_TITLE = "CPU Deviation from Baseline"
GRAPH_2_TITLE = "Instance 1 CPU Fleet Share"
GRAPH_3_TITLE = "Smoothed Traffic Rate"

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
    """Find a graph by exact title, then case-insensitive. Returns (title, targets) or (None, None)."""
    for title, targets in graphs:
        if title == expected_title:
            return title, targets
    for title, targets in graphs:
        if expected_title.lower() in title.lower():
            return title, targets
    return None, None

def _targets_str(targets):
    """Join all targets into one lowercase string for broad substring search."""
    return " ".join(targets).lower()

def verify_baseline_deviation_analysis(trajectory, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    score = 0
    feedback = []

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

    # 2. Check Dashboard exists (10 pts)
    if DASHBOARD_NAME not in dashboards:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Dashboard '{DASHBOARD_NAME}' not found. Present: {list(dashboards.keys())}"
        }
    score += 10
    feedback.append(f"[+10] Dashboard '{DASHBOARD_NAME}' exists")

    dashboard_state = dashboards[DASHBOARD_NAME]
    if "parse_error" in dashboard_state:
        return {
            "passed": False,
            "score": score,
            "feedback": f"Dashboard JSON parse error: {dashboard_state['parse_error']}"
        }

    graphs = _get_graphs(dashboard_state)

    # 3. Check Dashboard has >= 3 graphs (5 pts)
    if len(graphs) >= 3:
        score += 5
        feedback.append(f"[+5] Dashboard contains {len(graphs)} graphs")
    else:
        feedback.append(f"[-] Dashboard contains only {len(graphs)} graphs (expected >= 3)")

    # 4. Check Graph 1: CPU Deviation from Baseline
    t1, tgt1 = _find_graph(graphs, GRAPH_1_TITLE)
    if tgt1 is not None:
        score += 5
        feedback.append(f"[+5] Graph 1 '{GRAPH_1_TITLE}' found")
        t_str = _targets_str(tgt1)
        
        if "diffseries" in t_str:
            score += 12
            feedback.append("[+12] Graph 1 contains diffSeries")
        else:
            feedback.append("[-] Graph 1 missing diffSeries function")
            
        if "movingaverage" in t_str and "50" in t_str:
            score += 10
            feedback.append("[+10] Graph 1 contains movingAverage with window 50")
        else:
            feedback.append("[-] Graph 1 missing movingAverage(..., 50)")
            
        if "ec2_instance_1.cpu.utilization" in t_str:
            score += 3
            feedback.append("[+3] Graph 1 references instance 1 CPU metric")
    else:
        feedback.append(f"[-] Graph 1 '{GRAPH_1_TITLE}' not found")

    # 5. Check Graph 2: Instance 1 CPU Fleet Share
    t2, tgt2 = _find_graph(graphs, GRAPH_2_TITLE)
    if tgt2 is not None:
        score += 5
        feedback.append(f"[+5] Graph 2 '{GRAPH_2_TITLE}' found")
        t_str = _targets_str(tgt2)
        
        if "aspercent" in t_str:
            score += 12
            feedback.append("[+12] Graph 2 contains asPercent")
        else:
            feedback.append("[-] Graph 2 missing asPercent function")
            
        if "sumseries" in t_str and "ec2_instance" in t_str:
            score += 8
            feedback.append("[+8] Graph 2 contains sumSeries aggregating fleet")
        else:
            feedback.append("[-] Graph 2 missing sumSeries function for fleet")
    else:
        feedback.append(f"[-] Graph 2 '{GRAPH_2_TITLE}' not found")

    # 6. Check Graph 3: Smoothed Traffic Rate
    t3, tgt3 = _find_graph(graphs, GRAPH_3_TITLE)
    if tgt3 is not None:
        score += 5
        feedback.append(f"[+5] Graph 3 '{GRAPH_3_TITLE}' found")
        t_str = _targets_str(tgt3)
        
        if "exponentialmovingaverage" in t_str:
            score += 12
            feedback.append("[+12] Graph 3 contains exponentialMovingAverage")
        else:
            feedback.append("[-] Graph 3 missing exponentialMovingAverage function")
            
        # Match '20' as a discrete argument usually
        if "20" in t_str:
            score += 5
            feedback.append("[+5] Graph 3 EMA window is 20")
        else:
            feedback.append("[-] Graph 3 missing window 20")
            
        if "alias" in t_str:
            score += 8
            feedback.append("[+8] Graph 3 contains alias function")
        else:
            feedback.append("[-] Graph 3 missing alias function")
    else:
        feedback.append(f"[-] Graph 3 '{GRAPH_3_TITLE}' not found")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }