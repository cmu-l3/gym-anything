#!/usr/bin/env python3
"""
Verifier for canary_release_resource_validation task.

Scoring (100 pts, pass >= 60):
  10 pts  Dashboard 'Canary v2 Validation' exists
   5 pts  Dashboard contains >= 3 graphs
   5 pts  Graph 'CPU Regression Checker' exists
  10 pts  Stable/Canary CPU targets aliased correctly
  20 pts  diffSeries CPU Penalty target correct (subtracting instance_1 from instance_2)
   5 pts  Graph 'Disk I/O Multiplier' exists
  20 pts  divideSeries I/O Ratio target correct (instance_2 divided by instance_1)
   5 pts  Graph 'Cumulative CPU Cost' exists
  20 pts  integral CPU cost targets correct (wraps both metrics and aliased)
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

DASHBOARD_NAME = "Canary v2 Validation"
RESULT_PATH = "/tmp/canary_release_resource_validation_result.json"

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
    """Find a graph by exact title, then case-insensitive. Returns (title, targets) or (None, None)."""
    for title, targets in graphs:
        if title == expected_title:
            return title, targets
    for title, targets in graphs:
        if expected_title.lower() in title.lower():
            return title, targets
    return None, None

def _norm(s):
    """Normalize string by removing whitespace, quotes, and lowercasing for robust comparison."""
    return re.sub(r'[\s\'"]', '', str(s).lower())

def verify_canary_release_resource_validation(trajectory, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    score = 0
    feedback_parts = []

    # 1. Load result file
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

    # 2. Check Dashboard Existence
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

    # 3. Check graph count
    if len(graphs) >= 3:
        score += 5
        feedback_parts.append(f"[+5] Dashboard contains {len(graphs)} graphs (>= 3)")
    else:
        feedback_parts.append(f"[-] Dashboard only contains {len(graphs)} graphs, expected 3")

    # Graph 1: CPU Regression Checker
    title, targets = _find_graph(graphs, "CPU Regression Checker")
    if targets is not None:
        score += 5
        feedback_parts.append("[+5] Graph 'CPU Regression Checker' found")
        
        has_stable = False
        has_canary = False
        has_diff = False
        
        for t in targets:
            tn = _norm(t)
            # Check Stable CPU alias
            if "alias(" in tn and "ec2_instance_1.cpu.utilization" in tn and "stablecpu" in tn:
                has_stable = True
            # Check Canary CPU alias
            if "alias(" in tn and "ec2_instance_2.cpu.utilization" in tn and "canarycpu" in tn:
                has_canary = True
            # Check diffSeries penalty
            if "alias(" in tn and "diffseries(" in tn and "cpupenalty" in tn:
                # Need to verify order: Canary (2) minus Stable (1)
                match = re.search(r'diffseries\(([^,]+),([^)]+)\)', tn)
                if match:
                    arg1, arg2 = match.groups()
                    if "ec2_instance_2" in arg1 and "ec2_instance_1" in arg2:
                        has_diff = True
                        
        if has_stable and has_canary:
            score += 10
            feedback_parts.append("[+10] Stable/Canary CPU targets aliased correctly")
        else:
            feedback_parts.append("[-] Missing correctly aliased Stable or Canary CPU targets")
            
        if has_diff:
            score += 20
            feedback_parts.append("[+20] diffSeries CPU Penalty target correct (instance 2 minus 1)")
        else:
            feedback_parts.append("[-] Missing or incorrectly ordered diffSeries target")
    else:
        feedback_parts.append("[-] Graph 'CPU Regression Checker' not found")

    # Graph 2: Disk I/O Multiplier
    title, targets = _find_graph(graphs, "Disk I/O Multiplier")
    if targets is not None:
        score += 5
        feedback_parts.append("[+5] Graph 'Disk I/O Multiplier' found")
        
        has_divide = False
        for t in targets:
            tn = _norm(t)
            if "alias(" in tn and "divideseries(" in tn and "canaryi/oratio" in tn.replace("i/o", "io"):
                # Ratio string might lose slash or keep it depending on parsing/normalization
                # Let's just check 'ratio' and 'divide'
                pass
            if "divideseries(" in tn and "ratio" in tn:
                match = re.search(r'divideseries\(([^,]+),([^)]+)\)', tn)
                if match:
                    arg1, arg2 = match.groups()
                    if "ec2_instance_2.disk" in arg1 and "ec2_instance_1.disk" in arg2:
                        has_divide = True
                        
        if has_divide:
            score += 20
            feedback_parts.append("[+20] divideSeries I/O Ratio target correct (instance 2 divided by 1)")
        else:
            feedback_parts.append("[-] Missing or incorrectly ordered divideSeries target")
    else:
        feedback_parts.append("[-] Graph 'Disk I/O Multiplier' not found")

    # Graph 3: Cumulative CPU Cost
    title, targets = _find_graph(graphs, "Cumulative CPU Cost")
    if targets is not None:
        score += 5
        feedback_parts.append("[+5] Graph 'Cumulative CPU Cost' found")
        
        has_int_stable = False
        has_int_canary = False
        
        for t in targets:
            tn = _norm(t)
            if "alias(" in tn and "integral(" in tn:
                if "ec2_instance_1.cpu" in tn and "cumulativestable" in tn:
                    has_int_stable = True
                if "ec2_instance_2.cpu" in tn and "cumulativecanary" in tn:
                    has_int_canary = True
                    
        if has_int_stable and has_int_canary:
            score += 20
            feedback_parts.append("[+20] integral CPU cost targets correct")
        else:
            feedback_parts.append("[-] Missing correctly aliased integral targets")
    else:
        feedback_parts.append("[-] Graph 'Cumulative CPU Cost' not found")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }