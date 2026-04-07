#!/usr/bin/env python3
"""
Verifier for cost_efficiency_ratios task.

Scoring (100 pts, pass >= 60):
  10 pts  Dashboard 'Cost Efficiency Ratios' exists
   5 pts  Dashboard has >= 4 graphs
  20 pts  "Network per CPU" graph has divideSeries() with correct metrics
  15 pts  "Fleet CPU Aggregate" graph has sumSeries() with all 3 explicit metrics
  10 pts  "Fleet CPU Aggregate" graph wraps sumSeries() in alias()
  20 pts  "Disk IO per Request" graph has divideSeries() with cross-tier metrics
  15 pts  "Hourly CPU Summary" graph has summarize() with "1h" interval
   5 pts  All 4 exact graph titles match expected
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

DASHBOARD_NAME = "Cost Efficiency Ratios"
RESULT_PATH = "/tmp/cost_efficiency_ratios_result.json"


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


def _has_wildcard(target):
    """Detect if target contains common wildcards used to game specific metric enumerations."""
    t = target.lower()
    return "ec2_instance_*" in t or "ec2_instance_?" in t


def _find_graph_targets(graphs, exact_title, fallback_keywords):
    """Return targets for a matching graph title, or fallback to keyword match."""
    # 1. Exact match
    for title, targets in graphs:
        if title == exact_title:
            return targets
    
    # 2. Case-insensitive match
    for title, targets in graphs:
        if exact_title.lower() in title.lower():
            return targets
            
    # 3. Fallback to metrics content match
    for title, targets in graphs:
        targets_str = " ".join(targets).lower()
        if all(kw.lower() in targets_str for kw in fallback_keywords):
            return targets
            
    return None


def verify_cost_efficiency_ratios(trajectory, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    score = 0
    feedback_parts = []
    
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

    # Criterion 1: Dashboard existence
    if DASHBOARD_NAME not in dashboards:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Dashboard '{DASHBOARD_NAME}' not found.",
        }
    
    score += 10
    feedback_parts.append(f"[+10] Dashboard '{DASHBOARD_NAME}' exists")
    dashboard_state = dashboards[DASHBOARD_NAME]

    if "parse_error" in dashboard_state:
        return {
            "passed": False,
            "score": score,
            "feedback": f"Dashboard parse error: {dashboard_state['parse_error']}",
        }

    graphs = _get_graphs(dashboard_state)

    # Criterion 2: Number of graphs
    if len(graphs) >= 4:
        score += 5
        feedback_parts.append(f"[+5] Dashboard has {len(graphs)} graphs (>= 4)")
    else:
        feedback_parts.append(f"[-] Dashboard has only {len(graphs)} graphs")

    # Track exact title matches for bonus
    exact_titles_found = 0
    expected_titles = ["Network per CPU", "Fleet CPU Aggregate", "Disk IO per Request", "Hourly CPU Summary"]
    actual_titles = [g[0] for g in graphs]
    for expected in expected_titles:
        if expected in actual_titles:
            exact_titles_found += 1

    # Graph 1: Network per CPU
    g1_targets = _find_graph_targets(graphs, "Network per CPU", ["divide", "network"])
    if g1_targets:
        targets_str = " ".join(g1_targets).lower()
        if "divideseries" in targets_str and "network.bytes_in" in targets_str and "cpu.utilization" in targets_str:
            score += 20
            feedback_parts.append("[+20] Network per CPU: divideSeries with correct metrics")
        else:
            feedback_parts.append("[-] Network per CPU: Target missing divideSeries or expected metrics")
    else:
        feedback_parts.append("[-] Network per CPU graph not found")

    # Graph 2: Fleet CPU Aggregate
    g2_targets = _find_graph_targets(graphs, "Fleet CPU Aggregate", ["sumseries", "ec2_instance"])
    if g2_targets:
        targets_str = " ".join(g2_targets).lower()
        if _has_wildcard(targets_str):
            feedback_parts.append("[-] Fleet CPU Aggregate: Wildcard used. Must explicitly declare instances.")
        else:
            has_sum = "sumseries" in targets_str
            has_i1 = "ec2_instance_1.cpu.utilization" in targets_str
            has_i2 = "ec2_instance_2.cpu.utilization" in targets_str
            has_i3 = "ec2_instance_3.cpu.cloudwatch_utilization" in targets_str
            
            if has_sum and has_i1 and has_i2 and has_i3:
                score += 15
                feedback_parts.append("[+15] Fleet CPU Aggregate: sumSeries with 3 explicit metrics")
                
                # Check for alias() wrapping
                if "alias(" in targets_str or "alias (" in targets_str:
                    score += 10
                    feedback_parts.append("[+10] Fleet CPU Aggregate: alias() function used correctly")
                else:
                    feedback_parts.append("[-] Fleet CPU Aggregate: missing alias() function")
            else:
                feedback_parts.append("[-] Fleet CPU Aggregate: Missing sumSeries or one of the explicit metrics")
    else:
        feedback_parts.append("[-] Fleet CPU Aggregate graph not found")

    # Graph 3: Disk IO per Request
    g3_targets = _find_graph_targets(graphs, "Disk IO per Request", ["divide", "disk"])
    if g3_targets:
        targets_str = " ".join(g3_targets).lower()
        if "divideseries" in targets_str and "disk.write_bytes" in targets_str and "requests.count" in targets_str:
            score += 20
            feedback_parts.append("[+20] Disk IO per Request: divideSeries with correct cross-tier metrics")
        else:
            feedback_parts.append("[-] Disk IO per Request: Target missing divideSeries or expected metrics")
    else:
        feedback_parts.append("[-] Disk IO per Request graph not found")

    # Graph 4: Hourly CPU Summary
    g4_targets = _find_graph_targets(graphs, "Hourly CPU Summary", ["summarize"])
    if g4_targets:
        targets_str = " ".join(g4_targets).lower()
        # Accept '1h' or "1h"
        if "summarize" in targets_str and "ec2_instance_2" in targets_str and "1h" in targets_str:
            score += 15
            feedback_parts.append("[+15] Hourly CPU Summary: summarize with '1h' interval")
        else:
            feedback_parts.append("[-] Hourly CPU Summary: Target missing summarize, ec2_instance_2, or '1h'")
    else:
        feedback_parts.append("[-] Hourly CPU Summary graph not found")

    # Bonus: Exact titles
    if exact_titles_found == 4:
        score += 5
        feedback_parts.append("[+5] All 4 graph titles exactly match expected names")

    # Calculate final status
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }