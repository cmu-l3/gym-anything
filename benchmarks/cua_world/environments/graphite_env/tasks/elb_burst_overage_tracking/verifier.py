#!/usr/bin/env python3
"""
Verifier for elb_burst_overage_tracking task.

Scoring (100 pts, pass >= 60):
  10 pts  Dashboard 'ELB Burst Overage Tracking' exists
  10 pts  Graph 'Traffic vs Baseline' exists
  15 pts  Graph 1 targets valid (load_balancer.requests.count + constantLine(50))
  10 pts  Graph 'Instantaneous Burst Volume' exists
  20 pts  Graph 2 logic valid (maxSeries, offset -50, constantLine 0)
  10 pts  Graph 'Cumulative Billable Overage' exists
  25 pts  Graph 3 logic valid (integral wrapping Graph 2 logic)
"""

import json
import os
import tempfile

DASHBOARD_NAME = "ELB Burst Overage Tracking"
RESULT_PATH = "/tmp/elb_burst_overage_tracking_result.json"


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


def _targets_contain_all(targets, keywords):
    """Check if any target contains ALL keywords."""
    for t in targets:
        tl = t.lower()
        if all(kw.lower() in tl for kw in keywords):
            return True
    return False


def _targets_contain_any(targets, keywords):
    """Check if any target contains ANY of the keywords."""
    for t in targets:
        tl = t.lower()
        if any(kw.lower() in tl for kw in keywords):
            return True
    return False


def verify_elb_burst_overage_tracking(trajectory, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}
    result_path = RESULT_PATH

    score = 0
    feedback = []

    # ── Load result file ──────────────────────────────────────────────────────
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            tmp_path = tmp.name
        copy_from_env(result_path, tmp_path)
        with open(tmp_path) as f:
            result = json.load(f)
        os.unlink(tmp_path)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not load result file: {e}",
        }

    dashboards = result.get("dashboards", {})

    # ── Check 1: Dashboard exists (10 pts) ────────────────────────────────────
    if DASHBOARD_NAME not in dashboards:
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                f"Dashboard '{DASHBOARD_NAME}' not found. "
                f"Dashboards present: {list(dashboards.keys())}"
            ),
        }
    score += 10
    feedback.append(f"[+10] Dashboard '{DASHBOARD_NAME}' exists")

    dashboard_state = dashboards[DASHBOARD_NAME]
    if "parse_error" in dashboard_state:
        return {
            "passed": False,
            "score": score,
            "feedback": f"Dashboard JSON parse error: {dashboard_state['parse_error']}",
        }

    graphs = _get_graphs(dashboard_state)

    # ── Check 2: Graph 1 - Traffic vs Baseline (10 + 15 pts) ──────────────────
    graph1 = _find_graph(graphs, "Traffic vs Baseline")
    if graph1:
        score += 10
        feedback.append("[+10] Graph 'Traffic vs Baseline' found")
        targets1 = graph1[1]
        has_requests = _targets_contain_all(targets1, ["load_balancer.requests.count"])
        has_baseline = _targets_contain_all(targets1, ["constantline", "50"])
        
        if has_requests and has_baseline:
            score += 15
            feedback.append("[+15] Graph 1 contains requests metric and constantLine(50)")
        else:
            feedback.append("[-] Graph 1 missing required targets (load_balancer.requests.count or constantLine(50))")
    else:
        feedback.append("[-] Graph 'Traffic vs Baseline' not found")

    # ── Check 3: Graph 2 - Instantaneous Burst Volume (10 + 20 pts) ───────────
    graph2 = _find_graph(graphs, "Instantaneous Burst Volume")
    if graph2:
        score += 10
        feedback.append("[+10] Graph 'Instantaneous Burst Volume' found")
        targets2 = graph2[1]
        
        # Check for complex logic: maxSeries, offset(-50), constantLine(0)
        has_requests = _targets_contain_all(targets2, ["load_balancer.requests.count"])
        has_offset = _targets_contain_all(targets2, ["offset", "-50"])
        has_max_const = _targets_contain_all(targets2, ["maxseries", "constantline", "0"])
        
        if has_requests and has_offset and has_max_const:
            score += 20
            feedback.append("[+20] Graph 2 contains valid burst logic (maxSeries, offset, constantLine)")
        else:
            feedback.append("[-] Graph 2 burst calculation logic incomplete or incorrect")
    else:
        feedback.append("[-] Graph 'Instantaneous Burst Volume' not found")

    # ── Check 4: Graph 3 - Cumulative Billable Overage (10 + 25 pts) ──────────
    graph3 = _find_graph(graphs, "Cumulative Billable Overage")
    if graph3:
        score += 10
        feedback.append("[+10] Graph 'Cumulative Billable Overage' found")
        targets3 = graph3[1]
        
        # Check for integral wrapping the burst logic
        has_integral = _targets_contain_all(targets3, ["integral"])
        has_requests = _targets_contain_all(targets3, ["load_balancer.requests.count"])
        has_offset = _targets_contain_all(targets3, ["offset", "-50"])
        has_max_const = _targets_contain_all(targets3, ["maxseries", "constantline", "0"])
        
        if has_integral and has_requests and has_offset and has_max_const:
            score += 25
            feedback.append("[+25] Graph 3 contains valid cumulative logic (integral + burst logic)")
        elif has_integral and has_requests:
            score += 10
            feedback.append("[+10] Graph 3 contains integral and requests, but burst logic is missing/incorrect")
        else:
            feedback.append("[-] Graph 3 cumulative logic missing or incorrect")
    else:
        feedback.append("[-] Graph 'Cumulative Billable Overage' not found")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }