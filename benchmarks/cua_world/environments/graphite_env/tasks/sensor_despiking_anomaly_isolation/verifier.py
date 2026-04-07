#!/usr/bin/env python3
"""
Verifier for sensor_despiking_anomaly_isolation task.

Scoring (100 pts total, pass >= 65):
  10 pts  Dashboard 'Sensor Quality Analysis' exists
  15 pts  Graph 1: 'Raw vs Median Filter' + metric + movingMedian target
   5 pts  Graph 2: Title 'Absolute Anomaly Score'
  15 pts  Graph 2: target incorporates diffSeries logic
  15 pts  Graph 2: target incorporates absolute wrapper
   5 pts  Graph 3: Title 'Severe Anomalies Only'
  20 pts  Graph 3: target incorporates removeBelowValue(..., 5)
  15 pts  Graph 3: Full complex nested syntax confirmed (all 4 functions present)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

DASHBOARD_NAME = "Sensor Quality Analysis"
RESULT_PATH = "/tmp/sensor_despiking_anomaly_isolation_result.json"

TARGET_METRIC = "web_traffic.speed_sensor_1"


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


def _normalize_target(t):
    """Normalize target string for robust parsing (lowercase, no spaces, unify quotes)."""
    return t.lower().replace(" ", "").replace('"', "'")


def _find_graph(graphs, expected_title):
    """Find a graph by exact title, then case-insensitive. Returns (title, targets) or None."""
    for title, targets in graphs:
        if title == expected_title:
            return title, targets
    for title, targets in graphs:
        if expected_title.lower() in title.lower():
            return title, targets
    return None


def verify_sensor_despiking_anomaly_isolation(trajectory, env_info, task_info):
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
        feedback_parts.append(f"JSON parse error: {dashboard_state['parse_error']}")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    graphs = _get_graphs(dashboard_state)

    # ── Graph 1: Raw vs Median Filter (15 pts) ──────────────────────────────
    g1 = _find_graph(graphs, "Raw vs Median Filter")
    if g1:
        g1_title, g1_targets = g1
        if g1_title == "Raw vs Median Filter":
            score += 5
            
        has_raw = False
        has_median = False
        for t in g1_targets:
            tn = _normalize_target(t)
            if "movingmedian" not in tn and TARGET_METRIC in tn:
                has_raw = True
            if "movingmedian" in tn and TARGET_METRIC in tn and ("15min" in tn or "15" in tn):
                has_median = True
                
        if has_raw:
            score += 5
        if has_median:
            score += 5
            
        if has_raw and has_median:
            feedback_parts.append("Graph 1 correctly targets raw metric and median filter")
        else:
            feedback_parts.append("Graph 1 missing required target(s)")
    else:
        feedback_parts.append("Graph 1 'Raw vs Median Filter' not found")

    # ── Graph 2: Absolute Anomaly Score (35 pts) ──────────────────────────────
    g2 = _find_graph(graphs, "Absolute Anomaly Score")
    if g2:
        g2_title, g2_targets = g2
        if g2_title == "Absolute Anomaly Score":
            score += 5
            
        has_diff = False
        has_abs = False
        
        for t in g2_targets:
            tn = _normalize_target(t)
            if "diffseries" in tn and TARGET_METRIC in tn and "movingmedian" in tn:
                has_diff = True
            if "absolute(" in tn:
                has_abs = True
                
        if has_diff:
            score += 15
            feedback_parts.append("Graph 2 correctly applies diffSeries logic")
        else:
            feedback_parts.append("Graph 2 missing diffSeries logic")
            
        if has_abs:
            score += 15
            feedback_parts.append("Graph 2 correctly applies absolute wrapper")
        else:
            feedback_parts.append("Graph 2 missing absolute wrapper")
    else:
        feedback_parts.append("Graph 2 'Absolute Anomaly Score' not found")

    # ── Graph 3: Severe Anomalies Only (40 pts) ───────────────────────────────
    g3 = _find_graph(graphs, "Severe Anomalies Only")
    if g3:
        g3_title, g3_targets = g3
        if g3_title == "Severe Anomalies Only":
            score += 5
            
        has_remove = False
        full_syntax = False
        
        for t in g3_targets:
            tn = _normalize_target(t)
            if "removebelowvalue(" in tn and ",5)" in tn:
                has_remove = True
            
            # Check for full nesting: removeBelowValue -> absolute -> diffSeries -> movingMedian -> metric
            if (has_remove and "absolute(" in tn and "diffseries(" in tn and 
                "movingmedian(" in tn and TARGET_METRIC in tn):
                full_syntax = True
                
        if has_remove:
            score += 20
            feedback_parts.append("Graph 3 correctly filters with removeBelowValue")
        else:
            feedback_parts.append("Graph 3 missing removeBelowValue threshold")
            
        if full_syntax:
            score += 15
            feedback_parts.append("Graph 3 full nested syntax verified")
    else:
        feedback_parts.append("Graph 3 'Severe Anomalies Only' not found")

    # Final evaluation
    passed = score >= 65

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }