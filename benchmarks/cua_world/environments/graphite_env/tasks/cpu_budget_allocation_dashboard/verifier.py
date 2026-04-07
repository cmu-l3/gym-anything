#!/usr/bin/env python3
"""
Verifier for cpu_budget_allocation_dashboard task.

Scoring (100 pts, pass >= 60):
  10 pts  Dashboard 'CPU Budget Allocation' exists
   5 pts  Dashboard has >= 2 graphs
  10 pts  Graph 'Instance CPU Share' found
  10 pts  asPercent target for ec2_instance_1
  10 pts  asPercent target for ec2_instance_2
  10 pts  asPercent target for ec2_instance_3 (cloudwatch)
   5 pts  sumSeries used as denominator in asPercent including all 3 instances
   5 pts  areaMode set to stacked on 'Instance CPU Share'
  10 pts  Graph 'Fleet CPU Spread' found
  10 pts  rangeOfSeries target with EC2 CPU metrics
   8 pts  maxSeries target with EC2 CPU metrics
   7 pts  minSeries target with EC2 CPU metrics
"""

import json
import os
import tempfile

DASHBOARD_NAME = "CPU Budget Allocation"
SHARE_GRAPH_TITLE = "Instance CPU Share"
SPREAD_GRAPH_TITLE = "Fleet CPU Spread"
RESULT_PATH = "/tmp/cpu_budget_allocation_dashboard_result.json"

def _get_graphs(dashboard_state):
    """Return list of (title, targets_list, params_dict) from dashboard state dict."""
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
        graphs.append((title, [str(t) for t in targets], params))
    return graphs

def _find_graph(graphs, expected_title):
    """Find a graph by exact title, then case-insensitive. Returns (title, targets, params) or None."""
    for title, targets, params in graphs:
        if title == expected_title:
            return title, targets, params
    for title, targets, params in graphs:
        if expected_title.lower() in title.lower():
            return title, targets, params
    return None

def verify_cpu_budget_allocation_dashboard(trajectory, env_info, task_info):
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

    # 2. Check Dashboard exists (10 pts)
    if DASHBOARD_NAME not in dashboards:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Dashboard '{DASHBOARD_NAME}' not found. Present: {list(dashboards.keys())}"
        }
    score += 10
    feedback_parts.append(f"Dashboard '{DASHBOARD_NAME}' exists")

    dashboard_state = dashboards[DASHBOARD_NAME]
    if "parse_error" in dashboard_state:
        return {
            "passed": False,
            "score": score,
            "feedback": f"Dashboard JSON parse error: {dashboard_state['parse_error']}"
        }

    graphs = _get_graphs(dashboard_state)

    # 3. Check >= 2 graphs (5 pts)
    if len(graphs) >= 2:
        score += 5
        feedback_parts.append(f"Dashboard has {len(graphs)} graphs (>= 2)")
    else:
        feedback_parts.append(f"Expected >= 2 graphs, found {len(graphs)}")
        if not graphs:
            return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # 4. Check 'Instance CPU Share' Graph
    share_match = _find_graph(graphs, SHARE_GRAPH_TITLE)
    if share_match:
        share_title, share_targets, share_params = share_match
        score += 10
        feedback_parts.append(f"Graph '{SHARE_GRAPH_TITLE}' found")

        # Evaluate targets for asPercent
        found_aspercent_1 = False
        found_aspercent_2 = False
        found_aspercent_3 = False
        found_sumseries_all = False

        for t in share_targets:
            tl = t.lower()
            if "aspercent" in tl:
                if "ec2_instance_1" in tl: found_aspercent_1 = True
                if "ec2_instance_2" in tl: found_aspercent_2 = True
                if "ec2_instance_3" in tl: found_aspercent_3 = True

            # Check if sumSeries is acting as a denominator with all 3 instances
            if "sumseries" in tl and "ec2_instance_1" in tl and "ec2_instance_2" in tl and "ec2_instance_3" in tl:
                found_sumseries_all = True
            
            # Wildcard denominator check
            if "sumseries" in tl and ("ec2_instance_*" in tl or "ec2_instance_?" in tl):
                found_sumseries_all = True

        if found_aspercent_1:
            score += 10
            feedback_parts.append("asPercent applied to instance 1")
        if found_aspercent_2:
            score += 10
            feedback_parts.append("asPercent applied to instance 2")
        if found_aspercent_3:
            score += 10
            feedback_parts.append("asPercent applied to instance 3")
        if found_sumseries_all:
            score += 5
            feedback_parts.append("sumSeries denominator includes all instances")

        # Check for stacked area mode (can be in params dict or stacked() function in targets)
        is_stacked = False
        if str(share_params).lower().find("'areamode': 'stacked'") != -1:
            is_stacked = True
        elif str(share_params).lower().find("'linemode': 'stacked'") != -1:
            is_stacked = True
        elif any("stacked(" in t.lower() for t in share_targets):
            is_stacked = True

        if is_stacked:
            score += 5
            feedback_parts.append("Graph rendering mode is stacked")
        else:
            feedback_parts.append("Graph is missing stacked area mode")
            
    else:
        feedback_parts.append(f"Graph '{SHARE_GRAPH_TITLE}' not found")

    # 5. Check 'Fleet CPU Spread' Graph
    spread_match = _find_graph(graphs, SPREAD_GRAPH_TITLE)
    if spread_match:
        spread_title, spread_targets, spread_params = spread_match
        score += 10
        feedback_parts.append(f"Graph '{SPREAD_GRAPH_TITLE}' found")

        found_range = False
        found_max = False
        found_min = False

        for t in spread_targets:
            tl = t.lower()
            if "rangeofseries" in tl and ("ec2_instance" in tl or "cpu" in tl):
                found_range = True
            if "maxseries" in tl and ("ec2_instance" in tl or "cpu" in tl):
                found_max = True
            if "minseries" in tl and ("ec2_instance" in tl or "cpu" in tl):
                found_min = True

        if found_range:
            score += 10
            feedback_parts.append("rangeOfSeries target present")
        if found_max:
            score += 8
            feedback_parts.append("maxSeries target present")
        if found_min:
            score += 7
            feedback_parts.append("minSeries target present")
    else:
        feedback_parts.append(f"Graph '{SPREAD_GRAPH_TITLE}' not found")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }