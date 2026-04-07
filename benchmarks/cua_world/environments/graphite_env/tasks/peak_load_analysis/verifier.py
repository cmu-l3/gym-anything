#!/usr/bin/env python3
"""
Verifier for peak_load_analysis task.

Scoring (100 pts total, pass >= 60):
  10 pts  Dashboard 'Peak Load Analysis' exists
  10 pts  Dashboard has >= 3 graphs
  
  Graph 'Hourly CPU Peaks' (30 pts):
   8 pts  Graph exists with correct title
   8 pts  Target contains summarize() with ec2_instance_1 CPU metric
   7 pts  summarize() uses "1hour" or "1h" bucket size
   7 pts  summarize() uses "max" aggregation
   
  Graph 'Worst Case Instance' (20 pts):
   8 pts  Graph exists with correct title
   8 pts  highestMax() with wildcard CPU pattern used
   4 pts  highestMax() selects top 1 (N=1)
   
  Graph 'Fleet CPU Ceiling' (30 pts):
   8 pts  Graph exists with correct title
   7 pts  maxSeries() includes ec2_instance_1 CPU
   7 pts  maxSeries() includes ec2_instance_2 CPU
   8 pts  maxSeries() includes ec2_instance_3 CPU (cloudwatch_utilization suffix)
"""

import json
import os
import re
import tempfile

DASHBOARD_NAME = "Peak Load Analysis"
RESULT_PATH = "/tmp/peak_load_analysis_result.json"

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

def verify_peak_load_analysis(trajectory, env_info, task_info):
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
        return {"passed": False, "score": 0, "feedback": f"Could not load result file: {e}"}
        
    dashboards = result.get("dashboards", {})
    
    # ── Check 1: Dashboard exists (10 pts) ────────────────────────────────────
    if DASHBOARD_NAME not in dashboards:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Dashboard '{DASHBOARD_NAME}' not found. Dashboards present: {list(dashboards.keys())}"
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
    
    # ── Check 2: >= 3 graphs (10 pts) ─────────────────────────────────────────
    if len(graphs) >= 3:
        score += 10
        feedback_parts.append(f"[+10] Dashboard has {len(graphs)} graphs")
    else:
        feedback_parts.append(f"[-] Dashboard has {len(graphs)} graphs (expected >= 3)")
        
    # ── Check 3: Hourly CPU Peaks graph ───────────────────────────────────────
    hourly_match = _find_graph(graphs, "Hourly CPU Peaks")
    if hourly_match:
        score += 8
        feedback_parts.append("[+8] Graph 'Hourly CPU Peaks' found")
        
        targets = [t.lower() for t in hourly_match[1]]
        target_str = " ".join(targets)
        
        if "summarize" in target_str and "ec2_instance_1.cpu.utilization" in target_str:
            score += 8
            feedback_parts.append("[+8] summarize() wraps ec2_instance_1 CPU metric")
        
        # Check bucket size: matches '1hour' or '1h' in quotes
        if re.search(r"['\"](1hour|1h)['\"]", target_str):
            score += 7
            feedback_parts.append("[+7] summarize() uses correct bucket size")
            
        # Check aggregation: matches 'max' in quotes
        if re.search(r"['\"]max['\"]", target_str):
            score += 7
            feedback_parts.append("[+7] summarize() uses 'max' aggregation")
    else:
        feedback_parts.append("[-] Graph 'Hourly CPU Peaks' not found")
        
    # ── Check 4: Worst Case Instance graph ────────────────────────────────────
    worst_match = _find_graph(graphs, "Worst Case Instance")
    if worst_match:
        score += 8
        feedback_parts.append("[+8] Graph 'Worst Case Instance' found")
        
        targets = [t.lower() for t in worst_match[1]]
        target_str = " ".join(targets)
        
        if "highestmax" in target_str and ("*" in target_str or "?" in target_str):
            score += 8
            feedback_parts.append("[+8] highestMax() uses a wildcard pattern")
            
        # Matches highestMax(..., 1)
        if re.search(r"highestmax\s*\([^,]+,\s*1\s*\)", target_str):
            score += 4
            feedback_parts.append("[+4] highestMax() selects top 1")
    else:
        feedback_parts.append("[-] Graph 'Worst Case Instance' not found")
        
    # ── Check 5: Fleet CPU Ceiling graph ──────────────────────────────────────
    fleet_match = _find_graph(graphs, "Fleet CPU Ceiling")
    if fleet_match:
        score += 8
        feedback_parts.append("[+8] Graph 'Fleet CPU Ceiling' found")
        
        targets = [t.lower() for t in fleet_match[1]]
        target_str = " ".join(targets)
        
        if "maxseries" in target_str:
            if "ec2_instance_1.cpu.utilization" in target_str:
                score += 7
                feedback_parts.append("[+7] maxSeries() includes instance 1")
            if "ec2_instance_2.cpu.utilization" in target_str:
                score += 7
                feedback_parts.append("[+7] maxSeries() includes instance 2")
            if "ec2_instance_3.cpu.cloudwatch_utilization" in target_str:
                score += 8
                feedback_parts.append("[+8] maxSeries() includes instance 3 (cloudwatch)")
    else:
        feedback_parts.append("[-] Graph 'Fleet CPU Ceiling' not found")
        
    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }