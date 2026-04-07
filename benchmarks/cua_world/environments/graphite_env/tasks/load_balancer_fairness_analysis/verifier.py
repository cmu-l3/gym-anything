#!/usr/bin/env python3
"""
Verifier for load_balancer_fairness_analysis task.

Scoring (100 pts, pass >= 60):
  10 pts  Dashboard 'Load Balancer Fairness' exists
   5 pts  'Network Traffic Share' graph title exists
  25 pts  Target contains asPercent on network wildcard and wrapped in aliasByNode with index 1
   5 pts  'Disk Write Share' graph title exists
  20 pts  Target contains asPercent on disk wildcard and wrapped in aliasByNode with index 1
   5 pts  'CPU Imbalance Magnitude' graph title exists
  20 pts  Target correctly nests absolute(diffSeries(...)) for instance 1 and 2 CPUs
  10 pts  Target is successfully wrapped in alias(..., "CPU Gap")
"""

import json
import os
import re
import tempfile

DASHBOARD_NAME = "Load Balancer Fairness"
RESULT_PATH = "/tmp/load_balancer_fairness_analysis_result.json"

GRAPH_NETWORK = "Network Traffic Share"
GRAPH_DISK = "Disk Write Share"
GRAPH_CPU = "CPU Imbalance Magnitude"


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


def _check_network_target(targets):
    """
    Check if target has aliasByNode(asPercent(servers.ec2_instance_*.network.bytes_in), 1)
    """
    for t in targets:
        t_clean = re.sub(r'\s+', '', t).lower()
        if "aspercent" in t_clean and "network.bytes_in" in t_clean and "aliasbynode" in t_clean and ",1" in t_clean:
            return True
        # Less strict checking just in case
        if "aspercent(" in t_clean and "network" in t_clean and "aliasbynode" in t_clean:
            return True
    return False


def _check_disk_target(targets):
    """
    Check if target has aliasByNode(asPercent(servers.ec2_instance_*.disk.write_bytes), 1)
    """
    for t in targets:
        t_clean = re.sub(r'\s+', '', t).lower()
        if "aspercent" in t_clean and "disk.write_bytes" in t_clean and "aliasbynode" in t_clean and ",1" in t_clean:
            return True
        if "aspercent(" in t_clean and "disk" in t_clean and "aliasbynode" in t_clean:
            return True
    return False


def _check_cpu_target(targets):
    """
    Check if target has absolute(diffSeries(servers.ec2_instance_1.cpu.utilization, servers.ec2_instance_2.cpu.utilization))
    and is wrapped in alias(..., "CPU Gap")
    """
    has_diff = False
    has_abs = False
    has_alias = False

    for t in targets:
        t_clean = re.sub(r'\s+', '', t).lower()
        if "diffseries" in t_clean and "ec2_instance_1" in t_clean and "ec2_instance_2" in t_clean and "cpu" in t_clean:
            has_diff = True
        if "absolute" in t_clean:
            has_abs = True
        if "alias" in t_clean and "cpugap" in t_clean.replace("\"", "").replace("'", ""):
            has_alias = True
        
        if has_diff and has_abs and has_alias:
            return True, True

    # Check if they partially got it
    return (has_diff and has_abs), has_alias


def verify_load_balancer_fairness(trajectory, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}
    
    result_path = RESULT_PATH
    score = 0
    feedback_parts = []

    # Load result file
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

    # Check 1: Dashboard exists (10 pts)
    if DASHBOARD_NAME not in dashboards:
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                f"Dashboard '{DASHBOARD_NAME}' not found. "
                f"Present: {list(dashboards.keys())}"
            ),
        }
    
    score += 10
    feedback_parts.append(f"[+10] Dashboard '{DASHBOARD_NAME}' exists")

    dashboard_state = dashboards[DASHBOARD_NAME]
    if "parse_error" in dashboard_state:
        return {
            "passed": False,
            "score": score,
            "feedback": f"Dashboard JSON parse error: {dashboard_state['parse_error']}",
        }

    graphs = _get_graphs(dashboard_state)

    # Graph 1: Network
    network_graph = _find_graph(graphs, GRAPH_NETWORK)
    if network_graph:
        score += 5
        feedback_parts.append(f"[+5] Graph '{GRAPH_NETWORK}' found")
        if _check_network_target(network_graph[1]):
            score += 25
            feedback_parts.append("[+25] Network graph has valid asPercent/aliasByNode target")
        else:
            feedback_parts.append("[-] Network graph target incorrect")
            # fallback check for partial
            if any("aspercent" in t.lower() for t in network_graph[1]):
                score += 10
                feedback_parts.append("[+10] Network graph target has asPercent (partial)")
    else:
        feedback_parts.append(f"[-] Graph '{GRAPH_NETWORK}' not found")
        # search by function
        for title, tgts in graphs:
            if _check_network_target(tgts):
                score += 25
                feedback_parts.append(f"[+25] Valid network target found in graph '{title}'")
                break

    # Graph 2: Disk
    disk_graph = _find_graph(graphs, GRAPH_DISK)
    if disk_graph:
        score += 5
        feedback_parts.append(f"[+5] Graph '{GRAPH_DISK}' found")
        if _check_disk_target(disk_graph[1]):
            score += 20
            feedback_parts.append("[+20] Disk graph has valid asPercent/aliasByNode target")
        else:
            feedback_parts.append("[-] Disk graph target incorrect")
            if any("aspercent" in t.lower() for t in disk_graph[1]):
                score += 10
                feedback_parts.append("[+10] Disk graph target has asPercent (partial)")
    else:
        feedback_parts.append(f"[-] Graph '{GRAPH_DISK}' not found")
        # search by function
        for title, tgts in graphs:
            if _check_disk_target(tgts):
                score += 20
                feedback_parts.append(f"[+20] Valid disk target found in graph '{title}'")
                break

    # Graph 3: CPU
    cpu_graph = _find_graph(graphs, GRAPH_CPU)
    cpu_targets = []
    if cpu_graph:
        score += 5
        feedback_parts.append(f"[+5] Graph '{GRAPH_CPU}' found")
        cpu_targets = cpu_graph[1]
    else:
        feedback_parts.append(f"[-] Graph '{GRAPH_CPU}' not found")
        # Find by content
        for title, tgts in graphs:
            has_diff_abs, has_al = _check_cpu_target(tgts)
            if has_diff_abs or has_al or any("diffseries" in t.lower() for t in tgts):
                cpu_targets = tgts
                feedback_parts.append(f"  (Using graph '{title}' for CPU Gap check)")
                break

    if cpu_targets:
        has_diff_abs, has_al = _check_cpu_target(cpu_targets)
        if has_diff_abs:
            score += 20
            feedback_parts.append("[+20] CPU graph has valid absolute(diffSeries(...)) structure")
        else:
            feedback_parts.append("[-] CPU graph missing diffSeries or absolute")
            if any("diffseries" in t.lower() for t in cpu_targets):
                score += 10
                feedback_parts.append("[+10] CPU graph has diffSeries (partial)")

        if has_al:
            score += 10
            feedback_parts.append("[+10] CPU target properly aliased as 'CPU Gap'")
        else:
            feedback_parts.append("[-] CPU target alias missing or incorrect name")

    # Check for passing criteria
    has_aspercent = any(_check_network_target(g[1]) or _check_disk_target(g[1]) for g in graphs)
    has_cpu_diff = any(_check_cpu_target(g[1])[0] for g in graphs)
    
    passed = score >= 60 and (has_aspercent and has_cpu_diff)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }