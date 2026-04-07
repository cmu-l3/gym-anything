#!/usr/bin/env python3
"""
Verifier for redundant_sensor_drift_calibration task.

Scoring (100 pts, pass >= 60):
  10 pts  Dashboard 'Sensor Calibration' exists
  10 pts  All three graph titles exactly correct
  15 pts  Graph 1: 'Raw Telemetry' contains both sensor_1 and sensor_2
  15 pts  Graph 2: Computes the difference using diffSeries()
  15 pts  Graph 2: Applies absolute() to the diffSeries
  15 pts  Graph 3: Uses integral() to compute cumulative drift
  20 pts  Graph 3: Correct mathematical nesting: integral(absolute(diffSeries(...)))
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

DASHBOARD_NAME = "Sensor Calibration"
RESULT_PATH = "/tmp/redundant_sensor_drift_calibration_result.json"

EXPECTED_TITLES = [
    "Raw Telemetry",
    "Instantaneous Drift",
    "Cumulative Drift Penalty"
]

SENSOR_1 = "servers.web_traffic.speed_sensor_1"
SENSOR_2 = "servers.web_traffic.speed_sensor_2"


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


def _find_graph_by_title(graphs, expected_title):
    """Find a graph by title (exact first, then case-insensitive substring)."""
    for title, targets in graphs:
        if title == expected_title:
            return title, targets
    for title, targets in graphs:
        if expected_title.lower() in title.lower():
            return title, targets
    return None, None


def verify_redundant_sensor_drift_calibration(trajectory, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    score = 0
    feedback_parts = []

    # 1. Load exported result
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

    # 2. Check if Dashboard exists
    if DASHBOARD_NAME not in dashboards:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Dashboard '{DASHBOARD_NAME}' not found. Present: {list(dashboards.keys())}"
        }
    
    score += 10
    feedback_parts.append(f"[+10] Dashboard '{DASHBOARD_NAME}' exists")
    dashboard_state = dashboards[DASHBOARD_NAME]

    if "parse_error" in dashboard_state:
        return {
            "passed": False,
            "score": score,
            "feedback": f"Dashboard JSON parse error: {dashboard_state['parse_error']}"
        }

    graphs = _get_graphs(dashboard_state)

    # 3. Verify Graph Titles
    matched_titles = 0
    for expected_title in EXPECTED_TITLES:
        title, _ = _find_graph_by_title(graphs, expected_title)
        if title == expected_title:
            matched_titles += 1
            
    if matched_titles == 3:
        score += 10
        feedback_parts.append("[+10] All 3 graph titles perfectly matched")
    else:
        feedback_parts.append(f"[-] Only matched {matched_titles}/3 exact graph titles")

    # Locate each graph by title (or fallback)
    raw_title, raw_targets = _find_graph_by_title(graphs, "Raw Telemetry")
    drift_title, drift_targets = _find_graph_by_title(graphs, "Instantaneous Drift")
    cum_title, cum_targets = _find_graph_by_title(graphs, "Cumulative Drift Penalty")

    # If titles completely missed, try assigning sequentially assuming they made 3 graphs
    if len(graphs) >= 3:
        if raw_targets is None: raw_targets = graphs[0][1]
        if drift_targets is None: drift_targets = graphs[1][1]
        if cum_targets is None: cum_targets = graphs[2][1]

    # Helper to check if both sensors are referenced
    def _has_both_sensors(targets):
        text = " ".join(targets).lower()
        return "speed_sensor_1" in text and "speed_sensor_2" in text

    # 4. Check Graph 1 (Raw Telemetry)
    if raw_targets is not None:
        if _has_both_sensors(raw_targets):
            score += 15
            feedback_parts.append("[+15] Graph 1 contains both raw sensor metrics")
        else:
            feedback_parts.append("[-] Graph 1 is missing one or both sensor metrics")
    else:
        feedback_parts.append("[-] Graph 1 not found")

    # 5. Check Graph 2 (Instantaneous Drift)
    if drift_targets is not None:
        drift_text = " ".join(drift_targets).lower()
        has_diff = "diffseries" in drift_text
        has_abs = "absolute" in drift_text
        
        if has_diff:
            score += 15
            feedback_parts.append("[+15] Graph 2 uses diffSeries()")
        else:
            feedback_parts.append("[-] Graph 2 is missing diffSeries()")
            
        if has_abs:
            score += 15
            feedback_parts.append("[+15] Graph 2 uses absolute()")
        else:
            feedback_parts.append("[-] Graph 2 is missing absolute()")
            
        if not _has_both_sensors(drift_targets):
            feedback_parts.append("[-] Warning: Graph 2 does not reference both sensors")
    else:
        feedback_parts.append("[-] Graph 2 not found")

    # 6. Check Graph 3 (Cumulative Drift Penalty)
    if cum_targets is not None:
        cum_text = " ".join(cum_targets).lower()
        has_integral = "integral" in cum_text
        
        if has_integral:
            score += 15
            feedback_parts.append("[+15] Graph 3 uses integral()")
        else:
            feedback_parts.append("[-] Graph 3 is missing integral()")

        # Verify exact mathematical nesting: integral(absolute(diffSeries(...)))
        # This regex looks for 'integral' followed by open paren, then 'absolute' followed by open paren, then 'diffseries'
        nesting_pattern = r"integral\s*\(\s*absolute\s*\(\s*diffseries\s*\("
        has_correct_nesting = bool(re.search(nesting_pattern, cum_text))
        
        if has_correct_nesting:
            score += 20
            feedback_parts.append("[+20] Graph 3 correctly nests integral(absolute(diffSeries(...)))")
        else:
            feedback_parts.append("[-] Graph 3 failed nesting check. Must be integral(absolute(diffSeries(...)))")
    else:
        feedback_parts.append("[-] Graph 3 not found")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }