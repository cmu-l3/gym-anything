#!/usr/bin/env python3
"""
Verifier for sensor_imputation_and_cleaning task.

Scoring (100 pts, pass >= 60):
  10 pts  Dashboard 'Cleaned Telemetry' exists
  10 pts  Dashboard contains >= 4 graphs
  20 pts  Graph 1: 'Bridged Traffic Signal' correctly configures keepLastValue() on speed_sensor_1
  20 pts  Graph 2: 'Median-Smoothed Temperature' correctly configures movingMedian() on machine_temperature with window 5
  20 pts  Graph 3: 'Continuous Disk IO' correctly configures transformNull() on disk.write_bytes with default 0
  20 pts  Graph 4: 'Clean Fleet CPU' correctly configures aliasByNode() on ec2_instance CPU wildcard with index 1
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

DASHBOARD_NAME = "Cleaned Telemetry"
RESULT_PATH = "/tmp/sensor_imputation_and_cleaning_result.json"

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

def _check_target(targets, func, metric_keyword, arg=None):
    """Checks if any target contains the specified function, metric keyword, and optional argument."""
    for t in targets:
        t_lower = t.lower()
        t_clean = t.replace('"', '').replace("'", "").replace(" ", "")
        if func.lower() in t_lower and metric_keyword.lower() in t_lower:
            if arg is None or str(arg).lower() in t_clean.lower():
                return True
    return False

def _find_graph(graphs, expected_title):
    """Finds a graph by exact or partial title. Returns (title, targets)."""
    for title, targets in graphs:
        if title == expected_title:
            return title, targets
    for title, targets in graphs:
        if expected_title.lower() in title.lower():
            return title, targets
    return None, None

def verify_sensor_imputation_and_cleaning(trajectory, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "details": "copy_from_env unavailable"}
    
    score = 0
    details = []

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
            "details": f"Could not load result file: {e}",
        }

    dashboards = result.get("dashboards", {})

    # 2. Check Dashboard Existence
    if DASHBOARD_NAME not in dashboards:
        return {
            "passed": False,
            "score": 0,
            "details": (
                f"Dashboard '{DASHBOARD_NAME}' not found. "
                f"Dashboards present: {list(dashboards.keys())}"
            ),
        }
    score += 10
    details.append(f"[+10] Dashboard '{DASHBOARD_NAME}' exists")

    dashboard_state = dashboards[DASHBOARD_NAME]
    if "parse_error" in dashboard_state:
        return {
            "passed": False,
            "score": score,
            "details": f"Dashboard JSON parse error: {dashboard_state['parse_error']}",
        }

    graphs = _get_graphs(dashboard_state)

    # 3. Check Graph Count
    if len(graphs) >= 4:
        score += 10
        details.append(f"[+10] Dashboard contains {len(graphs)} graphs (>= 4)")
    else:
        details.append(f"[-] Expected >= 4 graphs, found {len(graphs)}")

    # 4. Verify Graph 1: Bridged Traffic Signal
    title, targets = _find_graph(graphs, "Bridged Traffic Signal")
    if targets:
        if _check_target(targets, "keepLastValue", "speed_sensor_1"):
            score += 20
            details.append("[+20] Bridged Traffic Signal: keepLastValue() correctly configured")
        else:
            details.append("[-] Bridged Traffic Signal missing keepLastValue() or correct metric")
    else:
        # Fallback metric scan across all graphs
        found = False
        for _, tgts in graphs:
            if _check_target(tgts, "keepLastValue", "speed_sensor_1"):
                score += 20
                details.append("[+20] keepLastValue() found in an un-titled graph")
                found = True
                break
        if not found:
            details.append("[-] keepLastValue(servers.web_traffic.speed_sensor_1) not found")

    # 5. Verify Graph 2: Median-Smoothed Temperature
    title, targets = _find_graph(graphs, "Median-Smoothed Temperature")
    if targets:
        if _check_target(targets, "movingMedian", "machine_temperature", "5"):
            score += 20
            details.append("[+20] Median-Smoothed Temperature: movingMedian() with window 5 correctly configured")
        else:
            details.append("[-] Median-Smoothed Temperature missing movingMedian() or window 5")
    else:
        found = False
        for _, tgts in graphs:
            if _check_target(tgts, "movingMedian", "machine_temperature", "5"):
                score += 20
                details.append("[+20] movingMedian() with window 5 found in an un-titled graph")
                found = True
                break
        if not found:
            details.append("[-] movingMedian(servers.datacenter.machine_temperature, 5) not found")

    # 6. Verify Graph 3: Continuous Disk IO
    title, targets = _find_graph(graphs, "Continuous Disk IO")
    if targets:
        if _check_target(targets, "transformNull", "write_bytes", "0"):
            score += 20
            details.append("[+20] Continuous Disk IO: transformNull() with default 0 correctly configured")
        else:
            details.append("[-] Continuous Disk IO missing transformNull() or default 0")
    else:
        found = False
        for _, tgts in graphs:
            if _check_target(tgts, "transformNull", "write_bytes", "0"):
                score += 20
                details.append("[+20] transformNull() with default 0 found in an un-titled graph")
                found = True
                break
        if not found:
            details.append("[-] transformNull(servers.ec2_instance_1.disk.write_bytes, 0) not found")

    # 7. Verify Graph 4: Clean Fleet CPU
    title, targets = _find_graph(graphs, "Clean Fleet CPU")
    if targets:
        # Check wildcard metric "ec2_instance_*.cpu.*" or similar plus aliasByNode
        if _check_target(targets, "aliasByNode", "ec2_instance", "1"):
            score += 20
            details.append("[+20] Clean Fleet CPU: aliasByNode() correctly configured with index 1")
        else:
            details.append("[-] Clean Fleet CPU missing aliasByNode() or correct index/metric")
    else:
        found = False
        for _, tgts in graphs:
            if _check_target(tgts, "aliasByNode", "ec2_instance", "1"):
                score += 20
                details.append("[+20] aliasByNode() with index 1 found in an un-titled graph")
                found = True
                break
        if not found:
            details.append("[-] aliasByNode(..., 1) not found")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(details)
    }