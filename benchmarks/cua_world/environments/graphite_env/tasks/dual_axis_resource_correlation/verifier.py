#!/usr/bin/env python3
"""
Verifier for dual_axis_resource_correlation task.

Scoring (100 pts, pass >= 60):
  15 pts  Dashboard 'Resource Correlation' exists
   5 pts  Dashboard has >= 1 graph
  15 pts  Graph titled 'CPU vs Disk Activity' found
  10 pts  Target contains ec2_instance_1.cpu.utilization
  10 pts  Target contains ec2_instance_1.disk.write_bytes
  10 pts  alias() used on CPU metric with 'CPU Utilization' label
  10 pts  alias() used on disk metric with 'Disk Write' label
  20 pts  secondYAxis() used on the disk metric
   5 pts  Both metrics appear in the SAME graph panel
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

DASHBOARD_NAME = "Resource Correlation"
GRAPH_TITLE = "CPU vs Disk Activity"
RESULT_PATH = "/tmp/dual_axis_resource_correlation_result.json"

CPU_METRIC = "ec2_instance_1.cpu.utilization"
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


def verify_dual_axis_resource_correlation(trajectory, env_info, task_info):
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

    # 2. Check Dashboard Existence (15 pts)
    # Perform case-insensitive search to be robust against minor typos
    dashboard_state = None
    for name, state in dashboards.items():
        if name.lower() == DASHBOARD_NAME.lower():
            dashboard_state = state
            score += 15
            feedback_parts.append(f"[+15] Dashboard '{DASHBOARD_NAME}' exists")
            break

    if not dashboard_state:
        feedback_parts.append(f"[-] Dashboard '{DASHBOARD_NAME}' not found.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    if "parse_error" in dashboard_state:
        feedback_parts.append(f"[-] Parse error: {dashboard_state['parse_error']}")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    graphs = _get_graphs(dashboard_state)

    # 3. Check Dashboard has >= 1 graph (5 pts)
    if not graphs:
        feedback_parts.append("[-] No graphs found in the dashboard")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}
    
    score += 5
    feedback_parts.append(f"[+5] Dashboard contains {len(graphs)} graph(s)")

    # Variables to track components across all graphs
    graph_title_found = False
    cpu_found = False
    disk_found = False
    cpu_alias_ok = False
    disk_alias_ok = False
    disk_second_y_ok = False
    both_in_same_graph = False

    # 4. Search for the specific requirements
    for title, targets in graphs:
        if title.lower() == GRAPH_TITLE.lower():
            graph_title_found = True
        elif GRAPH_TITLE.lower() in title.lower():
            graph_title_found = True  # Accept partial matches for the title

        has_cpu_in_this_graph = any(CPU_METRIC in t for t in targets)
        has_disk_in_this_graph = any(DISK_METRIC in t for t in targets)

        if has_cpu_in_this_graph and has_disk_in_this_graph:
            both_in_same_graph = True

        for t in targets:
            t_lower = t.lower()

            # CPU checks
            if CPU_METRIC in t:
                cpu_found = True
                if "alias" in t_lower and "cpu utilization" in t_lower:
                    cpu_alias_ok = True

            # Disk checks
            if DISK_METRIC in t:
                disk_found = True
                if "alias" in t_lower and "disk write" in t_lower:
                    disk_alias_ok = True
                if "secondyaxis" in t_lower:
                    disk_second_y_ok = True

    # 5. Score Components
    if graph_title_found:
        score += 15
        feedback_parts.append(f"[+15] Graph titled '{GRAPH_TITLE}' found")
    else:
        feedback_parts.append(f"[-] Graph titled '{GRAPH_TITLE}' NOT found")

    if cpu_found:
        score += 10
        feedback_parts.append(f"[+10] CPU metric target found")
    else:
        feedback_parts.append(f"[-] CPU metric target missing")

    if disk_found:
        score += 10
        feedback_parts.append(f"[+10] Disk metric target found")
    else:
        feedback_parts.append(f"[-] Disk metric target missing")

    if cpu_alias_ok:
        score += 10
        feedback_parts.append(f"[+10] Correct alias on CPU metric")
    else:
        feedback_parts.append(f"[-] Missing/incorrect alias on CPU metric")

    if disk_alias_ok:
        score += 10
        feedback_parts.append(f"[+10] Correct alias on Disk metric")
    else:
        feedback_parts.append(f"[-] Missing/incorrect alias on Disk metric")

    if disk_second_y_ok:
        score += 20
        feedback_parts.append(f"[+20] secondYAxis() applied to Disk metric")
    else:
        feedback_parts.append(f"[-] secondYAxis() NOT applied to Disk metric")

    if both_in_same_graph:
        score += 5
        feedback_parts.append(f"[+5] Both metrics successfully correlated in the same graph")
    else:
        feedback_parts.append(f"[-] Metrics are in separate graphs (failed correlation)")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "score": score,
            "both_in_same_graph": both_in_same_graph,
            "disk_second_y_ok": disk_second_y_ok
        }
    }