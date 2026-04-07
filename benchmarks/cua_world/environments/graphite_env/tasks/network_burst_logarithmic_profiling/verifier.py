#!/usr/bin/env python3
"""
Verifier for network_burst_logarithmic_profiling task.

Scoring (100 pts total, passing threshold 60):
  10 pts  Dashboard "Network Burst Profiling" exists
   5 pts  Dashboard has >= 3 distinct graphs
  15 pts  Graph 1 ("Linear Baseline") contains correct raw metric
  20 pts  Graph 2 ("Logarithmic Intake") contains logarithm(metric, 10)
  20 pts  Graph 3 ("Transient Burst Isolation") contains base logic: diffSeries(metric, movingMedian(metric, 15))
  10 pts  Graph 3 contains filter logic: removeBelowValue(..., 0)
  20 pts  All 3 graph titles perfectly match expectations
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

DASHBOARD_NAME = "Network Burst Profiling"
RESULT_PATH = "/tmp/network_burst_logarithmic_profiling_result.json"
TARGET_METRIC = "servers.ec2_instance_1.network.bytes_in"

EXPECTED_TITLES = [
    "Linear Baseline",
    "Logarithmic Intake",
    "Transient Burst Isolation"
]

def _get_graphs(dashboard_state):
    """Extract list of (title, [targets]) from a dashboard state dict."""
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

def _clean_target(target):
    """Normalize target string by removing spaces and making lowercase."""
    return target.replace(" ", "").replace("\"", "'").lower()

def verify_network_burst_logarithmic_profiling(trajectory, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    score = 0
    feedback = []

    # 1. Load result file safely
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            tmp_path = tmp.name
        copy_from_env(RESULT_PATH, tmp_path)
        with open(tmp_path) as f:
            result = json.load(f)
        os.unlink(tmp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not load result file: {e}"}

    dashboards = result.get("dashboards", {})

    # 2. Check Dashboard exists
    if DASHBOARD_NAME not in dashboards:
        feedback.append(f"[-] Dashboard '{DASHBOARD_NAME}' not found.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}
    
    score += 10
    feedback.append(f"[+10] Dashboard '{DASHBOARD_NAME}' exists")
    
    dashboard_state = dashboards[DASHBOARD_NAME]
    if "parse_error" in dashboard_state:
        feedback.append(f"[-] Parse error in dashboard state: {dashboard_state['parse_error']}")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

    graphs = _get_graphs(dashboard_state)

    # 3. Check graph count
    if len(graphs) >= 3:
        score += 5
        feedback.append(f"[+5] Dashboard contains {len(graphs)} graphs (>= 3)")
    else:
        feedback.append(f"[-] Dashboard contains {len(graphs)} graphs (expected 3)")

    # Analyze individual graphs to match titles and target contents
    linear_found = False
    log_found = False
    diff_logic_found = False
    filter_logic_found = False
    titles_matched = 0

    metric_lower = TARGET_METRIC.lower()

    for title, targets in graphs:
        # Check title match
        for expected_title in EXPECTED_TITLES:
            if title == expected_title:
                titles_matched += 1

        # Check target content
        for raw_target in targets:
            clean_t = _clean_target(raw_target)

            # Linear Baseline check
            if metric_lower in clean_t and "logarithm" not in clean_t and "diffseries" not in clean_t:
                linear_found = True

            # Logarithmic Intake check
            if "logarithm" in clean_t and metric_lower in clean_t and ",10" in clean_t:
                log_found = True

            # Transient Burst Isolation check
            # Needs diffSeries(metric, movingMedian(metric, 15))
            if "diffseries" in clean_t and "movingmedian" in clean_t and metric_lower in clean_t and ",15" in clean_t:
                diff_logic_found = True
            
            # Filter check: removeBelowValue(..., 0)
            if "removebelowvalue" in clean_t and ",0" in clean_t:
                filter_logic_found = True

    # Scoring graph target logic
    if linear_found:
        score += 15
        feedback.append("[+15] Linear Baseline graph contains raw metric")
    else:
        feedback.append("[-] Raw metric target not found for Linear Baseline")

    if log_found:
        score += 20
        feedback.append("[+20] Logarithmic graph target contains logarithm(..., 10)")
    else:
        feedback.append("[-] Valid logarithmic target not found")

    if diff_logic_found:
        score += 20
        feedback.append("[+20] Burst isolation graph contains diffSeries and movingMedian logic")
    else:
        feedback.append("[-] diffSeries / movingMedian logic missing from target")

    if filter_logic_found:
        score += 10
        feedback.append("[+10] Burst isolation graph correctly filtered with removeBelowValue(..., 0)")
    else:
        feedback.append("[-] removeBelowValue(..., 0) filter missing from target")

    # Titles score
    if titles_matched >= 3:
        score += 20
        feedback.append("[+20] All 3 graph titles match exactly")
    elif titles_matched > 0:
        score += (titles_matched * 6)
        feedback.append(f"[+{titles_matched * 6}] {titles_matched}/3 graph titles match exactly")
    else:
        feedback.append("[-] No graph titles match expected exactly")

    key_criteria_met = (log_found and diff_logic_found)
    passed = (score >= 60) and key_criteria_met

    if passed:
        feedback.append("SUCCEEDED")
    else:
        feedback.append("FAILED (must score >= 60 and have Logarithmic and Burst targets configured)")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }