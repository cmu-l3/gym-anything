#!/usr/bin/env python3
"""
Verifier for cumulative_transfer_reporting task.

Scoring:
- Dashboard "Quarterly Ops Review" exists (10)
- Dashboard has >= 3 graphs (10)
- Graph "Cumulative Network Transfer" found (10)
- integral() applied to network.bytes_in (15)
- alias() wrapping network integral (5)
- Graph "Request Rate" found (10)
- nonNegativeDerivative() applied to load_balancer.requests.count (15)
- alias() wrapping request rate (5)
- Graph "Cumulative Disk IO" found (10)
- integral() on instance 1 disk write bytes (5)
- integral() on instance 2 disk write bytes (5)

Pass Threshold: 60 points
"""

import json
import os
import tempfile

DASHBOARD_NAME = "Quarterly Ops Review"
RESULT_PATH = "/tmp/cumulative_transfer_reporting_result.json"

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
    for title, targets in graphs:
        if title == expected_title:
            return title, targets
    for title, targets in graphs:
        if expected_title.lower() in title.lower():
            return title, targets
    return None

def verify_cumulative_transfer_reporting(trajectory, env_info, task_info):
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
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not load result file: {e}"
        }

    dashboards = result.get("dashboards", {})

    if DASHBOARD_NAME not in dashboards:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Dashboard '{DASHBOARD_NAME}' not found. Present: {list(dashboards.keys())}"
        }
    
    score += 10
    feedback_parts.append(f"Dashboard '{DASHBOARD_NAME}' exists (+10)")

    dashboard_state = dashboards[DASHBOARD_NAME]
    if "parse_error" in dashboard_state:
        return {
            "passed": False,
            "score": score,
            "feedback": f"Dashboard JSON parse error: {dashboard_state['parse_error']}"
        }

    graphs = _get_graphs(dashboard_state)
    
    if len(graphs) >= 3:
        score += 10
        feedback_parts.append(f"Dashboard has {len(graphs)} graphs (>= 3) (+10)")
    else:
        feedback_parts.append(f"Expected >= 3 graphs, found {len(graphs)}")

    # Graph 1: Cumulative Network Transfer
    net_match = _find_graph(graphs, "Cumulative Network Transfer")
    if net_match:
        title, targets = net_match
        score += 10
        feedback_parts.append("Graph 'Cumulative Network Transfer' found (+10)")
        
        has_net_integral = False
        has_net_alias = False
        for t in targets:
            tl = t.lower()
            if "integral" in tl and "ec2_instance_1.network.bytes_in" in tl:
                has_net_integral = True
                if "alias" in tl and "total inbound bytes" in tl:
                    has_net_alias = True
                
        if has_net_integral:
            score += 15
            feedback_parts.append("integral() applied to network.bytes_in (+15)")
        else:
            feedback_parts.append("integral() on network.bytes_in missing")
            
        if has_net_alias:
            score += 5
            feedback_parts.append("alias() wrapping network integral (+5)")
        else:
            feedback_parts.append("alias() wrapping network integral missing")
    else:
        feedback_parts.append("Graph 'Cumulative Network Transfer' not found")

    # Graph 2: Request Rate
    req_match = _find_graph(graphs, "Request Rate")
    if req_match:
        title, targets = req_match
        score += 10
        feedback_parts.append("Graph 'Request Rate' found (+10)")
        
        has_req_deriv = False
        has_req_alias = False
        for t in targets:
            tl = t.lower()
            if "nonnegativederivative" in tl and "load_balancer.requests.count" in tl:
                has_req_deriv = True
                if "alias" in tl and "requests per second" in tl:
                    has_req_alias = True
                    
        if has_req_deriv:
            score += 15
            feedback_parts.append("nonNegativeDerivative() applied to load_balancer.requests.count (+15)")
        else:
            has_plain_deriv = any("derivative" in t.lower() and "load_balancer" in t.lower() for t in targets)
            if has_plain_deriv:
                feedback_parts.append("Used derivative() instead of nonNegativeDerivative() - 0 pts")
            else:
                feedback_parts.append("nonNegativeDerivative() on load balancer missing")
                
        if has_req_alias:
            score += 5
            feedback_parts.append("alias() wrapping request rate (+5)")
        else:
            feedback_parts.append("alias() wrapping request rate missing")
    else:
        feedback_parts.append("Graph 'Request Rate' not found")

    # Graph 3: Cumulative Disk IO
    disk_match = _find_graph(graphs, "Cumulative Disk IO")
    if disk_match:
        title, targets = disk_match
        score += 10
        feedback_parts.append("Graph 'Cumulative Disk IO' found (+10)")
        
        has_disk1 = False
        has_disk2 = False
        for t in targets:
            tl = t.lower()
            if "integral" in tl and "ec2_instance_1.disk.write_bytes" in tl:
                has_disk1 = True
            if "integral" in tl and "ec2_instance_2.disk.write_bytes" in tl:
                has_disk2 = True
                
        if has_disk1:
            score += 5
            feedback_parts.append("integral() on instance 1 disk write bytes (+5)")
        else:
            feedback_parts.append("integral() on instance 1 disk write bytes missing")
            
        if has_disk2:
            score += 5
            feedback_parts.append("integral() on instance 2 disk write bytes (+5)")
        else:
            feedback_parts.append("integral() on instance 2 disk write bytes missing")
    else:
        feedback_parts.append("Graph 'Cumulative Disk IO' not found")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }