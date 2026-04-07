#!/usr/bin/env python3
"""
Verifier for monitoring_system_meta_observability task.

Scoring (100 pts, pass >= 60):
  10 pts  Dashboard 'Graphite Health' exists
  10 pts  Dashboard has >= 4 graphs
  20 pts  Graph 1: 'Global Ingestion Rate' contains alias(sumSeries(carbon.agents.*.metricsReceived), "Total Metrics/min")
  20 pts  Graph 2: 'Average CPU User Time' contains alias(averageSeries(collectd.*.cpu-user), "Avg User CPU")
  20 pts  Graph 3: 'System Load' contains aliasByNode(collectd.*.load.load.shortterm, 1)
  20 pts  Graph 4: 'Carbon Cache Size' contains aliasByNode(carbon.agents.*.cache.size, 2)
"""

import json
import os
import tempfile
import re

DASHBOARD_NAME = "Graphite Health"
RESULT_PATH = "/tmp/monitoring_system_meta_observability_result.json"


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


def _check_target(targets, required_elements):
    """Check if ANY target contains ALL required elements (case-insensitive)."""
    for t in targets:
        t_lower = t.lower()
        if all(req.lower() in t_lower for req in required_elements):
            return True
    return False


def verify_monitoring_system_meta_observability(trajectory, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    score = 0
    feedback_parts = []

    # ── Load result file ──────────────────────────────────────────────────────
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

    # ── Check 1: Dashboard exists (10 pts) ────────────────────────────────────
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

    # ── Check 2: Has >= 4 graphs (10 pts) ─────────────────────────────────────
    if len(graphs) >= 4:
        score += 10
        feedback_parts.append(f"[+10] Dashboard has {len(graphs)} graphs (>= 4)")
    else:
        feedback_parts.append(f"[-] Expected >= 4 graphs, found {len(graphs)}")

    # ── Check 3: Graph 1 - Global Ingestion Rate (20 pts) ─────────────────────
    g1 = _find_graph(graphs, "Global Ingestion Rate")
    if g1:
        title, targets = g1
        if _check_target(targets, ["alias", "sumSeries", "carbon.agents.*.metricsReceived", "Total Metrics/min"]):
            score += 20
            feedback_parts.append("[+20] 'Global Ingestion Rate' correctly configured")
        else:
            feedback_parts.append("[-] 'Global Ingestion Rate' found but target configuration is incorrect")
    else:
        # Fallback check by function signature across all graphs
        found_target = False
        for _, targets in graphs:
            if _check_target(targets, ["alias", "sumSeries", "carbon.agents.*.metricsReceived", "Total Metrics/min"]):
                found_target = True
                break
        if found_target:
            score += 15
            feedback_parts.append("[+15] 'Global Ingestion Rate' target found but graph title was wrong")
        else:
            feedback_parts.append("[-] 'Global Ingestion Rate' graph/target missing")

    # ── Check 4: Graph 2 - Average CPU User Time (20 pts) ─────────────────────
    g2 = _find_graph(graphs, "Average CPU User Time")
    if g2:
        title, targets = g2
        # Use substring "cpu-user" instead of full path to allow collectd.*.cpu-*.cpu-user variations
        if _check_target(targets, ["alias", "averageSeries", "cpu-user", "Avg User CPU"]):
            score += 20
            feedback_parts.append("[+20] 'Average CPU User Time' correctly configured")
        else:
            feedback_parts.append("[-] 'Average CPU User Time' found but target configuration is incorrect")
    else:
        found_target = False
        for _, targets in graphs:
            if _check_target(targets, ["alias", "averageSeries", "cpu-user", "Avg User CPU"]):
                found_target = True
                break
        if found_target:
            score += 15
            feedback_parts.append("[+15] 'Average CPU User Time' target found but graph title was wrong")
        else:
            feedback_parts.append("[-] 'Average CPU User Time' graph/target missing")

    # ── Check 5: Graph 3 - System Load (20 pts) ───────────────────────────────
    g3 = _find_graph(graphs, "System Load")
    if g3:
        title, targets = g3
        if _check_target(targets, ["aliasByNode", "load.shortterm", "1"]):
            score += 20
            feedback_parts.append("[+20] 'System Load' correctly configured")
        else:
            feedback_parts.append("[-] 'System Load' found but target configuration is incorrect")
    else:
        found_target = False
        for _, targets in graphs:
            if _check_target(targets, ["aliasByNode", "load.shortterm", "1"]):
                found_target = True
                break
        if found_target:
            score += 15
            feedback_parts.append("[+15] 'System Load' target found but graph title was wrong")
        else:
            feedback_parts.append("[-] 'System Load' graph/target missing")

    # ── Check 6: Graph 4 - Carbon Cache Size (20 pts) ─────────────────────────
    g4 = _find_graph(graphs, "Carbon Cache Size")
    if g4:
        title, targets = g4
        if _check_target(targets, ["aliasByNode", "carbon.agents.*.cache.size", "2"]):
            score += 20
            feedback_parts.append("[+20] 'Carbon Cache Size' correctly configured")
        else:
            feedback_parts.append("[-] 'Carbon Cache Size' found but target configuration is incorrect")
    else:
        found_target = False
        for _, targets in graphs:
            if _check_target(targets, ["aliasByNode", "cache.size", "2"]):
                found_target = True
                break
        if found_target:
            score += 15
            feedback_parts.append("[+15] 'Carbon Cache Size' target found but graph title was wrong")
        else:
            feedback_parts.append("[-] 'Carbon Cache Size' graph/target missing")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }