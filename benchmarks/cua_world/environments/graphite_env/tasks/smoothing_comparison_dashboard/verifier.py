#!/usr/bin/env python3
"""
Verifier for smoothing_comparison_dashboard task.

Scoring (100 pts, pass >= 60):
  10 pts  Dashboard 'Smoothing Comparison' exists
   5 pts  Dashboard has >= 3 graphs
  
  Graph 1: "Raw vs SMA Temperature"
  10 pts  Title match
   5 pts  Raw machine_temperature target present
  10 pts  movingAverage(machine_temperature, 20) present
  
  Graph 2: "Raw vs EMA Temperature"
  10 pts  Title match
   5 pts  Raw machine_temperature target present
  15 pts  exponentialMovingAverage(machine_temperature, 20) present
  
  Graph 3: "Median vs Average CPU Filter"
  10 pts  Title match
   5 pts  movingAverage(ec2_instance_2, 20) present
  15 pts  movingMedian(ec2_instance_2, 20) present
"""

import json
import os
import re
import tempfile

DASHBOARD_NAME = "Smoothing Comparison"
RESULT_PATH = "/tmp/smoothing_comparison_dashboard_result.json"

GRAPH_1_TITLE = "Raw vs SMA Temperature"
GRAPH_2_TITLE = "Raw vs EMA Temperature"
GRAPH_3_TITLE = "Median vs Average CPU Filter"


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


def _has_function_target(targets, func_name, metric_kw, window):
    """
    Robust regex check for specific smoothing functions with explicit window size.
    Prevents "movingAverage" from matching "exponentialMovingAverage".
    """
    t_func = func_name.lower()
    t_met = metric_kw.replace(" ", "").lower()
    t_win = str(window)
    
    # Matches: funcName( ... metricKw ... , '20' )
    pattern = t_func + r'\([^,]*' + re.escape(t_met) + r'[^,]*,[\'"]?' + re.escape(t_win) + r'[\'"]?[,\)]'
    
    for t in targets:
        t_clean = t.replace(" ", "").lower()
        
        # Guard: if we're looking for movingaverage, ensure it's not exponentialmovingaverage
        if t_func == "movingaverage":
            idx = t_clean.find("movingaverage(")
            if idx > 0 and t_clean[idx-1].isalpha():
                continue
                
        if re.search(pattern, t_clean):
            return True
    return False


def _has_raw_target(targets, metric_kw):
    """
    Check if the metric is present without any smoothing functions applied.
    """
    t_met = metric_kw.replace(" ", "").lower()
    for t in targets:
        t_clean = t.replace(" ", "").lower()
        if t_met in t_clean:
            # Must NOT contain the smoothing functions
            if not any(x in t_clean for x in ["movingaverage", "movingmedian", "exponential"]):
                return True
    return False


def verify_smoothing_comparison_dashboard(trajectory, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "details": "copy_from_env unavailable"}
    
    score = 0
    details = []

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
            "details": f"Could not load result file: {e}",
        }

    dashboards = result.get("dashboards", {})

    # ── Check 1: Dashboard exists (10 pts) ────────────────────────────────────
    if DASHBOARD_NAME not in dashboards:
        # Fallback to case-insensitive match
        matched_name = next((k for k in dashboards.keys() if k.lower() == DASHBOARD_NAME.lower()), None)
        if matched_name:
            dashboard_state = dashboards[matched_name]
            score += 10
            details.append(f"[+10] Dashboard found (case-insensitive): {matched_name}")
        else:
            return {
                "passed": False,
                "score": 0,
                "details": (
                    f"Dashboard '{DASHBOARD_NAME}' not found. "
                    f"Present: {list(dashboards.keys())}"
                ),
            }
    else:
        dashboard_state = dashboards[DASHBOARD_NAME]
        score += 10
        details.append(f"[+10] Dashboard '{DASHBOARD_NAME}' exists")

    if "parse_error" in dashboard_state:
        return {
            "passed": False,
            "score": score,
            "details": f"Dashboard JSON parse error: {dashboard_state['parse_error']}",
        }

    graphs = _get_graphs(dashboard_state)

    # ── Check 2: Has >= 3 graphs (5 pts) ─────────────────────────────────────
    if len(graphs) >= 3:
        score += 5
        details.append(f"[+5] Dashboard has {len(graphs)} graph(s)")
    else:
        details.append(f"[-] Dashboard only has {len(graphs)} graphs, expected >= 3")

    # ── Graph 1: SMA Temperature (25 pts) ────────────────────────────────────
    g1_match = _find_graph(graphs, GRAPH_1_TITLE)
    if g1_match:
        score += 10
        details.append(f"[+10] Graph 1 '{GRAPH_1_TITLE}' found")
        g1_targets = g1_match[1]
    else:
        details.append(f"[-] Graph 1 '{GRAPH_1_TITLE}' not found, attempting loose metric matching...")
        g1_targets = next((t for _, t in graphs if any("machine_temperature" in x for x in t)), [])

    if g1_targets:
        if _has_raw_target(g1_targets, "machine_temperature"):
            score += 5
            details.append("[+5] Graph 1 contains raw machine_temperature target")
        else:
            details.append("[-] Graph 1 missing raw machine_temperature target")

        if _has_function_target(g1_targets, "movingAverage", "machine_temperature", 20):
            score += 10
            details.append("[+10] Graph 1 contains movingAverage(..., 20)")
        else:
            details.append("[-] Graph 1 missing movingAverage(..., 20)")

    # ── Graph 2: EMA Temperature (30 pts) ────────────────────────────────────
    g2_match = _find_graph(graphs, GRAPH_2_TITLE)
    if g2_match:
        score += 10
        details.append(f"[+10] Graph 2 '{GRAPH_2_TITLE}' found")
        g2_targets = g2_match[1]
    else:
        details.append(f"[-] Graph 2 '{GRAPH_2_TITLE}' not found, attempting loose metric matching...")
        # Avoid reusing G1 targets if possible
        g2_targets = next((t for _, t in graphs if any("exponential" in x for x in t)), [])

    if g2_targets:
        if _has_raw_target(g2_targets, "machine_temperature"):
            score += 5
            details.append("[+5] Graph 2 contains raw machine_temperature target")
        else:
            details.append("[-] Graph 2 missing raw machine_temperature target")

        if _has_function_target(g2_targets, "exponentialMovingAverage", "machine_temperature", 20):
            score += 15
            details.append("[+15] Graph 2 contains exponentialMovingAverage(..., 20)")
        else:
            details.append("[-] Graph 2 missing exponentialMovingAverage(..., 20)")

    # ── Graph 3: Median vs Average CPU (30 pts) ──────────────────────────────
    g3_match = _find_graph(graphs, GRAPH_3_TITLE)
    if g3_match:
        score += 10
        details.append(f"[+10] Graph 3 '{GRAPH_3_TITLE}' found")
        g3_targets = g3_match[1]
    else:
        details.append(f"[-] Graph 3 '{GRAPH_3_TITLE}' not found, attempting loose metric matching...")
        g3_targets = next((t for _, t in graphs if any("ec2_instance_2" in x for x in t)), [])

    if g3_targets:
        if _has_function_target(g3_targets, "movingAverage", "ec2_instance_2.cpu.utilization", 20):
            score += 5
            details.append("[+5] Graph 3 contains movingAverage(..., 20)")
        else:
            details.append("[-] Graph 3 missing movingAverage(..., 20)")

        if _has_function_target(g3_targets, "movingMedian", "ec2_instance_2.cpu.utilization", 20):
            score += 15
            details.append("[+15] Graph 3 contains movingMedian(..., 20)")
        else:
            details.append("[-] Graph 3 missing movingMedian(..., 20)")

    # ── Final Assessment ──────────────────────────────────────────────────────
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(details)
    }