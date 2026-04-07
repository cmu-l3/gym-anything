#!/usr/bin/env python3
"""
Verifier for storage_thrashing_index_dashboard task.

Scoring (100 pts, pass >= 60):
  10 pts  Dashboard 'Storage Thrashing Analysis' exists
  10 pts  Dashboard has exactly 3 graphs (or at least 3)
  15 pts  Graph 1 Correctness: Contains both raw CPU and scaled disk write metrics
  25 pts  Graph 2 Correctness: correctly uses divideSeries(CPU, scale(...))
  25 pts  Graph 3 Correctness: correctly wraps Graph 2 formula in movingMedian(..., 12)
  15 pts  All 3 graph titles exactly match the expected strings

Robustly parses target AST logic using Regex to avoid strict whitespace/formatting failures.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

DASHBOARD_NAME = "Storage Thrashing Analysis"
RESULT_PATH = "/tmp/storage_thrashing_index_dashboard_result.json"

EXPECTED_TITLES = [
    "Compute vs Storage Throughput",
    "Thrashing Index",
    "Smoothed Thrashing Trend"
]

# Patterns for target validation
CPU_METRIC = r"servers\.ec2_instance_1\.cpu\.utilization"
DISK_METRIC = r"servers\.ec2_instance_1\.disk\.write_bytes"

# Matches scale(..., 0.000001) allowing optional quotes and spacing
SCALE_PATTERN = r"scale\s*\(\s*.*?" + DISK_METRIC + r".*?\s*,\s*['\"]?0\.000001['\"]?\s*\)"

# Matches divideSeries(CPU, scale)
DIVIDE_PATTERN = r"divideSeries\s*\(\s*.*?" + CPU_METRIC + r".*?\s*,\s*" + SCALE_PATTERN + r"\s*\)"

# Matches movingMedian(divideSeries(CPU, scale), 12)
MEDIAN_PATTERN = r"movingMedian\s*\(\s*" + DIVIDE_PATTERN + r"\s*,\s*['\"]?12['\"]?\s*\)"


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


def verify_storage_thrashing_index_dashboard(trajectory, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    score = 0
    feedback_parts = []

    # 1. Load exported dashboard data
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

    # 2. Check for Dashboard Name
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
        return {"passed": False, "score": score, "feedback": f"Dashboard JSON parse error: {dashboard_state['parse_error']}"}

    graphs = _get_graphs(dashboard_state)

    # 3. Check graph count
    if len(graphs) >= 3:
        score += 10
        feedback_parts.append(f"[+10] Dashboard has {len(graphs)} graphs")
    else:
        feedback_parts.append(f"[-] Expected >= 3 graphs, found {len(graphs)}")

    # Graph target mapping logic
    # We will evaluate titles and patterns together to score robustly
    exact_titles_found = 0
    graph1_correct = False
    graph2_correct = False
    graph3_correct = False

    for title, targets in graphs:
        if title in EXPECTED_TITLES:
            exact_titles_found += 1
        
        target_string = " | ".join(targets)
        
        # Test Graph 1 rules: CPU metric and scale() metric exist as separate logical elements or within the graph
        has_cpu = re.search(CPU_METRIC, target_string)
        has_scale = re.search(SCALE_PATTERN, target_string)
        
        # Test Graph 2 rules: divideSeries(CPU, scale(Disk, factor))
        has_divide = re.search(DIVIDE_PATTERN, target_string)
        
        # Test Graph 3 rules: movingMedian(divideSeries(...), 12)
        has_median = re.search(MEDIAN_PATTERN, target_string)
        
        # Assign logic based on most advanced match
        if has_median and "Smoothed" in title:
            graph3_correct = True
        elif has_median: # Fallback if title is wrong
            graph3_correct = True
            
        elif has_divide and "Index" in title:
            graph2_correct = True
        elif has_divide: # Fallback if title is wrong
            graph2_correct = True
            
        elif has_cpu and has_scale and "Compute" in title:
            # ensure it's not nested inside a divide function
            if not has_divide:
                graph1_correct = True
        elif has_cpu and has_scale and not has_divide:
            graph1_correct = True

    # Assign Scores
    if graph1_correct:
        score += 15
        feedback_parts.append("[+15] Graph 1 contains CPU and scaled Disk targets")
    else:
        feedback_parts.append("[-] Graph 1 missing or incorrectly formatted")

    if graph2_correct:
        score += 25
        feedback_parts.append("[+25] Graph 2 correctly uses divideSeries(CPU, scale(...))")
    else:
        feedback_parts.append("[-] Graph 2 divideSeries composition is missing or incorrect")

    if graph3_correct:
        score += 25
        feedback_parts.append("[+25] Graph 3 correctly wraps Graph 2 formula in movingMedian(..., 12)")
    else:
        feedback_parts.append("[-] Graph 3 movingMedian composition is missing or incorrect")

    # Title match scoring
    if exact_titles_found == 3:
        score += 15
        feedback_parts.append("[+15] All 3 graph titles match exactly")
    else:
        feedback_parts.append(f"[-] Found {exact_titles_found}/3 exact graph titles")

    passed = score >= 70 and graph3_correct

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }