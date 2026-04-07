#!/usr/bin/env python3
"""
Verifier for cdn_performance_divergence_analysis task.

Scoring (100 pts, pass >= 65):
  10 pts  Dashboard 'CDN Routing Divergence' exists
   5 pts  Dashboard has >= 3 graphs
   5 pts  Graph 'Absolute Speed Divergence' found
  20 pts  `absolute` correctly wraps `diffSeries` with both sensors
   5 pts  Graph 'S1/S2 Performance Ratio' found
  20 pts  `divideSeries` used with S1 as dividend and S2 as divisor
   5 pts  Graph 'Smoothed Lower Bound Floor' found
  20 pts  `movingAverage(..., 10)` correctly wraps `minSeries`
  10 pts  Exact aliases applied correctly across all three graphs
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

DASHBOARD_NAME = "CDN Routing Divergence"
RESULT_PATH = "/tmp/cdn_performance_divergence_analysis_result.json"

GRAPH_DIV_TITLE = "Absolute Speed Divergence"
GRAPH_RATIO_TITLE = "S1/S2 Performance Ratio"
GRAPH_LOWER_TITLE = "Smoothed Lower Bound Floor"

# Required exact aliases
ALIAS_DIV = "Absolute Gap"
ALIAS_RATIO = "S1 to S2 Ratio"
ALIAS_LOWER = "Smoothed Worst Speed"


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
    """Find a graph by exact title, then case-insensitive. Returns (title, targets) or (None, [])."""
    for title, targets in graphs:
        if title == expected_title:
            return title, targets
    for title, targets in graphs:
        if expected_title.lower() in title.lower():
            return title, targets
    return None, []


def verify_cdn_performance_divergence_analysis(trajectory, env_info, task_info):
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
        feedback_parts.append(f"Dashboard '{DASHBOARD_NAME}' not found.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}
    
    score += 10
    feedback_parts.append(f"Dashboard '{DASHBOARD_NAME}' exists")

    dashboard_state = dashboards[DASHBOARD_NAME]
    if "parse_error" in dashboard_state:
        feedback_parts.append(f"Dashboard JSON parse error: {dashboard_state['parse_error']}")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    graphs = _get_graphs(dashboard_state)

    # ── Check 2: Has >= 3 graphs (5 pts) ─────────────────────────────────────
    if len(graphs) >= 3:
        score += 5
        feedback_parts.append(f"Dashboard has {len(graphs)} graphs (>= 3)")
    else:
        feedback_parts.append(f"Dashboard only has {len(graphs)} graphs (expected 3)")

    # ── Parse specific graphs ────────────────────────────────────────────────
    title_div, targets_div = _find_graph(graphs, GRAPH_DIV_TITLE)
    title_ratio, targets_ratio = _find_graph(graphs, GRAPH_RATIO_TITLE)
    title_lower, targets_lower = _find_graph(graphs, GRAPH_LOWER_TITLE)

    aliases_correct = 0

    # ── Graph 1: Divergence ──────────────────────────────────────────────────
    if title_div:
        score += 5
        feedback_parts.append(f"Graph '{GRAPH_DIV_TITLE}' found")
        
        # Check logic: absolute() wrapping diffSeries(speed_sensor_1, speed_sensor_2)
        valid_logic = False
        has_alias = False
        
        for t in targets_div:
            # Check for absolute(diffSeries(...))
            if re.search(r"absolute\s*\(\s*diffSeries\s*\(", t):
                # Ensure both sensors are present inside the diffSeries part
                if "speed_sensor_1" in t and "speed_sensor_2" in t:
                    valid_logic = True
            
            # Check for alias
            if re.search(rf"alias\s*\(.*?,\s*['\"]{ALIAS_DIV}['\"]\s*\)", t):
                has_alias = True

        if valid_logic:
            score += 20
            feedback_parts.append("Divergence logic correct (absolute wraps diffSeries)")
        else:
            feedback_parts.append("Divergence logic incorrect or missing metrics")
            
        if has_alias:
            aliases_correct += 1
            
    else:
        feedback_parts.append(f"Graph '{GRAPH_DIV_TITLE}' missing")

    # ── Graph 2: Ratio ───────────────────────────────────────────────────────
    if title_ratio:
        score += 5
        feedback_parts.append(f"Graph '{GRAPH_RATIO_TITLE}' found")
        
        valid_logic = False
        has_alias = False
        
        for t in targets_ratio:
            # Check for divideSeries(S1, S2) ensuring order
            if re.search(r"divideSeries\s*\(\s*[^,]*speed_sensor_1[^,]*,[^,]*speed_sensor_2", t):
                valid_logic = True
                
            # Check for alias
            if re.search(rf"alias\s*\(.*?,\s*['\"]{ALIAS_RATIO}['\"]\s*\)", t):
                has_alias = True

        if valid_logic:
            score += 20
            feedback_parts.append("Ratio logic correct (divideSeries S1, S2 in order)")
        else:
            feedback_parts.append("Ratio logic incorrect (must divide S1 by S2)")
            
        if has_alias:
            aliases_correct += 1
            
    else:
        feedback_parts.append(f"Graph '{GRAPH_RATIO_TITLE}' missing")

    # ── Graph 3: Lower Bound Floor ───────────────────────────────────────────
    if title_lower:
        score += 5
        feedback_parts.append(f"Graph '{GRAPH_LOWER_TITLE}' found")
        
        valid_logic = False
        has_alias = False
        
        for t in targets_lower:
            # Check movingAverage(minSeries(...), 10)
            if re.search(r"movingAverage\s*\(\s*minSeries\s*\(.*?\)\s*,\s*['\"]?10['\"]?\s*\)", t):
                # Ensure it targets the speed sensors (wildcard or explicitly both)
                if "speed_sensor" in t:
                    valid_logic = True
                    
            # Check for alias
            if re.search(rf"alias\s*\(.*?,\s*['\"]{ALIAS_LOWER}['\"]\s*\)", t):
                has_alias = True

        if valid_logic:
            score += 20
            feedback_parts.append("Lower bound logic correct (movingAverage wraps minSeries with window 10)")
        else:
            feedback_parts.append("Lower bound logic incorrect")
            
        if has_alias:
            aliases_correct += 1
            
    else:
        feedback_parts.append(f"Graph '{GRAPH_LOWER_TITLE}' missing")

    # ── Aliases Evaluation (10 pts) ──────────────────────────────────────────
    if aliases_correct == 3:
        score += 10
        feedback_parts.append("All 3 exact aliases correctly applied")
    elif aliases_correct > 0:
        partial_points = aliases_correct * 3
        score += partial_points
        feedback_parts.append(f"{aliases_correct}/3 exact aliases applied")

    passed = score >= 65
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }