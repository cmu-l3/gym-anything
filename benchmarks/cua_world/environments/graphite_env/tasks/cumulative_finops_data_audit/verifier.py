#!/usr/bin/env python3
"""
Verifier for cumulative_finops_data_audit task.

Scoring (100 pts, pass >= 70):
  10 pts: Dashboard 'Cumulative FinOps Audit' exists
  Graph 1: Total Network Ingress (25 pts)
    5 pts: Title exists
    5 pts: Metric 'ec2_instance_1.network.bytes_in' present
    5 pts: integral() applied
    5 pts: scale() with 0.000001 (or 1e-6) applied
    5 pts: alias() with 'Network MB' applied
  Graph 2: Total Disk Writes (25 pts)
    5 pts: Title exists
    5 pts: Metric 'ec2_instance_1.disk.write_bytes' present
    5 pts: integral() applied
    5 pts: scale() with 0.000001 (or 1e-6) applied
    5 pts: alias() with 'Disk MB' applied
  Graph 3: Combined I/O Volume (40 pts)
    5 pts: Title exists
    15 pts: sumSeries() applied combining both metrics
    5 pts: integral() applied
    10 pts: scale() with 0.000001 (or 1e-6) applied
    5 pts: alias() with 'Total I/O MB' applied
"""

import json
import os
import tempfile
import re

DASHBOARD_NAME = "Cumulative FinOps Audit"
RESULT_PATH = "/tmp/cumulative_finops_data_audit_result.json"

NETWORK_METRIC = "ec2_instance_1.network.bytes_in"
DISK_METRIC = "ec2_instance_1.disk.write_bytes"

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
    """Find a graph by exact title, then case-insensitive. Returns (title, targets) or None."""
    for title, targets in graphs:
        if title == expected_title:
            return title, targets
    for title, targets in graphs:
        if expected_title.lower() in title.lower():
            return title, targets
    return None

def _has_scale_factor(target_str):
    """Check if target string contains scale factor 0.000001 or 1e-06/1e-6."""
    t_lower = target_str.lower()
    return "0.000001" in t_lower or "1e-06" in t_lower or "1e-6" in t_lower

def verify_cumulative_finops_data_audit(trajectory, env_info, task_info):
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

    # ── Check Dashboard exists (10 pts) ───────────────────────────────────────
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

    # ── Graph 1: Total Network Ingress (25 pts max) ───────────────────────────
    g1 = _find_graph(graphs, "Total Network Ingress")
    if g1:
        score += 5
        feedback_parts.append("[+5] Graph 'Total Network Ingress' found")
        _, targets = g1
        t_str = " ".join(targets).lower()
        
        if NETWORK_METRIC.lower() in t_str:
            score += 5
            feedback_parts.append("[+5] Network metric present")
        else:
            feedback_parts.append("[-] Network metric missing")
            
        if "integral(" in t_str:
            score += 5
            feedback_parts.append("[+5] integral() applied")
        else:
            feedback_parts.append("[-] integral() missing")
            
        if "scale(" in t_str and _has_scale_factor(t_str):
            score += 5
            feedback_parts.append("[+5] scale(0.000001) applied")
        else:
            feedback_parts.append("[-] scale(0.000001) missing or incorrect")
            
        if "alias(" in t_str and "network mb" in t_str:
            score += 5
            feedback_parts.append("[+5] alias('Network MB') applied")
        else:
            feedback_parts.append("[-] alias('Network MB') missing or incorrect")
    else:
        feedback_parts.append("[-] Graph 'Total Network Ingress' missing")

    # ── Graph 2: Total Disk Writes (25 pts max) ───────────────────────────────
    g2 = _find_graph(graphs, "Total Disk Writes")
    if g2:
        score += 5
        feedback_parts.append("[+5] Graph 'Total Disk Writes' found")
        _, targets = g2
        t_str = " ".join(targets).lower()
        
        if DISK_METRIC.lower() in t_str:
            score += 5
            feedback_parts.append("[+5] Disk metric present")
        else:
            feedback_parts.append("[-] Disk metric missing")
            
        if "integral(" in t_str:
            score += 5
            feedback_parts.append("[+5] integral() applied")
        else:
            feedback_parts.append("[-] integral() missing")
            
        if "scale(" in t_str and _has_scale_factor(t_str):
            score += 5
            feedback_parts.append("[+5] scale(0.000001) applied")
        else:
            feedback_parts.append("[-] scale(0.000001) missing or incorrect")
            
        if "alias(" in t_str and "disk mb" in t_str:
            score += 5
            feedback_parts.append("[+5] alias('Disk MB') applied")
        else:
            feedback_parts.append("[-] alias('Disk MB') missing or incorrect")
    else:
        feedback_parts.append("[-] Graph 'Total Disk Writes' missing")

    # ── Graph 3: Combined I/O Volume (40 pts max) ─────────────────────────────
    g3 = _find_graph(graphs, "Combined I/O Volume")
    if g3:
        score += 5
        feedback_parts.append("[+5] Graph 'Combined I/O Volume' found")
        _, targets = g3
        t_str = " ".join(targets).lower()
        
        has_net = NETWORK_METRIC.lower() in t_str
        has_disk = DISK_METRIC.lower() in t_str
        
        if has_net and has_disk and "sumseries(" in t_str:
            score += 15
            feedback_parts.append("[+15] sumSeries() correctly combines both metrics")
        else:
            feedback_parts.append("[-] sumSeries() with both metrics missing")
            
        if "integral(" in t_str:
            score += 5
            feedback_parts.append("[+5] integral() applied")
        else:
            feedback_parts.append("[-] integral() missing")
            
        if "scale(" in t_str and _has_scale_factor(t_str):
            score += 10
            feedback_parts.append("[+10] scale(0.000001) applied")
        else:
            feedback_parts.append("[-] scale(0.000001) missing or incorrect")
            
        if "alias(" in t_str and "total i/o mb" in t_str:
            score += 5
            feedback_parts.append("[+5] alias('Total I/O MB') applied")
        else:
            feedback_parts.append("[-] alias('Total I/O MB') missing or incorrect")
    else:
        feedback_parts.append("[-] Graph 'Combined I/O Volume' missing")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }