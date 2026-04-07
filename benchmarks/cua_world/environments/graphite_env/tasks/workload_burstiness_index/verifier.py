#!/usr/bin/env python3
"""
Verifier for workload_burstiness_index task.

Scoring (100 pts, pass >= 60):
  10 pts  Dashboard 'Workload Burstiness Index' exists

  For 'Compute Thrashing' graph (30 pts):
   5 pts  Graph title matches
   5 pts  Raw metric `servers.ec2_instance_1.cpu.utilization` present
  20 pts  Synthesized metric has all 4 nested functions + window 10 + alias name

  For 'Database Thrashing' graph (30 pts):
   5 pts  Graph title matches
   5 pts  Raw metric `servers.rds_database.cpu.utilization` present
  20 pts  Synthesized metric has all 4 nested functions + window 10 + alias name

  For 'Network Burstiness' graph (30 pts):
   5 pts  Graph title matches
   5 pts  Raw metric `servers.ec2_instance_1.network.bytes_in` present
  20 pts  Synthesized metric has all 4 nested functions + window 10 + alias name
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

DASHBOARD_NAME = "Workload Burstiness Index"
RESULT_PATH = "/tmp/workload_burstiness_index_result.json"

EXPECTED_GRAPHS = [
    {
        "title": "Compute Thrashing",
        "raw": "servers.ec2_instance_1.cpu.utilization",
        "alias": "CPU Volatility"
    },
    {
        "title": "Database Thrashing",
        "raw": "servers.rds_database.cpu.utilization",
        "alias": "DB Volatility"
    },
    {
        "title": "Network Burstiness",
        "raw": "servers.ec2_instance_1.network.bytes_in",
        "alias": "Network Volatility"
    }
]

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


def _find_graph_by_title(graphs, expected_title):
    """Find a graph by exact or partial title."""
    for title, targets in graphs:
        if title == expected_title:
            return title, targets
    for title, targets in graphs:
        if expected_title.lower() in title.lower():
            return title, targets
    return None, None


def _has_raw_metric(targets, raw_metric):
    """Check if the exact raw metric exists as a standalone target (or inside an alias)."""
    # Simply having the metric in ANY target string is technically passing the nested check.
    # To ensure it's plotted as a baseline, we want to see it either by itself or aliased,
    # but WITHOUT derivative/movingAverage functions applied.
    for t in targets:
        tl = t.lower()
        if raw_metric.lower() in tl:
            # If it's the raw target, it shouldn't have derivative
            if "derivative" not in tl and "movingaverage" not in tl:
                return True
    return False


def _has_nested_volatility_metric(targets, raw_metric, expected_alias):
    """
    Check if a target has the complete nested structure:
    alias(movingAverage(absolute(derivative(metric)), 10), "alias")
    """
    for t in targets:
        tl = t.lower()
        
        # Must contain all required function names and parameters
        has_alias = "alias" in tl
        has_ma = "movingaverage" in tl
        has_abs = "absolute" in tl
        has_deriv = "derivative" in tl
        has_raw = raw_metric.lower() in tl
        has_window = "10" in tl
        has_name = expected_alias.lower() in tl
        
        if all([has_alias, has_ma, has_abs, has_deriv, has_raw, has_window, has_name]):
            return True
            
    return False


def verify_workload_burstiness_index(trajectory, env_info, task_info):
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
            "feedback": f"Could not load result file: {e}",
        }

    dashboards = result.get("dashboards", {})

    # 2. Check Dashboard exists (10 pts)
    if DASHBOARD_NAME not in dashboards:
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                f"Dashboard '{DASHBOARD_NAME}' not found. "
                f"Present: {list(dashboards.keys())}"
            ),
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
    
    # 3. Process each expected graph (30 pts each)
    for expected in EXPECTED_GRAPHS:
        title = expected["title"]
        raw = expected["raw"]
        alias = expected["alias"]
        
        found_title, targets = _find_graph_by_title(graphs, title)
        
        if found_title:
            score += 5
            feedback_parts.append(f"[+5] Graph '{title}' found")
            
            # Check for baseline raw metric
            if _has_raw_metric(targets, raw):
                score += 5
                feedback_parts.append(f"[+5] Raw baseline metric {raw} present in '{title}'")
            else:
                feedback_parts.append(f"[-] Raw baseline metric {raw} missing in '{title}'")
                
            # Check for nested volatility index
            if _has_nested_volatility_metric(targets, raw, alias):
                score += 20
                feedback_parts.append(f"[+20] Volatility Index correctly synthesized for '{title}'")
            else:
                feedback_parts.append(f"[-] Volatility Index incorrect or missing for '{title}'")
                
        else:
            feedback_parts.append(f"[-] Graph '{title}' missing completely")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }