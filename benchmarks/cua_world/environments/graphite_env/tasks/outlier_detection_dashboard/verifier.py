#!/usr/bin/env python3
"""
Verifier for outlier_detection_dashboard task.

Scoring (100 pts, pass >= 60):
  10 pts  Dashboard 'Outlier Detection' exists
  10 pts  Dashboard has >= 3 graphs
  10 pts  'Most Deviant Metrics' graph found
  15 pts  mostDeviant function present in target
   5 pts  mostDeviant parameter is 3
   5 pts  aliasByNode wrapping mostDeviant with parameter 1
  10 pts  'High Utilization Filter' graph found
  15 pts  currentAbove function with threshold 15
  10 pts  'Fleet CPU Envelope' graph found
   5 pts  maxSeries target present
   5 pts  minSeries target present
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

DASHBOARD_NAME = "Outlier Detection"
RESULT_PATH = "/tmp/outlier_detection_dashboard_result.json"

GRAPH_DEVIANT = "Most Deviant Metrics"
GRAPH_FILTER = "High Utilization Filter"
GRAPH_ENVELOPE = "Fleet CPU Envelope"


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


def _find_graph_exact_or_partial(graphs, expected_title):
    """Find a graph by exact title, then case-insensitive. Returns (title, targets) or None."""
    for title, targets in graphs:
        if title == expected_title:
            return title, targets
    for title, targets in graphs:
        if expected_title.lower() in title.lower():
            return title, targets
    return None


def _has_target_with(targets, required_substrings):
    """Check if any single target string contains ALL the required substrings."""
    for t in targets:
        tl = t.lower()
        if all(sub.lower() in tl for sub in required_substrings):
            return True
    return False


def verify_outlier_detection_dashboard(trajectory, env_info, task_info):
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

    # 3. Check Dashboard has >= 3 graphs (10 pts)
    if len(graphs) >= 3:
        score += 10
        feedback_parts.append(f"Dashboard has {len(graphs)} graphs (>= 3)")
    else:
        feedback_parts.append(f"Dashboard only has {len(graphs)} graphs (expected 3)")

    # 4. Check "Most Deviant Metrics" (10 + 15 + 5 + 5 pts)
    g1_match = _find_graph_exact_or_partial(graphs, GRAPH_DEVIANT)
    if g1_match:
        score += 10
        g1_title, g1_targets = g1_match
        feedback_parts.append(f"Graph '{g1_title}' found")
        
        # Check mostDeviant
        if _has_target_with(g1_targets, ["mostdeviant"]):
            score += 15
            feedback_parts.append("mostDeviant function used")
            
            # Check parameter 3
            if _has_target_with(g1_targets, ["mostdeviant", "3"]):
                score += 5
                feedback_parts.append("mostDeviant parameter 3 applied")
        else:
            feedback_parts.append("mostDeviant function missing")

        # Check aliasByNode
        if _has_target_with(g1_targets, ["aliasbynode"]):
            if _has_target_with(g1_targets, ["aliasbynode", "1"]):
                score += 5
                feedback_parts.append("aliasByNode(..., 1) applied")
    else:
        feedback_parts.append(f"Graph '{GRAPH_DEVIANT}' not found")

    # 5. Check "High Utilization Filter" (10 + 15 pts)
    g2_match = _find_graph_exact_or_partial(graphs, GRAPH_FILTER)
    if g2_match:
        score += 10
        g2_title, g2_targets = g2_match
        feedback_parts.append(f"Graph '{g2_title}' found")
        
        if _has_target_with(g2_targets, ["currentabove", "15"]):
            score += 15
            feedback_parts.append("currentAbove(..., 15) applied")
        elif _has_target_with(g2_targets, ["currentabove"]):
            feedback_parts.append("currentAbove used, but missing threshold 15")
        else:
            feedback_parts.append("currentAbove function missing")
    else:
        feedback_parts.append(f"Graph '{GRAPH_FILTER}' not found")

    # 6. Check "Fleet CPU Envelope" (10 + 5 + 5 pts)
    g3_match = _find_graph_exact_or_partial(graphs, GRAPH_ENVELOPE)
    if g3_match:
        score += 10
        g3_title, g3_targets = g3_match
        feedback_parts.append(f"Graph '{g3_title}' found")
        
        # We need to check if there are separate maxSeries and minSeries targets, 
        # or if they are in the same graph targets list.
        has_max = _has_target_with(g3_targets, ["maxseries", "ec2_instance"]) or _has_target_with(g3_targets, ["maxseries", "cpu"])
        has_min = _has_target_with(g3_targets, ["minseries", "ec2_instance"]) or _has_target_with(g3_targets, ["minseries", "cpu"])
        
        if has_max:
            score += 5
            feedback_parts.append("maxSeries target found")
        if has_min:
            score += 5
            feedback_parts.append("minSeries target found")
    else:
        feedback_parts.append(f"Graph '{GRAPH_ENVELOPE}' not found")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }