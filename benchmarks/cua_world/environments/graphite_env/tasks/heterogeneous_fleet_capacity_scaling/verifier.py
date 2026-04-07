#!/usr/bin/env python3
"""
Verifier for heterogeneous_fleet_capacity_scaling task.

Scoring (100 pts, pass >= 60):
  10 pts  Dashboard 'Heterogeneous Fleet Capacity' exists
  10 pts  Dashboard has >= 2 graphs
  15 pts  Small nodes (Instances 1 & 2) correctly scaled by 0.02
  15 pts  Massive node (Instance 3) correctly scaled by 0.16 (using cloudwatch_utilization)
  15 pts  'Total Active Cores' uses sumSeries() correctly wrapping the three scaled targets
  10 pts  'Naive Average' uses averageSeries() correctly
  20 pts  'True Weighted Average' correctly uses multi-level nesting: scale(sumSeries(...), 5)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

DASHBOARD_NAME = "Heterogeneous Fleet Capacity"
RESULT_PATH = "/tmp/heterogeneous_fleet_capacity_scaling_result.json"

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
    return None, None

def _has_target(targets, reqs):
    """Check if any target string contains all the required lowercase keywords, with spaces removed."""
    for t in targets:
        tl = t.replace(" ", "").lower()
        if all(r.lower() in tl for r in reqs):
            return True
    return False

def verify_heterogeneous_fleet_capacity_scaling(trajectory, env_info, task_info):
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
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                f"Dashboard '{DASHBOARD_NAME}' not found. "
                f"Dashboards present: {list(dashboards.keys())}"
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

    # ── Check 2: Has >= 2 graphs (10 pts) ─────────────────────────────────────
    if len(graphs) >= 2:
        score += 10
        feedback_parts.append(f"[+10] Dashboard has {len(graphs)} graphs (>= 2)")
    else:
        feedback_parts.append(f"[-] Expected >= 2 graphs, found {len(graphs)}")

    # ── Identify the two target graphs ─────────────────────────────────────────
    g1_title, g1_targets = _find_graph(graphs, "Active Compute Cores")
    g2_title, g2_targets = _find_graph(graphs, "Fleet Utilization: Naive vs True")

    # ── Check Graph 1: Active Compute Cores ────────────────────────────────────
    if g1_targets:
        feedback_parts.append(f"Graph 'Active Compute Cores' found")
        
        # Small Nodes Scaled (15 pts)
        if _has_target(g1_targets, ["scale", "ec2_instance_1", "0.02"]) and \
           _has_target(g1_targets, ["scale", "ec2_instance_2", "0.02"]):
            score += 15
            feedback_parts.append("[+15] Small nodes (Instance 1 & 2) correctly scaled by 0.02")
        else:
            feedback_parts.append("[-] Small nodes missing correct scale(..., 0.02)")

        # Massive Node Scaled (15 pts)
        if _has_target(g1_targets, ["scale", "ec2_instance_3", "cloudwatch", "0.16"]):
            score += 15
            feedback_parts.append("[+15] Massive node (Instance 3) correctly scaled by 0.16")
        else:
            feedback_parts.append("[-] Massive node missing correct scale(..., 0.16)")

        # Total Active Cores config (15 pts)
        if _has_target(g1_targets, ["sumseries", "scale", "ec2_instance_1", "0.02", "ec2_instance_3", "0.16"]):
            score += 15
            feedback_parts.append("[+15] 'Total Active Cores' sumSeries wraps correctly scaled targets")
        else:
            feedback_parts.append("[-] 'Total Active Cores' missing or not wrapping correctly")
    else:
        feedback_parts.append("[-] Graph 'Active Compute Cores' not found")

    # ── Check Graph 2: Fleet Utilization: Naive vs True ───────────────────────
    if g2_targets:
        feedback_parts.append(f"Graph 'Fleet Utilization: Naive vs True' found")
        
        # Naive Average (10 pts)
        if _has_target(g2_targets, ["averageseries", "ec2_instance_"]):
            score += 10
            feedback_parts.append("[+10] 'Naive Average' configured using averageSeries")
        else:
            feedback_parts.append("[-] 'Naive Average' missing or incorrect")

        # True Weighted Average (20 pts)
        if _has_target(g2_targets, ["scale", "sumseries", "ec2_instance_3", "0.16", "ec2_instance_1", "0.02", "5"]):
            score += 20
            feedback_parts.append("[+20] 'True Weighted Average' configured correctly with complex multi-level nesting")
        else:
            feedback_parts.append("[-] 'True Weighted Average' multi-level scaling incorrect")
    else:
        feedback_parts.append("[-] Graph 'Fleet Utilization: Naive vs True' not found")

    # ── Final Eval ─────────────────────────────────────────────────────────────
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }