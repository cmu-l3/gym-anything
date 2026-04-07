#!/usr/bin/env python3
"""
Verifier for database_efficiency_regression task.

Scoring (100 pts, pass >= 70):
  10 pts  Dashboard 'ORM Efficiency Analysis' exists
  10 pts  Dashboard has >= 4 graphs
  15 pts  Graph 'Raw Traffic Rate' found and correct
  10 pts  Graph 'Database CPU' found and correct
  25 pts  Graph 'Efficiency Index' found and correct
  30 pts  Graph 'Efficiency Degradation' found and correct
"""

import json
import os
import tempfile

DASHBOARD_NAME = "ORM Efficiency Analysis"
RESULT_PATH = "/tmp/database_efficiency_regression_result.json"

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

def normalize_target(t):
    """Normalize target string by removing spaces and standardizing quotes for evaluation."""
    return t.replace(' ', '').replace('"', "'").lower()

def verify_database_efficiency_regression(trajectory, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}
    
    score = 0
    details = []

    # ── Load result file ──────────────────────────────────────────────────────
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

    # ── Check 1: Dashboard exists (10 pts) ────────────────────────────────────
    if DASHBOARD_NAME not in dashboards:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Dashboard '{DASHBOARD_NAME}' not found. Present: {list(dashboards.keys())}"
        }
    
    score += 10
    details.append(f"[+10] Dashboard '{DASHBOARD_NAME}' exists")
    
    dashboard_state = dashboards[DASHBOARD_NAME]
    if "parse_error" in dashboard_state:
        return {"passed": False, "score": score, "feedback": f"Dashboard JSON parse error: {dashboard_state['parse_error']}"}

    graphs = _get_graphs(dashboard_state)
    
    # ── Check 2: Minimum graphs (10 pts) ──────────────────────────────────────
    if len(graphs) >= 4:
        score += 10
        details.append(f"[+10] Dashboard has {len(graphs)} graphs (>= 4)")
    else:
        details.append(f"[-] Expected >= 4 graphs, found {len(graphs)}")
        if not graphs:
            return {"passed": False, "score": score, "feedback": "\n".join(details)}

    # ── Check 3: Raw Traffic Rate (15 pts) ────────────────────────────────────
    g1_found = False
    for title, targets in graphs:
        if "Raw Traffic Rate" in title or "Raw Traffic" in title:
            norm_targets = [normalize_target(t) for t in targets]
            if any("nonnegativederivative(servers.load_balancer.requests.count)" in t for t in norm_targets):
                score += 15
                details.append("[+15] 'Raw Traffic Rate' graph is correct")
                g1_found = True
                break
    if not g1_found:
        details.append("[-] 'Raw Traffic Rate' graph missing or incorrect")

    # ── Check 4: Database CPU (10 pts) ────────────────────────────────────────
    g2_found = False
    for title, targets in graphs:
        if "Database CPU" in title:
            norm_targets = [normalize_target(t) for t in targets]
            if any("servers.rds_database.cpu.utilization" in t for t in norm_targets):
                score += 10
                details.append("[+10] 'Database CPU' graph is correct")
                g2_found = True
                break
    if not g2_found:
        details.append("[-] 'Database CPU' graph missing or incorrect")

    # ── Check 5: Efficiency Index (25 pts) ────────────────────────────────────
    g3_found = False
    for title, targets in graphs:
        if "Efficiency Index" in title:
            norm_targets = [normalize_target(t) for t in targets]
            valid = False
            for t in norm_targets:
                if "divideseries" in t and "nonnegativederivative" in t and "load_balancer.requests" in t and "rds_database.cpu" in t:
                    # simplistic check to enforce arg nesting order
                    if t.find("nonnegativederivative") < t.find("rds_database.cpu"):
                        valid = True
            if valid:
                score += 25
                details.append("[+25] 'Efficiency Index' graph is correct")
                g3_found = True
                break
    if not g3_found:
        details.append("[-] 'Efficiency Index' graph missing or incorrect")

    # ── Check 6: Efficiency Degradation (30 pts) ──────────────────────────────
    g4_found = False
    for title, targets in graphs:
        if "Efficiency Degradation" in title or "Degradation" in title:
            norm_targets = [normalize_target(t) for t in targets]
            has_base = False
            has_shifted = False
            for t in norm_targets:
                is_efficiency = "divideseries" in t and "nonnegativederivative" in t and "rds_database.cpu" in t
                if is_efficiency:
                    if "timeshift" in t and ('1d' in t or '24h' in t):
                        has_shifted = True
                    elif "timeshift" not in t:
                        has_base = True
            
            if has_base and has_shifted:
                score += 30
                details.append("[+30] 'Efficiency Degradation' graph is correct (both targets found)")
                g4_found = True
                break
            elif has_shifted:
                score += 15
                details.append("[+15] 'Efficiency Degradation' graph has timeShift target but missing base target")
                g4_found = True
                break
            elif has_base:
                score += 5
                details.append("[+5] 'Efficiency Degradation' graph has base target but missing timeShift target")
                g4_found = True
                break
    if not g4_found:
        details.append("[-] 'Efficiency Degradation' graph missing or incorrect")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(details)
    }