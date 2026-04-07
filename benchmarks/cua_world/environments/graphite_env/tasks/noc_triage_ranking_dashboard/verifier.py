#!/usr/bin/env python3
"""
Verifier for noc_triage_ranking_dashboard task.

Scoring (100 pts, pass >= 60):
  10 pts  Dashboard 'NOC Triage Board' exists
   5 pts  Dashboard has >= 3 graphs
  10 pts  Graph 'Hottest Servers' found
  15 pts  highestCurrent function used with CPU wildcard pattern
   5 pts  highestCurrent argument is exactly 2
  10 pts  Graph 'Temperature Alert Zone' found
   5 pts  machine_temperature metric present in graph
  15 pts  threshold() function present with value 80
  10 pts  Graph 'Sorted Disk Activity' found
  10 pts  sortByMaxima function used with disk write wildcard
   5 pts  aliasByNode function applied wrapping sortByMaxima with index 1
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

DASHBOARD_NAME = "NOC Triage Board"
RESULT_PATH = "/tmp/noc_triage_ranking_dashboard_result.json"

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

def verify_noc_triage_ranking_dashboard(trajectory, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}
    
    score = 0
    feedback_parts = []

    # ── Load result file ──────────────────────────────────────────────────────
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

    # ── Check 1: Dashboard exists (10 pts) ────────────────────────────────────
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

    # ── Check 2: Has >= 3 graphs (5 pts) ─────────────────────────────────────
    if len(graphs) >= 3:
        score += 5
        feedback_parts.append(f"[+5] Dashboard has {len(graphs)} graphs (>= 3)")
    else:
        feedback_parts.append(f"[-] Expected >= 3 graphs, found {len(graphs)}")

    # ── Check 3: Graph "Hottest Servers" (30 pts) ─────────────────────────────
    hottest = _find_graph(graphs, "Hottest Servers")
    if hottest:
        score += 10
        feedback_parts.append("[+10] Graph 'Hottest Servers' found")
        hottest_targets = hottest[1]
        
        has_hc_wildcard = False
        has_hc_2 = False
        
        for t in hottest_targets:
            t_lower = t.lower()
            if "highestcurrent" in t_lower:
                if "*" in t_lower and "cpu" in t_lower:
                    has_hc_wildcard = True
                if re.search(r'highestcurrent\(.+,\s*[\'"]?2[\'"]?\s*\)', t_lower):
                    has_hc_2 = True
        
        if has_hc_wildcard:
            score += 15
            feedback_parts.append("[+15] highestCurrent function used with CPU wildcard pattern")
        else:
            feedback_parts.append("[-] highestCurrent function with CPU wildcard not found")
            
        if has_hc_2:
            score += 5
            feedback_parts.append("[+5] highestCurrent argument is exactly 2")
        else:
            feedback_parts.append("[-] highestCurrent argument 2 not found")
    else:
        feedback_parts.append("[-] Graph 'Hottest Servers' not found")

    # ── Check 4: Graph "Temperature Alert Zone" (30 pts) ──────────────────────
    temp_zone = _find_graph(graphs, "Temperature Alert Zone")
    if temp_zone:
        score += 10
        feedback_parts.append("[+10] Graph 'Temperature Alert Zone' found")
        temp_targets = temp_zone[1]
        
        has_machine_temp = False
        has_threshold = False
        
        for t in temp_targets:
            t_lower = t.lower()
            if "machine_temperature" in t_lower:
                has_machine_temp = True
            if re.search(r'threshold\(\s*[\'"]?80[\'"]?', t_lower):
                has_threshold = True
                
        if has_machine_temp:
            score += 5
            feedback_parts.append("[+5] machine_temperature metric present")
        else:
            feedback_parts.append("[-] machine_temperature metric not found")
            
        if has_threshold:
            score += 15
            feedback_parts.append("[+15] threshold() function present with value 80")
        else:
            feedback_parts.append("[-] threshold(80) not found")
    else:
        feedback_parts.append("[-] Graph 'Temperature Alert Zone' not found")

    # ── Check 5: Graph "Sorted Disk Activity" (25 pts) ────────────────────────
    disk_act = _find_graph(graphs, "Sorted Disk Activity")
    if disk_act:
        score += 10
        feedback_parts.append("[+10] Graph 'Sorted Disk Activity' found")
        disk_targets = disk_act[1]
        
        has_sort = False
        has_alias = False
        
        for t in disk_targets:
            t_lower = t.lower()
            if "sortbymaxima" in t_lower and "disk.write_bytes" in t_lower:
                has_sort = True
            if "aliasbynode" in t_lower and re.search(r'aliasbynode\(.+,\s*[\'"]?1[\'"]?\s*\)', t_lower):
                has_alias = True
                
        if has_sort:
            score += 10
            feedback_parts.append("[+10] sortByMaxima function used with disk write metric")
        else:
            feedback_parts.append("[-] sortByMaxima with disk write not found")
            
        if has_alias:
            score += 5
            feedback_parts.append("[+5] aliasByNode function applied with index 1")
        else:
            feedback_parts.append("[-] aliasByNode with index 1 not found")
    else:
        feedback_parts.append("[-] Graph 'Sorted Disk Activity' not found")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }