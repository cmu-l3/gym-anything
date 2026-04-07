#!/usr/bin/env python3
"""
Verifier for weekly_ops_comparison task.

Scoring (100 pts, pass >= 60):
  10 pts  Dashboard 'Weekly Ops Review' exists
   5 pts  Dashboard has >= 3 graphs
  
  Graph 1 ("CPU This Week vs Last Week"):
   5 pts  Graph title found
   5 pts  Base metric ec2_instance_1.cpu.utilization present
  12 pts  timeShift with 7d present
   5 pts  alias() used (gated behind timeShift)
   
  Graph 2 ("Temperature Baseline Shift"):
   5 pts  Graph title found
   5 pts  Base metric datacenter.machine_temperature present
  12 pts  timeShift with 7d present
   5 pts  alias() used (gated behind timeShift)
   
  Graph 3 ("Network Week-over-Week Delta"):
   5 pts  Graph title found
   5 pts  Base metric ec2_instance_1.network.bytes_in present
   8 pts  diffSeries present
   8 pts  timeShift nested inside the same target as diffSeries
   5 pts  alias() used (gated behind diffSeries/timeShift)
"""

import json
import os
import tempfile

DASHBOARD_NAME = "Weekly Ops Review"
RESULT_PATH = "/tmp/weekly_ops_comparison_result.json"

G1_TITLE = "CPU This Week vs Last Week"
G1_METRIC = "ec2_instance_1.cpu.utilization"

G2_TITLE = "Temperature Baseline Shift"
G2_METRIC = "datacenter.machine_temperature"

G3_TITLE = "Network Week-over-Week Delta"
G3_METRIC = "network.bytes_in"


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


def _targets_str(targets):
    """Join all targets into one lowercase string for broad substring search."""
    return " ".join(targets).lower()


def verify_weekly_ops_comparison(trajectory, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "details": "copy_from_env unavailable"}
    result_path = RESULT_PATH

    score = 0
    details = []

    # ── Load result file ──────────────────────────────────────────────────────
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
            "details": f"Could not load result file: {e}",
        }

    dashboards = result.get("dashboards", {})

    # ── Check 1: Dashboard exists (10 pts) ────────────────────────────────────
    if DASHBOARD_NAME not in dashboards:
        return {
            "passed": False,
            "score": 0,
            "details": (
                f"Dashboard '{DASHBOARD_NAME}' not found. "
                f"Present: {list(dashboards.keys())}"
            ),
        }
    score += 10
    details.append(f"[+10] Dashboard '{DASHBOARD_NAME}' exists")

    dashboard_state = dashboards[DASHBOARD_NAME]
    if "parse_error" in dashboard_state:
        return {
            "passed": False,
            "score": score,
            "details": f"Dashboard JSON parse error: {dashboard_state['parse_error']}",
        }

    graphs = _get_graphs(dashboard_state)

    # ── Check 2: Has >= 3 graphs (5 pts) ──────────────────────────────────────
    if len(graphs) >= 3:
        score += 5
        details.append(f"[+5] Dashboard has {len(graphs)} graphs (>= 3)")
    else:
        details.append(f"[-] Expected >= 3 graphs, found {len(graphs)}")

    # ── Graph 1: CPU This Week vs Last Week ───────────────────────────────────
    g1_match = _find_graph(graphs, G1_TITLE)
    if g1_match:
        title, targets = g1_match
        score += 5
        details.append(f"[+5] Graph '{G1_TITLE}' found")
        
        t_str = _targets_str(targets)
        
        if G1_METRIC in t_str:
            score += 5
            details.append(f"[+5] G1 base metric '{G1_METRIC}' present")
            
        has_timeshift = "timeshift" in t_str and ("7d" in t_str or "1w" in t_str)
        if has_timeshift:
            score += 12
            details.append("[+12] G1 timeShift with 7d present")
            
            if "alias" in t_str:
                score += 5
                details.append("[+5] G1 alias() wrapper present")
            else:
                details.append("[-] G1 alias() wrapper missing")
        else:
            details.append("[-] G1 timeShift(..., '7d') missing")
    else:
        details.append(f"[-] Graph '{G1_TITLE}' not found")

    # ── Graph 2: Temperature Baseline Shift ───────────────────────────────────
    g2_match = _find_graph(graphs, G2_TITLE)
    if g2_match:
        title, targets = g2_match
        score += 5
        details.append(f"[+5] Graph '{G2_TITLE}' found")
        
        t_str = _targets_str(targets)
        
        if G2_METRIC in t_str:
            score += 5
            details.append(f"[+5] G2 base metric '{G2_METRIC}' present")
            
        has_timeshift = "timeshift" in t_str and ("7d" in t_str or "1w" in t_str)
        if has_timeshift:
            score += 12
            details.append("[+12] G2 timeShift with 7d present")
            
            if "alias" in t_str:
                score += 5
                details.append("[+5] G2 alias() wrapper present")
            else:
                details.append("[-] G2 alias() wrapper missing")
        else:
            details.append("[-] G2 timeShift(..., '7d') missing")
    else:
        details.append(f"[-] Graph '{G2_TITLE}' not found")

    # ── Graph 3: Network Week-over-Week Delta ─────────────────────────────────
    g3_match = _find_graph(graphs, G3_TITLE)
    if g3_match:
        title, targets = g3_match
        score += 5
        details.append(f"[+5] Graph '{G3_TITLE}' found")
        
        t_str = _targets_str(targets)
        
        if G3_METRIC in t_str:
            score += 5
            details.append(f"[+5] G3 base metric '{G3_METRIC}' present")
            
        if "diffseries" in t_str:
            score += 8
            details.append("[+8] G3 diffSeries function present")
            
            # Anti-gaming: Ensure timeShift is inside diffSeries by checking if a SINGLE target has both
            nested = False
            for t in targets:
                tl = t.lower()
                if "diffseries" in tl and "timeshift" in tl and ("7d" in tl or "1w" in tl):
                    nested = True
                    break
                    
            if nested:
                score += 8
                details.append("[+8] G3 timeShift nested correctly inside diffSeries target")
                
                if "alias" in t_str:
                    score += 5
                    details.append("[+5] G3 alias() wrapper present")
                else:
                    details.append("[-] G3 alias() wrapper missing")
            else:
                details.append("[-] G3 timeShift not found nested inside the diffSeries target")
        else:
            details.append("[-] G3 diffSeries missing")
    else:
        details.append(f"[-] Graph '{G3_TITLE}' not found")

    # Final tally
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(details)
    }