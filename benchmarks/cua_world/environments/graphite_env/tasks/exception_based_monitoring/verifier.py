#!/usr/bin/env python3
"""
Verifier for exception_based_monitoring task.

Scoring (100 pts, pass >= 60):
  15 pts  Dashboard 'Exception Monitoring' exists
   5 pts  Dashboard has >= 4 graphs
  20 pts  Target contains highestAverage wrapping CPU metrics with parameter 2
  20 pts  Target contains averageAbove wrapping web_traffic metrics with parameter 60
  20 pts  Target contains sortByMaxima wrapping disk.write_bytes metrics
  20 pts  Target contains exclude wrapping CPU metrics with 'instance_2'
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

DASHBOARD_NAME = "Exception Monitoring"
RESULT_PATH = "/tmp/exception_based_monitoring_result.json"

def _get_all_targets(dashboard_state):
    """Return a flat list of all target strings across all graphs in the dashboard."""
    all_targets = []
    raw_graphs = dashboard_state.get("graphs", [])
    for entry in raw_graphs:
        if not isinstance(entry, (list, tuple)) or len(entry) < 2:
            continue
        params = entry[1] if isinstance(entry[1], dict) else {}
        targets = params.get("target", [])
        if isinstance(targets, str):
            targets = [targets]
        all_targets.extend([str(t) for t in targets])
    return all_targets

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

def verify_exception_based_monitoring(trajectory, env_info, task_info):
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

    # 1. Check Dashboard Exists (15 pts)
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
    all_targets = _get_all_targets(dashboard_state)

    # 2. Check Graph Count (5 pts)
    if len(graphs) >= 4:
        score += 5
        feedback_parts.append(f"[+5] Dashboard has {len(graphs)} graphs (>= 4)")
    else:
        feedback_parts.append(f"[-] Expected >= 4 graphs, found {len(graphs)}")

    # 3. Check highestAverage (20 pts)
    # Expected: highestAverage(servers.*.cpu.*, 2)
    highest_avg_found = False
    for t in all_targets:
        t_lower = t.lower()
        if "highestaverage" in t_lower and "cpu" in t_lower and ", 2)" in t_lower.replace("'", "").replace('"', ""):
            highest_avg_found = True
            break
        elif "highestaverage" in t_lower and re.search(r'highestaverage\s*\([^,]+cpu[^,]*,\s*2\s*\)', t_lower):
            highest_avg_found = True
            break

    if highest_avg_found:
        score += 20
        feedback_parts.append("[+20] highestAverage target correctly configured")
    else:
        feedback_parts.append("[-] highestAverage target with 'cpu' and parameter '2' not found")

    # 4. Check averageAbove (20 pts)
    # Expected: averageAbove(servers.web_traffic.*, 60)
    avg_above_found = False
    for t in all_targets:
        t_lower = t.lower()
        if "averageabove" in t_lower and "web_traffic" in t_lower and "60" in t_lower:
            avg_above_found = True
            break

    if avg_above_found:
        score += 20
        feedback_parts.append("[+20] averageAbove target correctly configured")
    else:
        feedback_parts.append("[-] averageAbove target with 'web_traffic' and parameter '60' not found")

    # 5. Check sortByMaxima (20 pts)
    # Expected: sortByMaxima(servers.ec2_instance_*.disk.write_bytes)
    sort_by_max_found = False
    for t in all_targets:
        t_lower = t.lower()
        if "sortbymaxima" in t_lower and "disk.write_bytes" in t_lower:
            sort_by_max_found = True
            break

    if sort_by_max_found:
        score += 20
        feedback_parts.append("[+20] sortByMaxima target correctly configured")
    else:
        feedback_parts.append("[-] sortByMaxima target with 'disk.write_bytes' not found")

    # 6. Check exclude (20 pts)
    # Expected: exclude(servers.ec2_instance_*.cpu.*, "instance_2")
    exclude_found = False
    for t in all_targets:
        t_lower = t.lower()
        if "exclude" in t_lower and "cpu" in t_lower and "instance_2" in t_lower:
            exclude_found = True
            break

    if exclude_found:
        score += 20
        feedback_parts.append("[+20] exclude target correctly configured")
    else:
        feedback_parts.append("[-] exclude target with 'instance_2' not found")

    # Determine final pass/fail
    key_criteria_met = highest_avg_found or avg_above_found or sort_by_max_found or exclude_found
    passed = (score >= 60) and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }