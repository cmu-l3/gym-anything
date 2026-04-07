#!/usr/bin/env python3
"""
Verifier for thermal_efficiency_ratio_monitoring task.

Scoring (100 pts, pass >= 65):
  10 pts  Dashboard 'HVAC Thermal Efficiency' exists
  10 pts  'Raw Thermal Ratio' graph exists
  15 pts  Correct Ratio Logic (contains divideSeries with machine_temperature and averageSeries)
  10 pts  'Smoothed Alerting Signal' graph exists
  15 pts  Moving Median applied (window 12)
  15 pts  Static Threshold configured (3.0)
  10 pts  'Temperature vs CPU Overlay' graph exists
  15 pts  Second Y-Axis configured on CPU target
"""

import json
import os
import tempfile
import re

DASHBOARD_NAME = "HVAC Thermal Efficiency"
RESULT_PATH = "/tmp/thermal_efficiency_ratio_monitoring_result.json"

GRAPH_RAW = "Raw Thermal Ratio"
GRAPH_SMOOTHED = "Smoothed Alerting Signal"
GRAPH_OVERLAY = "Temperature vs CPU Overlay"

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
    """Find graph by exact title, then case-insensitive. Returns (title, targets)."""
    for title, targets in graphs:
        if title == expected_title:
            return title, targets
    for title, targets in graphs:
        if expected_title.lower() in title.lower():
            return title, targets
    return None, None

def _has_ratio_logic(targets):
    """Check if any target uses divideSeries with machine_temperature and averageSeries."""
    for t in targets:
        tl = t.lower().replace(" ", "")
        if "divideseries" in tl and "machine_temperature" in tl and "averageseries" in tl:
            return True
    return False

def verify_thermal_efficiency_ratio_monitoring(trajectory, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}
    
    score = 0
    feedback_parts = []
    has_valid_ratio_logic = False
    
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
        # Check case-insensitive
        found_dash = None
        for d_name in dashboards:
            if d_name.lower() == DASHBOARD_NAME.lower():
                found_dash = d_name
                break
        if not found_dash:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Dashboard '{DASHBOARD_NAME}' not found. Present: {list(dashboards.keys())}"
            }
        dashboard_state = dashboards[found_dash]
        score += 10
        feedback_parts.append(f"Dashboard '{DASHBOARD_NAME}' exists (case-insensitive match)")
    else:
        dashboard_state = dashboards[DASHBOARD_NAME]
        score += 10
        feedback_parts.append(f"Dashboard '{DASHBOARD_NAME}' exists")

    if "parse_error" in dashboard_state:
        return {
            "passed": False,
            "score": score,
            "feedback": f"Dashboard JSON parse error: {dashboard_state['parse_error']}"
        }

    graphs = _get_graphs(dashboard_state)

    # ── Check 2: Raw Thermal Ratio Graph (10 pts + 15 pts) ────────────────────
    title_raw, targets_raw = _find_graph(graphs, GRAPH_RAW)
    if targets_raw is not None:
        score += 10
        feedback_parts.append(f"Graph '{GRAPH_RAW}' found")
        if _has_ratio_logic(targets_raw):
            score += 15
            has_valid_ratio_logic = True
            feedback_parts.append("Correct divideSeries ratio logic applied")
        else:
            feedback_parts.append("Ratio logic missing or incorrect (needs divideSeries, machine_temperature, and averageSeries)")
    else:
        feedback_parts.append(f"Graph '{GRAPH_RAW}' missing")

    # ── Check 3: Smoothed Alerting Signal Graph (10 pts + 15 pts + 15 pts) ────
    title_smoothed, targets_smoothed = _find_graph(graphs, GRAPH_SMOOTHED)
    if targets_smoothed is not None:
        score += 10
        feedback_parts.append(f"Graph '{GRAPH_SMOOTHED}' found")
        
        has_moving_median = False
        has_threshold = False
        
        for t in targets_smoothed:
            tl = t.lower().replace(" ", "")
            # Check for moving median with window 12
            if "movingmedian" in tl and ",12)" in tl:
                has_moving_median = True
            # Check for threshold of 3.0 or 3
            if re.search(r"threshold\([^,]*3(\.0)?,", tl) or re.search(r"threshold\(3(\.0)?\)", tl):
                has_threshold = True
                
            # If agent didn't successfully do ratio logic in graph 1, maybe they did it here
            if "divideseries" in tl and "machine_temperature" in tl:
                has_valid_ratio_logic = True

        if has_moving_median:
            score += 15
            feedback_parts.append("Moving median filter (12) applied")
        else:
            feedback_parts.append("Moving median filter with window 12 missing")
            
        if has_threshold:
            score += 15
            feedback_parts.append("Critical threshold line (3.0) configured")
        else:
            feedback_parts.append("Critical threshold line missing")
    else:
        feedback_parts.append(f"Graph '{GRAPH_SMOOTHED}' missing")

    # ── Check 4: Temperature vs CPU Overlay Graph (10 pts + 15 pts) ───────────
    title_overlay, targets_overlay = _find_graph(graphs, GRAPH_OVERLAY)
    if targets_overlay is not None:
        score += 10
        feedback_parts.append(f"Graph '{GRAPH_OVERLAY}' found")
        
        has_second_yaxis = False
        for t in targets_overlay:
            tl = t.lower()
            if "secondyaxis" in tl and ("cpu" in tl or "averageseries" in tl):
                has_second_yaxis = True
                break
                
        if has_second_yaxis:
            score += 15
            feedback_parts.append("Second Y-Axis configured on CPU target")
        else:
            feedback_parts.append("Second Y-Axis missing on CPU target")
    else:
        feedback_parts.append(f"Graph '{GRAPH_OVERLAY}' missing")

    # ── Final Evaluation ──────────────────────────────────────────────────────
    passed = score >= 65 and has_valid_ratio_logic
    
    if not has_valid_ratio_logic:
        feedback_parts.append("CRITICAL FAILURE: No graph successfully implemented the divideSeries(temp, avg(cpu)) logic.")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }