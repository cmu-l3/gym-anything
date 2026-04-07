#!/usr/bin/env python3
"""
Verifier for wow_deployment_baseline task.

Scoring (100 pts, pass >= 60):
  10 pts  Dashboard 'WoW Deployment Baseline' exists
   5 pts  Dashboard has >= 3 graphs
  25 pts  'Web Traffic WoW' graph correctly configured (current + historical alias, color, timeShift)
  30 pts  'ELB Requests WoW' graph correctly configured (derivative, aliases, color, timeShift)
  25 pts  'RDS CPU WoW' graph correctly configured (current + historical alias, color, timeShift)
   5 pts  Time shift parameter properly formatted ('1w' or '7d')
"""

import json
import os
import tempfile

DASHBOARD_NAME = "WoW Deployment Baseline"
RESULT_PATH = "/tmp/wow_deployment_baseline_result.json"


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
    """Find a graph by exact or case-insensitive title match."""
    for title, targets in graphs:
        if title == expected_title:
            return targets
    for title, targets in graphs:
        if expected_title.lower() in title.lower():
            return targets
    return None


def _check_target(targets, metric, alias_name, require_timeshift=False, require_color=False, require_derivative=False):
    """
    Check if a target meeting all criteria exists in the list of targets.
    Uses substring matching so it is robust to arbitrary function nesting.
    """
    alias_lower = alias_name.lower()
    metric_lower = metric.lower()

    for t in targets:
        tl = t.lower()
        if metric_lower not in tl:
            continue

        if alias_lower not in tl:
            continue

        if require_derivative and "derivative" not in tl:
            continue

        if require_timeshift:
            if "timeshift" not in tl:
                continue
            if not any(x in tl for x in ["1w", "7d", "-1w", "-7d"]):
                continue

        if require_color:
            if "color" not in tl:
                continue
            if not any(x in tl for x in ["gray", "grey", "808080"]):
                continue

        return True
    return False


def verify_wow_deployment_baseline(trajectory, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    score = 0
    feedback_parts = []

    # 1. Copy and load result file
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

    # 2. Check Dashboard exists (10 pts)
    if DASHBOARD_NAME not in dashboards:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Dashboard '{DASHBOARD_NAME}' not found."
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

    # 3. Check graph count (5 pts)
    if len(graphs) >= 3:
        score += 5
        feedback_parts.append(f"[+5] Dashboard has {len(graphs)} graphs")
    else:
        feedback_parts.append(f"[-] Dashboard has only {len(graphs)} graphs (expected >= 3)")

    # 4. Verify 'Web Traffic WoW' (25 pts)
    web_targets = _find_graph(graphs, "Web Traffic WoW")
    if web_targets is not None:
        if _check_target(web_targets, "servers.web_traffic.speed_sensor_1", "Current Traffic"):
            score += 10
            feedback_parts.append("[+10] Web Traffic WoW: Current target configured correctly")
        else:
            feedback_parts.append("[-] Web Traffic WoW: Current target missing or incorrect")
            
        if _check_target(web_targets, "servers.web_traffic.speed_sensor_1", "Last Week Traffic", require_timeshift=True, require_color=True):
            score += 15
            feedback_parts.append("[+15] Web Traffic WoW: Historical target configured correctly")
        else:
            feedback_parts.append("[-] Web Traffic WoW: Historical target missing or incorrect")
    else:
        feedback_parts.append("[-] Graph 'Web Traffic WoW' not found")

    # 5. Verify 'ELB Requests WoW' (30 pts)
    elb_targets = _find_graph(graphs, "ELB Requests WoW")
    if elb_targets is not None:
        if _check_target(elb_targets, "servers.load_balancer.requests.count", "Current Requests", require_derivative=True):
            score += 12
            feedback_parts.append("[+12] ELB Requests WoW: Current target configured correctly (with derivative)")
        else:
            feedback_parts.append("[-] ELB Requests WoW: Current target missing or incorrect")
            
        if _check_target(elb_targets, "servers.load_balancer.requests.count", "Last Week Requests", require_timeshift=True, require_color=True, require_derivative=True):
            score += 18
            feedback_parts.append("[+18] ELB Requests WoW: Historical target configured correctly (with derivative)")
        else:
            feedback_parts.append("[-] ELB Requests WoW: Historical target missing or incorrect")
    else:
        feedback_parts.append("[-] Graph 'ELB Requests WoW' not found")

    # 6. Verify 'RDS CPU WoW' (25 pts)
    rds_targets = _find_graph(graphs, "RDS CPU WoW")
    if rds_targets is not None:
        if _check_target(rds_targets, "servers.rds_database.cpu.utilization", "Current RDS CPU"):
            score += 10
            feedback_parts.append("[+10] RDS CPU WoW: Current target configured correctly")
        else:
            feedback_parts.append("[-] RDS CPU WoW: Current target missing or incorrect")
            
        if _check_target(rds_targets, "servers.rds_database.cpu.utilization", "Last Week RDS CPU", require_timeshift=True, require_color=True):
            score += 15
            feedback_parts.append("[+15] RDS CPU WoW: Historical target configured correctly")
        else:
            feedback_parts.append("[-] RDS CPU WoW: Historical target missing or incorrect")
    else:
        feedback_parts.append("[-] Graph 'RDS CPU WoW' not found")

    # 7. Check formatting of time shift string broadly across graphs (5 pts)
    time_shift_valid = False
    for title, targets in graphs:
        for t in targets:
            tl = t.lower()
            if "timeshift" in tl and any(x in tl for x in ["1w", "7d", "-1w", "-7d"]):
                time_shift_valid = True
                break
    if time_shift_valid:
        score += 5
        feedback_parts.append("[+5] Valid timeShift string format used ('1w' or '7d')")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }