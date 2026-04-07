#!/usr/bin/env python3
"""
Verifier for alias_regex_legend_dashboard task.

Scoring (100 pts, pass >= 60):
  10 pts  Dashboard 'On-Call Runbook Metrics' exists
   5 pts  Dashboard has >= 4 graphs
   5 pts  Graph 'Server CPU Overview' present
  15 pts  aliasByNode used with ec2_instance wildcard in CPU graph
   5 pts  Graph 'System Vitals' present
  15 pts  alias() used for >= 2 distinct metrics in System Vitals
   5 pts  Graph 'Disk Activity' present
  20 pts  aliasSub used with regex pattern (and capture group) for disk metrics
   5 pts  Graph 'Request Rate with Stats' present
  10 pts  cactiStyle wrapping the LB request metric
   5 pts  derivative used inside the LB request target
"""

import json
import os
import re
import tempfile

DASHBOARD_NAME = "On-Call Runbook Metrics"
RESULT_PATH = "/tmp/alias_regex_legend_dashboard_result.json"

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

def verify_alias_regex_legend_dashboard(trajectory, env_info, task_info):
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

    # ── Check 2: Has >= 4 graphs (5 pts) ─────────────────────────────────────
    if len(graphs) >= 4:
        score += 5
        feedback_parts.append(f"[+5] Dashboard has {len(graphs)} graphs (>= 4)")
    else:
        feedback_parts.append(f"[-] Expected >= 4 graphs, found {len(graphs)}")

    # ── Graph 1: Server CPU Overview (20 pts) ────────────────────────────────
    g1 = _find_graph(graphs, "Server CPU Overview")
    if g1:
        score += 5
        feedback_parts.append("[+5] 'Server CPU Overview' graph found")
        targets = g1[1]
        
        has_aliasbynode = False
        for t in targets:
            tl = t.lower()
            if "aliasbynode" in tl and "ec2_instance" in tl and "cpu" in tl:
                has_aliasbynode = True
                break
                
        if has_aliasbynode:
            score += 15
            feedback_parts.append("[+15] aliasByNode used with EC2 wildcard")
        else:
            feedback_parts.append("[-] aliasByNode with EC2 CPU metric not found in graph 1")
    else:
        feedback_parts.append("[-] 'Server CPU Overview' graph missing")

    # ── Graph 2: System Vitals (20 pts) ──────────────────────────────────────
    g2 = _find_graph(graphs, "System Vitals")
    if g2:
        score += 5
        feedback_parts.append("[+5] 'System Vitals' graph found")
        targets = g2[1]
        
        alias_count = 0
        for t in targets:
            # Need to match simple alias(..., "...")
            if re.search(r'alias\(.*servers\..*\,.*\)', t, re.IGNORECASE):
                alias_count += 1
                
        if alias_count >= 2:
            score += 15
            feedback_parts.append(f"[+15] alias() used for {alias_count} distinct metrics")
        elif alias_count == 1:
            score += 7
            feedback_parts.append(f"[+7] alias() used for only 1 metric (expected >= 2)")
        else:
            feedback_parts.append("[-] alias() not properly applied to metrics in graph 2")
    else:
        feedback_parts.append("[-] 'System Vitals' graph missing")

    # ── Graph 3: Disk Activity (25 pts) ──────────────────────────────────────
    g3 = _find_graph(graphs, "Disk Activity")
    if g3:
        score += 5
        feedback_parts.append("[+5] 'Disk Activity' graph found")
        targets = g3[1]
        
        has_aliassub = False
        for t in targets:
            tl = t.lower()
            # Must have aliasSub, a disk metric, and parentheses indicating a regex capture group
            if "aliassub" in tl and "disk" in tl and ("(" in t or "%28" in t):
                has_aliassub = True
                break
                
        if has_aliassub:
            score += 20
            feedback_parts.append("[+20] aliasSub with regex capture group used correctly")
        else:
            feedback_parts.append("[-] aliasSub with proper regex capture group not found in graph 3")
    else:
        feedback_parts.append("[-] 'Disk Activity' graph missing")

    # ── Graph 4: Request Rate with Stats (20 pts) ────────────────────────────
    g4 = _find_graph(graphs, "Request Rate with Stats")
    if g4:
        score += 5
        feedback_parts.append("[+5] 'Request Rate with Stats' graph found")
        targets = g4[1]
        
        has_cactistyle = False
        has_derivative = False
        for t in targets:
            tl = t.lower()
            if "cactistyle" in tl and "load_balancer" in tl:
                has_cactistyle = True
            if "derivative" in tl and "load_balancer" in tl:
                has_derivative = True
                
        if has_cactistyle:
            score += 10
            feedback_parts.append("[+10] cactiStyle applied to load balancer metric")
        else:
            feedback_parts.append("[-] cactiStyle missing from load balancer target")
            
        if has_derivative:
            score += 5
            feedback_parts.append("[+5] derivative applied to load balancer metric")
        else:
            feedback_parts.append("[-] derivative missing from load balancer target")
    else:
        feedback_parts.append("[-] 'Request Rate with Stats' graph missing")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }