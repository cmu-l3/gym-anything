#!/usr/bin/env python3
"""
Verifier for db_saturation_impact_overlay task.

Scoring (100 pts, pass >= 70):
  10 pts  Dashboard 'DB Saturation Impact' exists
   5 pts  Graph 'DB Saturation Bands' exists
  10 pts  Graph 1 contains raw RDS CPU metric
  20 pts  Graph 1 contains fully constructed drawAsInfinite/removeBelowValue alert band
   5 pts  Graph 'Traffic Drop Correlation' exists
  15 pts  Graph 2 contains derivative(load_balancer.requests.count)
  15 pts  Graph 2 contains the cross-metric alert band
   5 pts  Graph 'DB CPU Velocity' exists
  10 pts  Graph 3 contains derivative(RDS CPU)
   5 pts  Graph 3 contains threshold(0) with blue coloring
"""

import json
import os
import tempfile

DASHBOARD_NAME = "DB Saturation Impact"
RESULT_PATH = "/tmp/db_saturation_impact_overlay_result.json"

GRAPH_1_TITLE = "DB Saturation Bands"
GRAPH_2_TITLE = "Traffic Drop Correlation"
GRAPH_3_TITLE = "DB CPU Velocity"


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


def _targets_contain(targets, required_substrings):
    """Return True if any single target contains ALL required substrings (case-insensitive)."""
    for t in targets:
        tl = t.lower()
        if all(sub.lower() in tl for sub in required_substrings):
            return True
    return False


def verify_db_saturation_impact_overlay(trajectory, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}
    result_path = RESULT_PATH

    score = 0
    feedback_parts = []

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
    has_valid_band_anywhere = False

    # ── Check 2: Graph 1 - DB Saturation Bands ────────────────────────────────
    g1_match = _find_graph(graphs, GRAPH_1_TITLE)
    if g1_match:
        score += 5
        feedback_parts.append(f"[+5] Graph '{GRAPH_1_TITLE}' found")
        g1_title, g1_targets = g1_match

        # Sub-check: Raw RDS CPU metric (10 pts)
        # Note: Must be the raw metric, not just inside a function
        raw_found = False
        for t in g1_targets:
            tl = t.lower()
            if "rds_database.cpu.utilization" in tl and "removebelowvalue" not in tl:
                raw_found = True
                break
        
        if raw_found:
            score += 10
            feedback_parts.append(f"[+10] Raw RDS CPU metric found in Graph 1")
        else:
            feedback_parts.append(f"[-] Raw RDS CPU metric missing in Graph 1")

        # Sub-check: Alert band target (20 pts)
        band_reqs = ["drawasinfinite", "removebelowvalue", "rds_database.cpu.utilization", "90", "color", "red"]
        if _targets_contain(g1_targets, band_reqs):
            score += 20
            has_valid_band_anywhere = True
            feedback_parts.append(f"[+20] Valid drawAsInfinite alert band found in Graph 1")
        else:
            feedback_parts.append(f"[-] Missing/incomplete drawAsInfinite alert band in Graph 1")
    else:
        feedback_parts.append(f"[-] Graph '{GRAPH_1_TITLE}' not found")

    # ── Check 3: Graph 2 - Traffic Drop Correlation ───────────────────────────
    g2_match = _find_graph(graphs, GRAPH_2_TITLE)
    if g2_match:
        score += 5
        feedback_parts.append(f"[+5] Graph '{GRAPH_2_TITLE}' found")
        g2_title, g2_targets = g2_match

        # Sub-check: derivative load balancer requests (15 pts)
        if _targets_contain(g2_targets, ["derivative", "load_balancer.requests.count"]):
            score += 15
            feedback_parts.append(f"[+15] derivative(LB requests) found in Graph 2")
        else:
            feedback_parts.append(f"[-] Missing derivative(LB requests) in Graph 2")

        # Sub-check: Cross-metric alert band overlay (15 pts)
        band_reqs = ["drawasinfinite", "removebelowvalue", "rds_database.cpu.utilization", "90"]
        if _targets_contain(g2_targets, band_reqs):
            score += 15
            has_valid_band_anywhere = True
            feedback_parts.append(f"[+15] Cross-metric alert band applied to Graph 2")
        else:
            feedback_parts.append(f"[-] Missing cross-metric alert band in Graph 2")
    else:
        feedback_parts.append(f"[-] Graph '{GRAPH_2_TITLE}' not found")

    # ── Check 4: Graph 3 - DB CPU Velocity ────────────────────────────────────
    g3_match = _find_graph(graphs, GRAPH_3_TITLE)
    if g3_match:
        score += 5
        feedback_parts.append(f"[+5] Graph '{GRAPH_3_TITLE}' found")
        g3_title, g3_targets = g3_match

        # Sub-check: derivative(RDS CPU) (10 pts)
        if _targets_contain(g3_targets, ["derivative", "rds_database.cpu.utilization"]):
            score += 10
            feedback_parts.append(f"[+10] derivative(RDS CPU) found in Graph 3")
        else:
            feedback_parts.append(f"[-] Missing derivative(RDS CPU) in Graph 3")

        # Sub-check: threshold(0) with color blue (5 pts)
        if _targets_contain(g3_targets, ["threshold", "0", "color", "blue"]):
            score += 5
            feedback_parts.append(f"[+5] Colored threshold(0) baseline found in Graph 3")
        elif _targets_contain(g3_targets, ["threshold", "0"]):
            score += 2
            feedback_parts.append(f"[+2] threshold(0) found but missing blue color in Graph 3")
        else:
            feedback_parts.append(f"[-] Missing threshold(0) baseline in Graph 3")
    else:
        feedback_parts.append(f"[-] Graph '{GRAPH_3_TITLE}' not found")

    # ── Final Determination ───────────────────────────────────────────────────
    # The key mechanic being tested is the dynamic alert band. If the agent didn't 
    # successfully construct drawAsInfinite(removeBelowValue(...)) in at least one graph,
    # the task fundamentally fails.
    key_criteria_met = has_valid_band_anywhere
    
    if score >= 70 and not key_criteria_met:
        feedback_parts.append("\n[!] Failed: Required alert band logic (drawAsInfinite + removeBelowValue) was never successfully constructed.")
        passed = False
    else:
        passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }