#!/usr/bin/env python3
"""
Verifier for statsd_application_telemetry task.

Scoring (100 pts, pass >= 65):
  30 pts  Live Telemetry Flowing: At least 2 non-null data points in graphite render API
  10 pts  Dashboard 'Payment Gateway' exists
  15 pts  Graph 'Live Throughput' correctly configured
  25 pts  Graph 'Success Ratio' correctly configured with asPercent
  20 pts  Graph 'System Impact' correctly configured with secondYAxis
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

DASHBOARD_NAME = "Payment Gateway"
RESULT_PATH = "/tmp/statsd_application_telemetry_result.json"

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

def verify_statsd_application_telemetry(trajectory, env_info, task_info):
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
            "feedback": f"Could not load result file: {e}"
        }

    dashboards = result.get("dashboards", {})
    render_data = result.get("render_data", [])
    
    # ── Check 1: Telemetry Data (30 pts) ──────────────────────────────────────
    # Verify the daemon was actually written and run by checking for live data points
    non_null_points = 0
    if render_data and isinstance(render_data, list) and len(render_data) > 0:
        datapoints = render_data[0].get("datapoints", [])
        for val, ts in datapoints:
            if val is not None:
                non_null_points += 1

    if non_null_points >= 2:
        score += 30
        feedback.append(f"[+30] Live Telemetry Flowing ({non_null_points} data points found)")
    elif non_null_points == 1:
        score += 10
        feedback.append(f"[+10] Live Telemetry: Only 1 data point found (daemon might have stopped too early)")
    else:
        feedback.append("[-] Live Telemetry: No data points found in Graphite (daemon not running or using incorrect metric path)")

    # ── Check 2: Dashboard Exists (10 pts) ────────────────────────────────────
    if DASHBOARD_NAME not in dashboards:
        feedback.append(f"[-] Dashboard '{DASHBOARD_NAME}' not found")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback)}
    
    score += 10
    feedback.append(f"[+10] Dashboard '{DASHBOARD_NAME}' exists")
    
    dashboard_state = dashboards[DASHBOARD_NAME]
    graphs = _get_graphs(dashboard_state)
    
    # ── Check 3: Live Throughput Graph (15 pts) ───────────────────────────────
    throughput_found = False
    for title, targets in graphs:
        if "Live Throughput".lower() in title.lower():
            targets_str = " ".join(targets).lower()
            if "stats.counters.payment.success.rate" in targets_str and "stats.counters.payment.failure.rate" in targets_str:
                throughput_found = True
                break
    if throughput_found:
        score += 15
        feedback.append("[+15] Graph 'Live Throughput' correctly configured")
    else:
        feedback.append("[-] Graph 'Live Throughput' missing or incorrect targets")

    # ── Check 4: Success Ratio Graph (25 pts) ─────────────────────────────────
    ratio_found = False
    for title, targets in graphs:
        if "Success Ratio".lower() in title.lower():
            targets_str = " ".join(targets).lower()
            if "aspercent" in targets_str and "sumseries" in targets_str and "stats.counters.payment.success.rate" in targets_str and "stats.counters.payment.*.rate" in targets_str:
                ratio_found = True
                break
    if ratio_found:
        score += 25
        feedback.append("[+25] Graph 'Success Ratio' correctly configured with asPercent")
    else:
        feedback.append("[-] Graph 'Success Ratio' missing or incorrect formula")
        
    # ── Check 5: System Impact Graph (20 pts) ─────────────────────────────────
    impact_found = False
    for title, targets in graphs:
        if "System Impact".lower() in title.lower():
            targets_str = " ".join(targets).lower()
            if "secondyaxis" in targets_str and "servers.ec2_instance_1.cpu.utilization" in targets_str and "sumseries" in targets_str and "stats.counters.payment.*.rate" in targets_str:
                impact_found = True
                break
    if impact_found:
        score += 20
        feedback.append("[+20] Graph 'System Impact' correctly configured with secondYAxis")
    else:
        feedback.append("[-] Graph 'System Impact' missing or incorrect formula")
        
    # Gating check: Must have live telemetry and basic graph config to pass
    passed = score >= 65 and non_null_points >= 2
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }