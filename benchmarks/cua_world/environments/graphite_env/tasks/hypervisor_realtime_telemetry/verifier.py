#!/usr/bin/env python3
"""
Verifier for hypervisor_realtime_telemetry task.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

DASHBOARD_NAME = "Hypervisor Telemetry"
RESULT_PATH = "/tmp/hypervisor_realtime_telemetry_result.json"

def _get_graphs(dashboard_state):
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
    for title, targets in graphs:
        if title == expected_title:
            return title, targets
    for title, targets in graphs:
        if expected_title.lower() in title.lower():
            return title, targets
    return None

def _has_target(targets, func, keywords, exact_args=None):
    for t in targets:
        tl = t.lower()
        if func.lower() in tl:
            if all(kw.lower() in tl for kw in keywords):
                if exact_args:
                    all_found = True
                    for arg in exact_args:
                        # Match whole numbers securely 
                        if arg.isdigit():
                            if not re.search(r'\b' + arg + r'\b', tl):
                                all_found = False
                                break
                        else:
                            if arg.lower() not in tl:
                                all_found = False
                                break
                    if all_found:
                        return True
                else:
                    return True
    return False

def verify_hypervisor_realtime_telemetry(trajectory, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}
    
    score = 0
    feedback_parts = []
    
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

    if DASHBOARD_NAME not in dashboards:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Dashboard '{DASHBOARD_NAME}' not found. Present: {list(dashboards.keys())}"
        }
    
    score += 15
    feedback_parts.append(f"[+15] Dashboard '{DASHBOARD_NAME}' exists")
    
    dashboard_state = dashboards[DASHBOARD_NAME]
    if "parse_error" in dashboard_state:
        return {
            "passed": False,
            "score": score,
            "feedback": f"Dashboard JSON parse error: {dashboard_state['parse_error']}"
        }

    graphs = _get_graphs(dashboard_state)
    
    # Check Graph 1: System Memory Layout
    g1 = _find_graph(graphs, "System Memory Layout")
    if g1:
        score += 10
        feedback_parts.append("[+10] Graph 'System Memory Layout' found")
        if _has_target(g1[1], "stacked", ["collectd", "memory"], ["*"]):
            score += 20
            feedback_parts.append("[+20] stacked() applied to collectd memory metrics with wildcard")
        elif _has_target(g1[1], "stacked", ["collectd", "memory"]):
            score += 15
            feedback_parts.append("[+15] stacked() applied, but wildcard '*' may be missing")
        else:
            feedback_parts.append("[-] stacked() not applied to collectd memory metrics")
    else:
        feedback_parts.append("[-] Graph 'System Memory Layout' not found")

    # Check Graph 2: CPU Core Comparison
    g2 = _find_graph(graphs, "CPU Core Comparison")
    if g2:
        score += 10
        feedback_parts.append("[+10] Graph 'CPU Core Comparison' found")
        if _has_target(g2[1], "aliasByNode", ["collectd", "cpu"], ["3", "*"]):
            score += 20
            feedback_parts.append("[+20] aliasByNode() applied to collectd cpu metrics with index 3")
        elif _has_target(g2[1], "aliasByNode", ["collectd", "cpu"], ["3"]):
            score += 15
            feedback_parts.append("[+15] aliasByNode() applied, but wildcard '*' may be missing")
        else:
            feedback_parts.append("[-] aliasByNode() not applied correctly to collectd cpu metrics")
    else:
        feedback_parts.append("[-] Graph 'CPU Core Comparison' not found")

    # Check Graph 3: System Load Envelopes
    g3 = _find_graph(graphs, "System Load Envelopes")
    if g3:
        score += 10
        feedback_parts.append("[+10] Graph 'System Load Envelopes' found")
        if _has_target(g3[1], "lineWidth", ["collectd", "load"], ["2", "*"]):
            score += 15
            feedback_parts.append("[+15] lineWidth() applied to collectd load metrics with width 2")
        elif _has_target(g3[1], "lineWidth", ["collectd", "load"], ["2"]):
            score += 10
            feedback_parts.append("[+10] lineWidth() applied, but wildcard '*' may be missing")
        else:
            feedback_parts.append("[-] lineWidth() not applied correctly to collectd load metrics")
    else:
        feedback_parts.append("[-] Graph 'System Load Envelopes' not found")
        
    passed = score >= 65
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }