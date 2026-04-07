#!/usr/bin/env python3
"""
Verifier for capacity_headroom_inversion task.

Scoring (100 pts, pass >= 60):
  10 pts  Dashboard 'Capacity Headroom' exists
   5 pts  'RDS Compute Headroom' graph exists
  20 pts  RDS Math correct (diffSeries/constantLine or scale/offset with 100)
   5 pts  'Thermal Headroom' graph exists
  20 pts  Thermal Math correct (diffSeries/constantLine or scale/offset with 120)
   5 pts  'Total Fleet Idle CPU' graph exists
  15 pts  Fleet Aggregation uses sumSeries (or similar) on EC2 metrics
  20 pts  Fleet Math correct (diffSeries/constantLine or scale/offset with 300)
"""

import json
import os
import tempfile

DASHBOARD_NAME = "Capacity Headroom"
RESULT_PATH = "/tmp/capacity_headroom_inversion_result.json"

def _get_graphs(dashboard_state):
    """Extract list of (title, targets_list) from dashboard state dict."""
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

def _check_inversion(targets, metric_keyword, expected_const):
    """
    Checks if any target achieves the inversion metric transformation:
    Approach A: diffSeries(constantLine(X), metric)
    Approach B: offset(scale(metric, -1), X)
    """
    for t in targets:
        tl = t.lower()
        if metric_keyword.lower() not in tl:
            continue
        
        const_str = str(expected_const)
        
        # Check Approach A (diffSeries and constantLine)
        has_diff = "diffseries" in tl and "constantline" in tl and const_str in tl
        
        # Check Approach B (scale by -1 and offset)
        has_offset = "offset" in tl and "scale" in tl and "-1" in tl and const_str in tl
        
        if has_diff or has_offset:
            return True
            
    return False

def _check_fleet_aggregation(targets):
    """Checks if the targets aggregate the fleet (e.g., using sumSeries)."""
    for t in targets:
        tl = t.lower()
        if "ec2_instance" in tl and ("sumseries" in tl or "sum" in tl):
            return True
    return False

def verify_capacity_headroom_inversion(trajectory, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    score = 0
    feedback_parts = []

    # 1. Load exported result file
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

    # 3. RDS Headroom Graph
    rds_graph = _find_graph(graphs, "RDS Compute Headroom")
    if rds_graph:
        score += 5
        feedback_parts.append("[+5] 'RDS Compute Headroom' graph found")
        
        if _check_inversion(rds_graph[1], "rds_database", 100):
            score += 20
            feedback_parts.append("[+20] RDS inversion math correct (100 - utilization)")
        else:
            feedback_parts.append("[-] RDS inversion math incorrect or missing constant '100'")
    else:
        feedback_parts.append("[-] 'RDS Compute Headroom' graph not found")

    # 4. Thermal Headroom Graph
    thermal_graph = _find_graph(graphs, "Thermal Headroom")
    if thermal_graph:
        score += 5
        feedback_parts.append("[+5] 'Thermal Headroom' graph found")
        
        if _check_inversion(thermal_graph[1], "machine_temperature", 120):
            score += 20
            feedback_parts.append("[+20] Thermal inversion math correct (120 - temperature)")
        else:
            feedback_parts.append("[-] Thermal inversion math incorrect or missing constant '120'")
    else:
        feedback_parts.append("[-] 'Thermal Headroom' graph not found")

    # 5. Fleet Headroom Graph
    fleet_graph = _find_graph(graphs, "Total Fleet Idle CPU")
    if fleet_graph:
        score += 5
        feedback_parts.append("[+5] 'Total Fleet Idle CPU' graph found")
        
        if _check_fleet_aggregation(fleet_graph[1]):
            score += 15
            feedback_parts.append("[+15] Fleet aggregation (sumSeries) detected")
        else:
            feedback_parts.append("[-] Fleet aggregation (sumSeries) missing")

        if _check_inversion(fleet_graph[1], "ec2_instance", 300):
            score += 20
            feedback_parts.append("[+20] Fleet inversion math correct (300 - sum)")
        else:
            feedback_parts.append("[-] Fleet inversion math incorrect or missing constant '300'")
    else:
        feedback_parts.append("[-] 'Total Fleet Idle CPU' graph not found")

    passed = score >= 60 and (score >= 45) # Need at least some math patterns to pass alongside structure
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }