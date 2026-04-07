#!/usr/bin/env python3
"""
Verifier for network_route_divergence_monitoring task.

Scoring (100 pts, pass >= 65):
  10 pts  Dashboard 'CDN Route Diagnostics' exists
  10 pts  Dashboard has >= 3 graphs
  15 pts  Graph 'Edge Speed Comparison' contains speed_sensor_1 and speed_sensor_2
  20 pts  Graph 'Speed Divergence Delta' uses diffSeries() on both sensors
  15 pts  Graph 'Speed Divergence Delta' uses absolute() wrapping the diff
  15 pts  Graph 'Aggregate Route Mean' uses averageSeries()
  15 pts  All 3 graph titles perfectly match specifications
"""

import json
import os
import tempfile

DASHBOARD_NAME = "CDN Route Diagnostics"
RESULT_PATH = "/tmp/network_route_divergence_monitoring_result.json"

EXPECTED_TITLES = [
    "Edge Speed Comparison",
    "Speed Divergence Delta",
    "Aggregate Route Mean"
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


def _targets_contain_all(targets, substrings):
    """Check if ANY single target contains ALL of the substrings (case-insensitive)."""
    for t in targets:
        tl = t.lower()
        if all(sub.lower() in tl for sub in substrings):
            return True
    return False


def _any_target_contains_all(targets, substrings_sets):
    """Check if ALL substring requirements are met across ANY targets."""
    for required_subs in substrings_sets:
        found = False
        for t in targets:
            tl = t.lower()
            if all(sub.lower() in tl for sub in required_subs):
                found = True
                break
        if not found:
            return False
    return True


def verify_network_route_divergence_monitoring(trajectory, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}
    
    score = 0
    feedback = []

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
                f"Present: {list(dashboards.keys())}"
            ),
        }
    score += 10
    feedback.append(f"[+10] Dashboard '{DASHBOARD_NAME}' exists")

    dashboard_state = dashboards[DASHBOARD_NAME]
    if "parse_error" in dashboard_state:
        return {
            "passed": False,
            "score": score,
            "feedback": f"Dashboard JSON parse error: {dashboard_state['parse_error']}",
        }

    graphs = _get_graphs(dashboard_state)

    # ── Check 2: Has >= 3 graphs (10 pts) ─────────────────────────────────────
    if len(graphs) >= 3:
        score += 10
        feedback.append(f"[+10] Dashboard contains {len(graphs)} graphs (>= 3)")
    else:
        feedback.append(f"[-] Expected >= 3 graphs, found {len(graphs)}")
        if not graphs:
            return {"passed": False, "score": score, "feedback": "\n".join(feedback)}

    # Track exact title matches
    exact_titles_found = 0

    # ── Graph A: Edge Speed Comparison (15 pts) ───────────────────────────────
    edge_graph = None
    for title, targets in graphs:
        if title == "Edge Speed Comparison":
            edge_graph = targets
            exact_titles_found += 1
            break
    if not edge_graph:
        for title, targets in graphs:
            if "edge speed comparison" in title.lower():
                edge_graph = targets
                break
    if not edge_graph:
        # Fallback to function matching
        for title, targets in graphs:
            if _any_target_contains_all(targets, [["speed_sensor_1"], ["speed_sensor_2"]]) and not _targets_contain_all(targets, ["diffseries"]):
                edge_graph = targets
                feedback.append(f"  (Using graph '{title}' for Edge Speed checks)")
                break

    if edge_graph:
        if _any_target_contains_all(edge_graph, [["speed_sensor_1"], ["speed_sensor_2"]]):
            score += 15
            feedback.append("[+15] 'Edge Speed Comparison' contains speed_sensor_1 and speed_sensor_2")
        else:
            feedback.append("[-] 'Edge Speed Comparison' missing one or both speed sensor metrics")
    else:
        feedback.append("[-] Graph 'Edge Speed Comparison' not found")

    # ── Graph B: Speed Divergence Delta (20 pts diffSeries, 15 pts absolute) ──
    divergence_graph = None
    for title, targets in graphs:
        if title == "Speed Divergence Delta":
            divergence_graph = targets
            exact_titles_found += 1
            break
    if not divergence_graph:
        for title, targets in graphs:
            if "divergence delta" in title.lower():
                divergence_graph = targets
                break
    if not divergence_graph:
        # Fallback to function matching
        for title, targets in graphs:
            if _targets_contain_all(targets, ["diffseries", "speed_sensor"]):
                divergence_graph = targets
                feedback.append(f"  (Using graph '{title}' for Divergence checks)")
                break

    if divergence_graph:
        has_diff = _targets_contain_all(divergence_graph, ["diffseries", "speed_sensor_1", "speed_sensor_2"])
        has_abs = _targets_contain_all(divergence_graph, ["absolute", "diffseries"])
        
        if has_diff:
            score += 20
            feedback.append("[+20] 'Speed Divergence Delta' uses diffSeries() on both sensors")
        else:
            feedback.append("[-] 'Speed Divergence Delta' missing diffSeries() with both sensors")
            
        if has_abs and has_diff:
            score += 15
            feedback.append("[+15] 'Speed Divergence Delta' correctly uses absolute() to get magnitude")
        elif has_abs:
            feedback.append("[-] 'Speed Divergence Delta' uses absolute() but missing correct diffSeries usage")
        else:
            feedback.append("[-] 'Speed Divergence Delta' missing absolute() wrapper")
    else:
        feedback.append("[-] Graph 'Speed Divergence Delta' not found")

    # ── Graph C: Aggregate Route Mean (15 pts) ────────────────────────────────
    mean_graph = None
    for title, targets in graphs:
        if title == "Aggregate Route Mean":
            mean_graph = targets
            exact_titles_found += 1
            break
    if not mean_graph:
        for title, targets in graphs:
            if "aggregate route mean" in title.lower() or "mean" in title.lower():
                mean_graph = targets
                break
    if not mean_graph:
        # Fallback to function matching
        for title, targets in graphs:
            if _targets_contain_all(targets, ["averageseries"]):
                mean_graph = targets
                feedback.append(f"  (Using graph '{title}' for Aggregate Mean checks)")
                break

    if mean_graph:
        if _targets_contain_all(mean_graph, ["averageseries", "speed_sensor"]):
            score += 15
            feedback.append("[+15] 'Aggregate Route Mean' uses averageSeries() on speed sensors")
        else:
            feedback.append("[-] 'Aggregate Route Mean' missing averageSeries() or speed_sensor target")
    else:
        feedback.append("[-] Graph 'Aggregate Route Mean' not found")

    # ── Check exact titles (15 pts) ───────────────────────────────────────────
    if exact_titles_found == 3:
        score += 15
        feedback.append("[+15] All 3 graph titles perfectly match specifications")
    else:
        feedback.append(f"[-] Only {exact_titles_found}/3 graph titles exactly matched specifications")

    passed = score >= 65 and divergence_graph is not None and mean_graph is not None
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }