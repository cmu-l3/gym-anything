#!/usr/bin/env python3
"""
Verifier for dynamic_wildcard_filtering task.

Scoring System (100 points total, Pass >= 60):
- Dashboard exists (10 pts)
- Graph count correct >= 3 (10 pts)
- Graph 1 "Stateless Compute Nodes" found (10 pts)
- Graph 1 target logic valid (wildcard + exclude "rds") (15 pts)
- Graph 2 "Maintenance Exclusion Avg" found (10 pts)
- Graph 2 target logic valid (averageSeries + wildcard + exclude "instance_2") (20 pts)
- Graph 3 "EC2 Explicit Grep" found (10 pts)
- Graph 3 target logic valid (wildcard + grep "ec2") (15 pts)

Anti-gaming: Ensure a wildcard (*) is actually used in the targets to prevent
hardcoding of individual metrics.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

DASHBOARD_NAME = "Sanitized Compute Fleet"
RESULT_PATH = "/tmp/dynamic_wildcard_filtering_result.json"

GRAPH_1_TITLE = "Stateless Compute Nodes"
GRAPH_2_TITLE = "Maintenance Exclusion Avg"
GRAPH_3_TITLE = "EC2 Explicit Grep"


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
    """Find a graph by exact or partial case-insensitive title."""
    for title, targets in graphs:
        if title == expected_title:
            return title, targets
    for title, targets in graphs:
        if expected_title.lower() in title.lower():
            return title, targets
    return None, None


def _check_target_logic(targets, required_keywords, forbidden_keywords=None):
    """
    Check if ANY target satisfies all required keywords.
    Also ensures a wildcard '*' is present.
    """
    if forbidden_keywords is None:
        forbidden_keywords = []

    for t in targets:
        tl = t.lower()
        
        # Anti-gaming: Ensure they used a wildcard, not hardcoded paths
        if "*" not in tl:
            continue
            
        has_all = all(kw.lower() in tl for kw in required_keywords)
        has_forbidden = any(fkw.lower() in tl for fkw in forbidden_keywords)
        
        if has_all and not has_forbidden:
            return True
    return False


def verify_dynamic_wildcard_filtering(trajectory, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}
    
    score = 0
    feedback_parts = []

    # 1. Load result file safely using copy_from_env
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

    # 2. Check Dashboard Exists (10 pts)
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

    # 3. Check Graph Count (10 pts)
    if len(graphs) >= 3:
        score += 10
        feedback_parts.append(f"[+10] Dashboard has {len(graphs)} graphs (>= 3)")
    else:
        feedback_parts.append(f"[-] Dashboard only has {len(graphs)} graphs, expected >= 3")

    # 4. Evaluate Graph 1: Stateless Compute Nodes
    g1_title, g1_targets = _find_graph(graphs, GRAPH_1_TITLE)
    if g1_targets is not None:
        score += 10
        feedback_parts.append(f"[+10] Graph '{GRAPH_1_TITLE}' found")
        
        # Needs exclude() and 'rds' and wildcard
        if _check_target_logic(g1_targets, ["exclude", "rds"]):
            score += 15
            feedback_parts.append(f"[+15] Graph 1 logic valid (wildcard + exclude 'rds')")
        else:
            feedback_parts.append("[-] Graph 1 logic invalid (missing exclude, 'rds', or wildcard)")
    else:
        feedback_parts.append(f"[-] Graph '{GRAPH_1_TITLE}' not found")

    # 5. Evaluate Graph 2: Maintenance Exclusion Avg
    g2_title, g2_targets = _find_graph(graphs, GRAPH_2_TITLE)
    if g2_targets is not None:
        score += 10
        feedback_parts.append(f"[+10] Graph '{GRAPH_2_TITLE}' found")
        
        # Needs averageSeries() and exclude() and 'instance_2' and wildcard
        if _check_target_logic(g2_targets, ["averageseries", "exclude", "instance_2"]):
            score += 20
            feedback_parts.append(f"[+20] Graph 2 logic valid (averageSeries + wildcard + exclude 'instance_2')")
        else:
            feedback_parts.append("[-] Graph 2 logic invalid (missing averageSeries, exclude, 'instance_2', or wildcard)")
    else:
        feedback_parts.append(f"[-] Graph '{GRAPH_2_TITLE}' not found")

    # 6. Evaluate Graph 3: EC2 Explicit Grep
    g3_title, g3_targets = _find_graph(graphs, GRAPH_3_TITLE)
    if g3_targets is not None:
        score += 10
        feedback_parts.append(f"[+10] Graph '{GRAPH_3_TITLE}' found")
        
        # Needs grep() and 'ec2' and wildcard
        if _check_target_logic(g3_targets, ["grep", "ec2"]):
            score += 15
            feedback_parts.append(f"[+15] Graph 3 logic valid (wildcard + grep 'ec2')")
        else:
            feedback_parts.append("[-] Graph 3 logic invalid (missing grep, 'ec2', or wildcard)")
    else:
        feedback_parts.append(f"[-] Graph '{GRAPH_3_TITLE}' not found")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }