#!/usr/bin/env python3
"""
Verifier for normalized_ux_degradation_analysis task.

Scoring (100 pts, pass >= 60):
  10 pts  Dashboard 'UX Correlation Analysis' exists
   5 pts  Dashboard has >= 3 graphs
  15 pts  Graph 'Raw Speed' uses averageSeries on speed sensors
  15 pts  Graph 'Request Rate' uses derivative on LB requests
  10 pts  Graph 'Normalized System Behavior' exists
  15 pts  Normalized Load target (normalize + derivative + alias "Load Shape")
  15 pts  Normalized DB target (normalize + alias "DB Shape")
  15 pts  Normalized Speed target (normalize + averageSeries + alias "Speed Shape")
"""

import json
import os
import tempfile
import re

DASHBOARD_NAME = "UX Correlation Analysis"
RESULT_PATH = "/tmp/normalized_ux_degradation_analysis_result.json"

GRAPH_RAW_SPEED = "Raw Speed"
GRAPH_REQUEST_RATE = "Request Rate"
GRAPH_NORMALIZED = "Normalized System Behavior"


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


def _has_target(targets, required_keywords):
    """Check if any target contains ALL the required keywords (case-insensitive)."""
    for t in targets:
        tl = t.lower()
        if all(kw.lower() in tl for kw in required_keywords):
            return True
    return False


def verify_normalized_ux_degradation_analysis(trajectory, env_info, task_info):
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
            "feedback": f"Could not load result file: {e}",
        }

    dashboards = result.get("dashboards", {})

    # ── Check 1: Dashboard exists (10 pts) ────────────────────────────────────
    if DASHBOARD_NAME not in dashboards:
        # Fallback check for close matches
        found_name = None
        for name in dashboards.keys():
            if "UX Correlation" in name or "Correlation Analysis" in name:
                found_name = name
                break
        
        if not found_name:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Dashboard '{DASHBOARD_NAME}' not found. Present: {list(dashboards.keys())}"
            }
        else:
            dashboard_state = dashboards[found_name]
            score += 5
            feedback_parts.append(f"[+5] Dashboard found with slightly incorrect name: '{found_name}'")
    else:
        dashboard_state = dashboards[DASHBOARD_NAME]
        score += 10
        feedback_parts.append(f"[+10] Dashboard '{DASHBOARD_NAME}' exists")

    if "parse_error" in dashboard_state:
        return {
            "passed": False,
            "score": score,
            "feedback": f"Dashboard JSON parse error: {dashboard_state['parse_error']}"
        }

    graphs = _get_graphs(dashboard_state)

    # ── Check 2: Has >= 3 graphs (5 pts) ──────────────────────────────────────
    if len(graphs) >= 3:
        score += 5
        feedback_parts.append(f"[+5] Dashboard has {len(graphs)} graphs (>= 3)")
    else:
        feedback_parts.append(f"[-] Expected 3 graphs, found {len(graphs)}")

    # ── Check 3: Raw Speed Graph (15 pts) ─────────────────────────────────────
    raw_speed_match = _find_graph(graphs, GRAPH_RAW_SPEED)
    if raw_speed_match:
        title, targets = raw_speed_match
        if _has_target(targets, ["averageSeries", "speed_sensor"]):
            score += 15
            feedback_parts.append(f"[+15] '{GRAPH_RAW_SPEED}' graph correct (averageSeries + speed_sensor)")
        else:
            feedback_parts.append(f"[-] '{GRAPH_RAW_SPEED}' graph found but missing averageSeries or speed_sensor")
    else:
        feedback_parts.append(f"[-] Graph '{GRAPH_RAW_SPEED}' not found")

    # ── Check 4: Request Rate Graph (15 pts) ──────────────────────────────────
    req_rate_match = _find_graph(graphs, GRAPH_REQUEST_RATE)
    if req_rate_match:
        title, targets = req_rate_match
        # Accept either derivative or nonNegativeDerivative
        has_derivative = _has_target(targets, ["derivative", "requests.count"]) or \
                         _has_target(targets, ["nonnegativederivative", "requests.count"])
        if has_derivative:
            score += 15
            feedback_parts.append(f"[+15] '{GRAPH_REQUEST_RATE}' graph correct (derivative + requests.count)")
        else:
            feedback_parts.append(f"[-] '{GRAPH_REQUEST_RATE}' graph found but missing derivative function")
    else:
        feedback_parts.append(f"[-] Graph '{GRAPH_REQUEST_RATE}' not found")

    # ── Check 5: Normalized System Behavior Graph (10 + 3x15 pts) ─────────────
    norm_match = _find_graph(graphs, GRAPH_NORMALIZED)
    if norm_match:
        title, targets = norm_match
        score += 10
        feedback_parts.append(f"[+10] Graph '{GRAPH_NORMALIZED}' exists")

        # Target A: Normalized Load
        has_derivative = any("derivative" in t.lower() for t in targets)
        has_norm_load = _has_target(targets, ["normalize", "requests.count", "load shape"]) and has_derivative
        if has_norm_load:
            score += 15
            feedback_parts.append(f"[+15] Normalized Load target is correct")
        else:
            feedback_parts.append(f"[-] Normalized Load target missing or incorrect (needs normalize, derivative, requests.count, alias 'Load Shape')")

        # Target B: Normalized DB
        if _has_target(targets, ["normalize", "rds_database.cpu", "db shape"]):
            score += 15
            feedback_parts.append(f"[+15] Normalized DB target is correct")
        else:
            feedback_parts.append(f"[-] Normalized DB target missing or incorrect (needs normalize, rds_database.cpu, alias 'DB Shape')")

        # Target C: Normalized Speed
        if _has_target(targets, ["normalize", "averageseries", "speed_sensor", "speed shape"]):
            score += 15
            feedback_parts.append(f"[+15] Normalized Speed target is correct")
        else:
            feedback_parts.append(f"[-] Normalized Speed target missing or incorrect (needs normalize, averageSeries, speed_sensor, alias 'Speed Shape')")
    else:
        feedback_parts.append(f"[-] Graph '{GRAPH_NORMALIZED}' not found")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }