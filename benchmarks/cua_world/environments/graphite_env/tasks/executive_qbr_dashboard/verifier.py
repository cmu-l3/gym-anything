#!/usr/bin/env python3
"""
Verifier for the executive_qbr_dashboard task.
"""

import json
import os
import tempfile
import re

DASHBOARD_NAME = "QBR Infrastructure Summary"
RESULT_PATH = "/tmp/executive_qbr_dashboard_result.json"

def _get_graphs(dashboard_state):
    """Return a list of tuples containing (title, targets_list) from the dashboard dict."""
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
    """Find a graph by title, returning exactly matching one first, then ignoring case."""
    for title, targets in graphs:
        if title == expected_title:
            return title, targets
    for title, targets in graphs:
        if expected_title.lower() in title.lower():
            return title, targets
    return None

def verify_executive_qbr_dashboard(trajectory, env_info, task_info):
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
    
    # 1. Check if the required Dashboard exists (10 pts)
    if DASHBOARD_NAME not in dashboards:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Dashboard '{DASHBOARD_NAME}' not found. Present dashboards: {list(dashboards.keys())}"
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
    
    # 2. Minimum Graph Count Constraint (5 pts)
    if len(graphs) >= 3:
        score += 5
        feedback_parts.append(f"[+5] Dashboard has {len(graphs)} graphs")
    else:
        feedback_parts.append(f"[-] Expected at least 3 graphs, found {len(graphs)}")
        
    # --- Check Graph 1: Top CPU Consumers ---
    g1_match = _find_graph(graphs, "Top CPU Consumers")
    if g1_match:
        score += 8
        feedback_parts.append("[+8] Graph 'Top CPU Consumers' found")
        _, g1_targets = g1_match
        g1_str = " ".join(g1_targets).lower()
        
        # Checking highestCurrent composition
        if "highestcurrent" in g1_str and "2" in g1_str and "cpu" in g1_str:
            score += 10
            feedback_parts.append("[+10] highestCurrent function correctly applied")
        else:
            feedback_parts.append("[-] highestCurrent function mapping is missing or incorrect")
            
        # Checking aliasByNode composition
        if "aliasbynode" in g1_str and "1" in g1_str:
            score += 12
            feedback_parts.append("[+12] aliasByNode function properly layered")
        else:
            feedback_parts.append("[-] aliasByNode mapping is missing or incorrect")
    else:
        feedback_parts.append("[-] Graph 'Top CPU Consumers' missing")
        
    # --- Check Graph 2: Disk Write Rate ---
    g2_match = _find_graph(graphs, "Disk Write Rate")
    if g2_match:
        score += 8
        feedback_parts.append("[+8] Graph 'Disk Write Rate' found")
        _, g2_targets = g2_match
        g2_str = " ".join(g2_targets).lower()
        
        # Strict validation on nonNegativeDerivative applied to Counter metric
        if "nonnegativederivative" in g2_str and "instance_1.disk.write_bytes" in g2_str:
            score += 8
            feedback_parts.append("[+8] nonNegativeDerivative securely tracks instance_1 disk traffic")
        elif "derivative" in g2_str and "instance_1.disk.write_bytes" in g2_str:
            feedback_parts.append("[-] Used basic derivative() instead of safe nonNegativeDerivative() for instance_1")
            
        if "nonnegativederivative" in g2_str and "instance_2.disk.write_bytes" in g2_str:
            score += 8
            feedback_parts.append("[+8] nonNegativeDerivative securely tracks instance_2 disk traffic")
        elif "derivative" in g2_str and "instance_2.disk.write_bytes" in g2_str:
            feedback_parts.append("[-] Used basic derivative() instead of safe nonNegativeDerivative() for instance_2")
            
        # Check explicit alias transformation application
        if "alias(" in g2_str and "writes/sec" in g2_str:
            score += 6
            feedback_parts.append("[+6] Clean aliases applied to disk rates")
    else:
        feedback_parts.append("[-] Graph 'Disk Write Rate' missing")
        
    # --- Check Graph 3: Fleet CPU Envelope ---
    g3_match = _find_graph(graphs, "Fleet CPU Envelope")
    if g3_match:
        score += 8
        feedback_parts.append("[+8] Graph 'Fleet CPU Envelope' found")
        _, g3_targets = g3_match
        g3_str = " ".join(g3_targets).lower()
        
        if "maxseries" in g3_str and "cpu" in g3_str:
            score += 6
            feedback_parts.append("[+6] maxSeries aggregation target present")
            
        if "averageseries" in g3_str and "cpu" in g3_str:
            score += 5
            feedback_parts.append("[+5] averageSeries aggregation target present")
            
        if "minseries" in g3_str and "cpu" in g3_str:
            score += 6
            feedback_parts.append("[+6] minSeries aggregation target present")
            
    else:
        feedback_parts.append("[-] Graph 'Fleet CPU Envelope' missing")

    passed = score >= 60 and ("QBR Infrastructure Summary" in dashboards)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }