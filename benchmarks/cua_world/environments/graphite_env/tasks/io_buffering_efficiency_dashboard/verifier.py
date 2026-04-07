#!/usr/bin/env python3
"""
Verifier for io_buffering_efficiency_dashboard task.

Scoring (100 pts, pass >= 60):
  10 pts  Dashboard 'I/O Buffering Efficiency' exists
  10 pts  Dashboard has >= 4 graphs
  20 pts  Graph 1: 'Cumulative Network Ingest' contains integral() wrapping network.bytes_in
  20 pts  Graph 2: 'Network Ingress Rate (Bits)' contains scale(..., 8) wrapping network.bytes_in
  20 pts  Graph 3: 'Write-to-Ingest Ratio' contains divideSeries() with correct argument ordering
  20 pts  Graph 4: 'Robust Disk I/O' contains movingMedian(..., 10) wrapping disk.write_bytes
"""

import json
import os
import re
import tempfile

DASHBOARD_NAME = "I/O Buffering Efficiency"
RESULT_PATH = "/tmp/io_buffering_efficiency_dashboard_result.json"

GRAPH_TITLES = {
    "integral": "Cumulative Network Ingest",
    "scale": "Network Ingress Rate (Bits)",
    "divide": "Write-to-Ingest Ratio",
    "median": "Robust Disk I/O"
}


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
    """Find a graph by exact title, then case-insensitive. Returns (title, targets) or (None, None)."""
    for title, targets in graphs:
        if title == expected_title:
            return title, targets
    for title, targets in graphs:
        if expected_title.lower() in title.lower():
            return title, targets
    return None, None


def verify_io_buffering_efficiency_dashboard(trajectory, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}
    
    score = 0
    feedback_parts = []

    # Load result file
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

    # Check 1: Dashboard exists (10 pts)
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

    # Check 2: Has >= 4 graphs (10 pts)
    if len(graphs) >= 4:
        score += 10
        feedback_parts.append(f"[+10] Dashboard contains {len(graphs)} graph(s) (>= 4)")
    else:
        feedback_parts.append(f"[-] Dashboard contains {len(graphs)} graph(s), expected >= 4")

    # Check Graph 1: Integral (20 pts)
    title1, targets1 = _find_graph_by_title(graphs, GRAPH_TITLES["integral"])
    if not targets1:
        # Fallback to function search
        for t_title, t_targets in graphs:
            if any("integral" in str(x).lower() for x in t_targets):
                targets1 = t_targets
                feedback_parts.append(f"  (Using graph '{t_title}' for Integral check)")
                break

    if targets1:
        t_str = " ".join(targets1).lower()
        if "integral(" in t_str and "network.bytes_in" in t_str:
            score += 20
            feedback_parts.append("[+20] integral(network.bytes_in) correctly configured")
        else:
            feedback_parts.append("[-] Integral graph missing 'integral(' or 'network.bytes_in'")
    else:
        feedback_parts.append(f"[-] Integral graph '{GRAPH_TITLES['integral']}' not found")

    # Check Graph 2: Scale (20 pts)
    title2, targets2 = _find_graph_by_title(graphs, GRAPH_TITLES["scale"])
    if not targets2:
        for t_title, t_targets in graphs:
            if any("scale" in str(x).lower() for x in t_targets):
                targets2 = t_targets
                feedback_parts.append(f"  (Using graph '{t_title}' for Scale check)")
                break
                
    if targets2:
        t_str = " ".join(targets2).lower()
        if "scale(" in t_str and "network.bytes_in" in t_str:
            # Check if scale factor 8 is present
            if re.search(r'scale\([^,]+,\s*[\'"]?8[\'"]?\)', t_str):
                score += 20
                feedback_parts.append("[+20] scale(network.bytes_in, 8) correctly configured")
            else:
                score += 10
                feedback_parts.append("[+10] scale(network.bytes_in) found, but factor is not 8")
        else:
            feedback_parts.append("[-] Scale graph missing 'scale(' or 'network.bytes_in'")
    else:
        feedback_parts.append(f"[-] Scale graph '{GRAPH_TITLES['scale']}' not found")

    # Check Graph 3: DivideSeries (20 pts)
    title3, targets3 = _find_graph_by_title(graphs, GRAPH_TITLES["divide"])
    if not targets3:
        for t_title, t_targets in graphs:
            if any("divide" in str(x).lower() for x in t_targets):
                targets3 = t_targets
                feedback_parts.append(f"  (Using graph '{t_title}' for DivideSeries check)")
                break

    if targets3:
        t_str = " ".join(targets3).lower()
        if "divideseries(" in t_str and "disk.write_bytes" in t_str and "network.bytes_in" in t_str:
            # Check argument ordering: disk.write_bytes MUST be before network.bytes_in
            idx_disk = t_str.find("disk.write_bytes")
            idx_net = t_str.find("network.bytes_in")
            if idx_disk < idx_net:
                score += 20
                feedback_parts.append("[+20] divideSeries configured with correct numerator/denominator ordering")
            else:
                score += 10
                feedback_parts.append("[+10] divideSeries found, but numerator/denominator ordering is reversed")
        else:
            feedback_parts.append("[-] divideSeries graph missing function call or required metrics")
    else:
        feedback_parts.append(f"[-] DivideSeries graph '{GRAPH_TITLES['divide']}' not found")

    # Check Graph 4: Moving Median (20 pts)
    title4, targets4 = _find_graph_by_title(graphs, GRAPH_TITLES["median"])
    if not targets4:
        for t_title, t_targets in graphs:
            if any("median" in str(x).lower() for x in t_targets):
                targets4 = t_targets
                feedback_parts.append(f"  (Using graph '{t_title}' for movingMedian check)")
                break

    if targets4:
        t_str = " ".join(targets4).lower()
        if "movingmedian(" in t_str and "disk.write_bytes" in t_str:
            # Check if window size 10 is present
            if re.search(r'movingmedian\([^,]+,\s*[\'"]?10[\'"]?\)', t_str):
                score += 20
                feedback_parts.append("[+20] movingMedian(disk.write_bytes, 10) correctly configured")
            else:
                score += 10
                feedback_parts.append("[+10] movingMedian(disk.write_bytes) found, but window is not 10")
        else:
            feedback_parts.append("[-] movingMedian graph missing 'movingMedian(' or 'disk.write_bytes'")
    else:
        feedback_parts.append(f"[-] movingMedian graph '{GRAPH_TITLES['median']}' not found")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }