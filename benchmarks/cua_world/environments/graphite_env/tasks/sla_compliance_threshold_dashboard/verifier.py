#!/usr/bin/env python3
"""
Verifier for sla_compliance_threshold_dashboard task.

Scoring (100 pts, pass >= 60):
  10 pts  Dashboard 'SLA Compliance Report' exists
   5 pts  Dashboard has >= 3 graphs
  10 pts  Graph 'Fleet CPU vs SLA Target' found
  10 pts  maxSeries target with ec2_instance wildcard in Graph 1
  15 pts  threshold(80) target in Graph 1
  10 pts  Graph 'SLA Breach Windows' found
  15 pts  removeBelowValue(*, 80) target in Graph 2
  10 pts  maxSeries function present in Graph 2 targets
   5 pts  Graph 'Database CPU vs SLA Target' found
   5 pts  rds_database metric in Graph 3
   5 pts  threshold(90) target in Graph 3
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

DASHBOARD_NAME = "SLA Compliance Report"
RESULT_PATH = "/tmp/sla_compliance_threshold_dashboard_result.json"

GRAPH1_TITLE = "Fleet CPU vs SLA Target"
GRAPH2_TITLE = "SLA Breach Windows"
GRAPH3_TITLE = "Database CPU vs SLA Target"


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
    """Find graph by exact title, then case-insensitive. Returns (title, targets) or None."""
    for title, targets in graphs:
        if title == expected_title:
            return title, targets
    for title, targets in graphs:
        if expected_title.lower() in title.lower():
            return title, targets
    return None


def verify_sla_compliance_threshold_dashboard(trajectory, env_info, task_info):
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

    # ── Check 2: Has >= 3 graphs (5 pts) ──────────────────────────────────────
    if len(graphs) >= 3:
        score += 5
        feedback_parts.append(f"[+5] Dashboard contains {len(graphs)} graph(s)")
    else:
        feedback_parts.append(f"[-] Expected >= 3 graphs, found {len(graphs)}")

    # ── Check Graph 1: Fleet CPU vs SLA Target ────────────────────────────────
    g1 = _find_graph(graphs, GRAPH1_TITLE)
    if g1:
        score += 10
        feedback_parts.append(f"[+10] Graph '{GRAPH1_TITLE}' found")
        targets = g1[1]
        t_str = " ".join(targets).lower()

        # maxSeries + wildcard
        if "maxseries" in t_str and "ec2_instance" in t_str:
            score += 10
            feedback_parts.append("[+10] maxSeries with ec2_instance metrics in Graph 1")
        else:
            feedback_parts.append("[-] Missing maxSeries with ec2_instance metrics in Graph 1")

        # threshold(80)
        if re.search(r"threshold\(\s*80(?:\.0+)?\b", t_str):
            score += 15
            feedback_parts.append("[+15] threshold(80) present in Graph 1")
        elif "threshold" in t_str:
            feedback_parts.append("[-] threshold function used but not with value 80 in Graph 1")
        else:
            feedback_parts.append("[-] threshold(80) missing in Graph 1")
    else:
        feedback_parts.append(f"[-] Graph '{GRAPH1_TITLE}' not found")

    # ── Check Graph 2: SLA Breach Windows ─────────────────────────────────────
    g2 = _find_graph(graphs, GRAPH2_TITLE)
    if g2:
        score += 10
        feedback_parts.append(f"[+10] Graph '{GRAPH2_TITLE}' found")
        targets = g2[1]
        t_str = " ".join(targets).lower()

        # removeBelowValue(..., 80)
        if re.search(r"removebelowvalue\(.*,\s*80(?:\.0+)?\s*\)", t_str):
            score += 15
            feedback_parts.append("[+15] removeBelowValue with threshold 80 in Graph 2")
        elif "removebelowvalue" in t_str:
            feedback_parts.append("[-] removeBelowValue function used but missing correct 80 threshold in Graph 2")
        else:
            feedback_parts.append("[-] removeBelowValue missing in Graph 2")

        # maxSeries nested
        if "maxseries" in t_str:
            score += 10
            feedback_parts.append("[+10] maxSeries function present in Graph 2")
        else:
            feedback_parts.append("[-] maxSeries missing in Graph 2")
    else:
        feedback_parts.append(f"[-] Graph '{GRAPH2_TITLE}' not found")

    # ── Check Graph 3: Database CPU vs SLA Target ─────────────────────────────
    g3 = _find_graph(graphs, GRAPH3_TITLE)
    if g3:
        score += 5
        feedback_parts.append(f"[+5] Graph '{GRAPH3_TITLE}' found")
        targets = g3[1]
        t_str = " ".join(targets).lower()

        # rds_database metric
        if "rds_database.cpu" in t_str:
            score += 5
            feedback_parts.append("[+5] rds_database.cpu metric in Graph 3")
        else:
            feedback_parts.append("[-] rds_database metric missing in Graph 3")

        # threshold(90)
        if re.search(r"threshold\(\s*90(?:\.0+)?\b", t_str):
            score += 5
            feedback_parts.append("[+5] threshold(90) present in Graph 3")
        elif "threshold" in t_str:
            feedback_parts.append("[-] threshold function used but not with value 90 in Graph 3")
        else:
            feedback_parts.append("[-] threshold(90) missing in Graph 3")
    else:
        feedback_parts.append(f"[-] Graph '{GRAPH3_TITLE}' not found")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }