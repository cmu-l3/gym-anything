#!/usr/bin/env python3
"""
Verifier for traffic_distribution_and_volume task.

Scoring (100 pts, pass >= 65):
  10 pts  Dashboard 'Traffic Distribution Report' exists
   5 pts  Dashboard has exactly 3 graphs
  10 pts  Graph titled 'Traffic Share Percentage' found
  20 pts  Graph 1 uses asPercent() with speed_sensor metrics
  10 pts  Graph titled 'Cumulative LB Requests' found
  15 pts  Graph 2 uses integral() on load balancer request count
   5 pts  Graph 2 is wrapped in color() with 'blue'
  10 pts  Graph titled 'Network Ingress Volume' found
  15 pts  Graph 3 uses cactiStyle() on ec2_instance_1.network.bytes_in
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

DASHBOARD_NAME = "Traffic Distribution Report"
GRAPH1_TITLE = "Traffic Share Percentage"
GRAPH2_TITLE = "Cumulative LB Requests"
GRAPH3_TITLE = "Network Ingress Volume"
RESULT_PATH = "/tmp/traffic_dist_result.json"

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

def _targets_str(targets):
    """Join all targets into one lowercase string for broad substring search."""
    return " ".join(targets).lower()

def verify_traffic_distribution_and_volume(trajectory, env_info, task_info):
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
            "feedback": f"Could not load result file: {e}",
        }

    dashboards = result.get("dashboards", {})

    # ── Check 1: Dashboard exists (10 pts) ────────────────────────────────────
    if DASHBOARD_NAME not in dashboards:
        # Check for case insensitive match
        found_dash = None
        for d_name in dashboards:
            if d_name.lower() == DASHBOARD_NAME.lower():
                found_dash = d_name
                break
                
        if found_dash:
            dashboard_state = dashboards[found_dash]
            score += 10
            feedback_parts.append(f"[+10] Dashboard '{found_dash}' exists (case-insensitive match)")
        else:
            return {
                "passed": False,
                "score": 0,
                "feedback": (
                    f"Dashboard '{DASHBOARD_NAME}' not found. "
                    f"Present: {list(dashboards.keys())}"
                ),
            }
    else:
        dashboard_state = dashboards[DASHBOARD_NAME]
        score += 10
        feedback_parts.append(f"[+10] Dashboard '{DASHBOARD_NAME}' exists")

    if "parse_error" in dashboard_state:
        return {
            "passed": False,
            "score": score,
            "feedback": f"Dashboard JSON parse error: {dashboard_state['parse_error']}",
        }

    graphs = _get_graphs(dashboard_state)

    # ── Check 2: Graph Count (5 pts) ──────────────────────────────────────────
    if len(graphs) == 3:
        score += 5
        feedback_parts.append("[+5] Dashboard contains exactly 3 graphs")
    elif len(graphs) > 0:
        feedback_parts.append(f"[-] Dashboard contains {len(graphs)} graphs (expected 3)")
    else:
        feedback_parts.append("[-] No graphs found in the dashboard")
        return {"passed": False, "score": score, "feedback": "\n".join(feedback_parts)}

    # Helper function to find graphs
    def find_graph(expected_title):
        for title, targets in graphs:
            if title == expected_title:
                return title, targets
        for title, targets in graphs:
            if expected_title.lower() in title.lower():
                return title, targets
        return None, None

    # ── Graph 1: Traffic Share Percentage ─────────────────────────────────────
    g1_title, g1_targets = find_graph(GRAPH1_TITLE)
    if g1_targets is not None:
        score += 10
        feedback_parts.append(f"[+10] Graph '{GRAPH1_TITLE}' found")
        
        ts1 = _targets_str(g1_targets)
        if "aspercent" in ts1 and "speed_sensor" in ts1:
            score += 20
            feedback_parts.append("[+20] Graph 1 uses asPercent() with web traffic metrics")
        else:
            feedback_parts.append("[-] Graph 1 missing asPercent() or web traffic metrics")
    else:
        feedback_parts.append(f"[-] Graph '{GRAPH1_TITLE}' not found")
        # Try finding the logic in any graph
        for _, tgts in graphs:
            ts = _targets_str(tgts)
            if "aspercent" in ts and "speed_sensor" in ts:
                score += 10 # Partial credit for logic existing without the title
                feedback_parts.append("[+10] Found asPercent() logic in an untitled/incorrectly-titled graph")
                break

    # ── Graph 2: Cumulative LB Requests ───────────────────────────────────────
    g2_title, g2_targets = find_graph(GRAPH2_TITLE)
    if g2_targets is not None:
        score += 10
        feedback_parts.append(f"[+10] Graph '{GRAPH2_TITLE}' found")
        
        ts2 = _targets_str(g2_targets)
        if "integral" in ts2 and "load_balancer.requests.count" in ts2:
            score += 15
            feedback_parts.append("[+15] Graph 2 uses integral() with load balancer requests")
        else:
            feedback_parts.append("[-] Graph 2 missing integral() or load balancer metrics")
            
        if "color" in ts2 and "blue" in ts2:
            score += 5
            feedback_parts.append("[+5] Graph 2 correctly uses color('blue')")
        else:
            feedback_parts.append("[-] Graph 2 missing color('blue')")
    else:
        feedback_parts.append(f"[-] Graph '{GRAPH2_TITLE}' not found")
        # Try finding the logic in any graph
        for _, tgts in graphs:
            ts = _targets_str(tgts)
            if "integral" in ts and "load_balancer.requests.count" in ts:
                score += 7 # Partial credit
                feedback_parts.append("[+7] Found integral() logic in an untitled/incorrectly-titled graph")
                if "color" in ts and "blue" in ts:
                    score += 2
                break

    # ── Graph 3: Network Ingress Volume ───────────────────────────────────────
    g3_title, g3_targets = find_graph(GRAPH3_TITLE)
    if g3_targets is not None:
        score += 10
        feedback_parts.append(f"[+10] Graph '{GRAPH3_TITLE}' found")
        
        ts3 = _targets_str(g3_targets)
        if "cactistyle" in ts3 and "ec2_instance_1.network.bytes_in" in ts3:
            score += 15
            feedback_parts.append("[+15] Graph 3 uses cactiStyle() with ec2 network metrics")
        else:
            feedback_parts.append("[-] Graph 3 missing cactiStyle() or network metrics")
    else:
        feedback_parts.append(f"[-] Graph '{GRAPH3_TITLE}' not found")
        # Try finding the logic in any graph
        for _, tgts in graphs:
            ts = _targets_str(tgts)
            if "cactistyle" in ts and "ec2_instance_1.network.bytes_in" in ts:
                score += 7 # Partial credit
                feedback_parts.append("[+7] Found cactiStyle() logic in an untitled/incorrectly-titled graph")
                break

    # ── Final Determination ───────────────────────────────────────────────────
    passed = score >= 65
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }