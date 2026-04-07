#!/usr/bin/env python3
"""
Verifier for network_traffic_rate_conversion task.

Scoring (100 pts, pass >= 60):
  10 pts  Dashboard 'Network Bandwidth Monitor' exists
  10 pts  Dashboard has >= 2 graphs
  10 pts  Graph 'Inbound Traffic Rate' found
  15 pts  Rate function (derivative/nonNegativeDerivative/perSecond) applied
  20 pts  scale() with factor 0.000008 present
  10 pts  alias() used for labeling
  10 pts  Graph 'Smoothed Traffic Rate' found
  15 pts  movingAverage() with window 5 applied to the pipeline
"""

import json
import os
import re
import tempfile

DASHBOARD_NAME = "Network Bandwidth Monitor"
GRAPH_RATE_TITLE = "Inbound Traffic Rate"
GRAPH_SMOOTH_TITLE = "Smoothed Traffic Rate"
TARGET_METRIC = "servers.ec2_instance_1.network.bytes_in"
RESULT_PATH = "/tmp/network_traffic_rate_conversion_result.json"

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

def verify_network_traffic_rate_conversion(trajectory, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}
    result_path = RESULT_PATH

    score = 0
    feedback = []

    # ── Load result file ──────────────────────────────────────────────────────
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            tmp_path = tmp.name
        copy_from_env(result_path, tmp_path)
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

    # ── Check 1: Dashboard exists (10 pts) ────────────────────────────────────
    # Case insensitive search just in case
    found_dashboard = None
    for d_name in dashboards.keys():
        if d_name.lower() == DASHBOARD_NAME.lower():
            found_dashboard = d_name
            break

    if not found_dashboard:
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                f"Dashboard '{DASHBOARD_NAME}' not found. "
                f"Present: {list(dashboards.keys())}"
            ),
        }
    
    score += 10
    feedback.append(f"[+10] Dashboard '{DASHBOARD_NAME}' exists")

    dashboard_state = dashboards[found_dashboard]
    if "parse_error" in dashboard_state:
        return {
            "passed": False,
            "score": score,
            "feedback": f"Dashboard JSON parse error: {dashboard_state['parse_error']}",
        }

    graphs = _get_graphs(dashboard_state)

    # ── Check 2: Has >= 2 graphs (10 pts) ─────────────────────────────────────
    if len(graphs) >= 2:
        score += 10
        feedback.append(f"[+10] Dashboard has {len(graphs)} graphs (>= 2)")
    else:
        feedback.append(f"[-] Expected >= 2 graphs, found {len(graphs)}")
        if len(graphs) == 0:
            return {"passed": False, "score": score, "feedback": "\n".join(feedback)}

    # ── Find specific graphs ──────────────────────────────────────────────────
    rate_match = _find_graph(graphs, GRAPH_RATE_TITLE)
    smooth_match = _find_graph(graphs, GRAPH_SMOOTH_TITLE)

    rate_targets = rate_match[1] if rate_match else None
    smooth_targets = smooth_match[1] if smooth_match else None

    # Fallback to identify by content if titles were mistyped
    if not rate_targets:
        for t, tgts in graphs:
            if tgts and not any("movingaverage" in tr.lower() for tr in tgts):
                rate_targets = tgts
                feedback.append(f"  (Using graph '{t}' for Inbound Rate checks)")
                break

    if not smooth_targets:
        for t, tgts in graphs:
            if tgts and any("movingaverage" in tr.lower() for tr in tgts):
                smooth_targets = tgts
                feedback.append(f"  (Using graph '{t}' for Smoothed Rate checks)")
                break

    # ── Check 3: Rate Graph exists (10 pts) ───────────────────────────────────
    if rate_match:
        score += 10
        feedback.append(f"[+10] Graph '{GRAPH_RATE_TITLE}' found")
    else:
        feedback.append(f"[-] Exact graph '{GRAPH_RATE_TITLE}' not found")

    # Evaluate Rate Targets
    has_rate = False
    has_scale = False
    has_alias = False

    if rate_targets:
        for target in rate_targets:
            # Must reference the target metric
            if TARGET_METRIC not in target:
                continue
            
            # Check Rate Function
            if re.search(r"(derivative|nonNegativeDerivative|perSecond)\s*\(", target, re.IGNORECASE):
                has_rate = True
            
            # Check Scale Factor (allow 0.000008, 8e-6, 8E-6, 0.8e-5)
            if re.search(r"scale\s*\(.*?(0\.000008|8e-0?6|0\.8e-0?5).*?\)", target, re.IGNORECASE):
                has_scale = True

            # Check Alias
            if re.search(r"alias\s*\(", target, re.IGNORECASE):
                has_alias = True

    if has_rate:
        score += 15
        feedback.append("[+15] Rate function applied to network metric")
    else:
        feedback.append("[-] Rate function (derivative/perSecond) missing")

    if has_scale:
        score += 20
        feedback.append("[+20] scale() with factor 0.000008 correctly applied")
    else:
        feedback.append("[-] scale() with factor 0.000008 missing or incorrect")

    if has_alias:
        score += 10
        feedback.append("[+10] alias() used for labeling")
    else:
        feedback.append("[-] alias() function missing")

    # ── Check 4: Smoothed Graph exists (10 pts) ───────────────────────────────
    if smooth_match:
        score += 10
        feedback.append(f"[+10] Graph '{GRAPH_SMOOTH_TITLE}' found")
    else:
        feedback.append(f"[-] Exact graph '{GRAPH_SMOOTH_TITLE}' not found")

    # Evaluate Smoothed Targets
    has_moving_avg = False
    if smooth_targets:
        for target in smooth_targets:
            if TARGET_METRIC not in target:
                continue
            
            # Check for movingAverage with window 5 (allow spaces, quotes)
            if re.search(r"movingAverage\s*\(.*?,?\s*['\"]?5(\.0)?['\"]?\s*\)", target, re.IGNORECASE):
                has_moving_avg = True

    if has_moving_avg:
        score += 15
        feedback.append("[+15] movingAverage() with window 5 applied successfully")
    else:
        feedback.append("[-] movingAverage() with window 5 missing or incorrect")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }