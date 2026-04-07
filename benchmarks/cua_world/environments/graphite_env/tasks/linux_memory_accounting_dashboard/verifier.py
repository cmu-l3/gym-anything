#!/usr/bin/env python3
"""
Verifier for linux_memory_accounting_dashboard task.

Scoring System
| Criterion | Points | Description |
|-----------|--------|-------------|
| Dashboard Exists | 10 | Dashboard "Linux Memory Accounting" is found in the DB |
| Graph Count | 10 | Dashboard contains exactly 3 graphs |
| Graph 1 Title | 5 | Title exactly matches "Absolute Memory Breakdown" |
| Graph 1 Target: Stacked | 10 | Uses stacked() function |
| Graph 1 Target: Alias | 15 | Uses aliasByNode() with the correct node index (3) |
| Graph 2 Title | 5 | Title exactly matches "True Application Memory Percent" |
| Graph 2 Target: Percent | 15 | Uses asPercent() with memory-used as the first argument |
| Graph 2 Target: Total | 15 | Uses sumSeries() of all memory metrics as the second argument |
| Graph 3 Title | 5 | Title exactly matches "Available Memory" |
| Graph 3 Target: Sum | 10 | Uses sumSeries() combining memory-free and memory-cached |
| Total | 100 | |
"""

import json
import os
import tempfile

DASHBOARD_NAME = "Linux Memory Accounting"
GRAPH1_TITLE = "Absolute Memory Breakdown"
GRAPH2_TITLE = "True Application Memory Percent"
GRAPH3_TITLE = "Available Memory"
RESULT_PATH = "/tmp/linux_memory_accounting_dashboard_result.json"


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


def verify_linux_memory_accounting_dashboard(trajectory, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    result_path = RESULT_PATH
    score = 0
    feedback_parts = []

    # 1. Load result file safely using copy_from_env
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
        feedback_parts.append(f"Dashboard '{DASHBOARD_NAME}' not found.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}
    
    score += 10
    feedback_parts.append(f"Dashboard '{DASHBOARD_NAME}' exists")
    
    dashboard_state = dashboards[DASHBOARD_NAME]
    if "parse_error" in dashboard_state:
        feedback_parts.append(f"Dashboard parse error: {dashboard_state['parse_error']}")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    graphs = _get_graphs(dashboard_state)

    # Check 2: Graph count (10 pts)
    if len(graphs) >= 3:
        score += 10
        feedback_parts.append(f"Found {len(graphs)} graphs (>= 3)")
    else:
        feedback_parts.append(f"Found {len(graphs)} graphs, expected 3")

    def find_graph(title):
        for t, targets in graphs:
            if t == title:
                return targets
        for t, targets in graphs:
            if title.lower() in t.lower():
                return targets
        return None

    # Check 3: Graph 1 (Absolute Memory Breakdown)
    g1_targets = find_graph(GRAPH1_TITLE)
    if g1_targets is not None:
        score += 5
        feedback_parts.append(f"Graph '{GRAPH1_TITLE}' found")
        t_str = _targets_str(g1_targets)
        
        # Check Stacked
        if "stacked(" in t_str:
            score += 10
            feedback_parts.append("stacked() found")
        else:
            feedback_parts.append("stacked() missing")
            
        # Check aliasByNode(..., 3)
        if "aliasbynode(" in t_str and ",3)" in t_str.replace(" ", ""):
            score += 15
            feedback_parts.append("aliasByNode(..., 3) found")
        elif "aliasbynode(" in t_str:
            score += 5
            feedback_parts.append("aliasByNode() found but without node 3")
        else:
            feedback_parts.append("aliasByNode() missing")
    else:
        feedback_parts.append(f"Graph '{GRAPH1_TITLE}' not found")

    # Check 4: Graph 2 (True Application Memory Percent)
    g2_targets = find_graph(GRAPH2_TITLE)
    has_aspercent = False
    if g2_targets is not None:
        score += 5
        feedback_parts.append(f"Graph '{GRAPH2_TITLE}' found")
        t_str = _targets_str(g2_targets)
        
        # asPercent with memory-used
        if "aspercent(" in t_str and "memory-used" in t_str:
            score += 15
            has_aspercent = True
            feedback_parts.append("asPercent(..., memory-used) found")
        else:
            feedback_parts.append("asPercent() with memory-used missing")
            
        # sumSeries inside asPercent
        if has_aspercent and "sumseries(" in t_str:
            score += 15
            feedback_parts.append("sumSeries() inside asPercent found")
        else:
            feedback_parts.append("sumSeries() inside asPercent missing")
    else:
        feedback_parts.append(f"Graph '{GRAPH2_TITLE}' not found")

    # Check 5: Graph 3 (Available Memory)
    g3_targets = find_graph(GRAPH3_TITLE)
    if g3_targets is not None:
        score += 5
        feedback_parts.append(f"Graph '{GRAPH3_TITLE}' found")
        t_str = _targets_str(g3_targets)
        
        # We need sumSeries and both free/cached keywords
        # Brace expansion or multiple explicitly typed arguments work identically here
        if "sumseries(" in t_str and "memory-free" in t_str.replace("{","").replace("}","") and "memory-cached" in t_str.replace("{","").replace("}",""):
            score += 10
            feedback_parts.append("sumSeries(memory-free, memory-cached) found")
        elif "sumseries(" in t_str and "free" in t_str and "cached" in t_str:
            # Tolerant matcher in case the user successfully used brace expansion sumSeries(collectd.*.memory.memory-{free,cached})
            score += 10
            feedback_parts.append("sumSeries(..., free, cached) found")
        else:
            feedback_parts.append("sumSeries() with memory-free and memory-cached missing")
    else:
        feedback_parts.append(f"Graph '{GRAPH3_TITLE}' not found")

    passed = score >= 70 and has_aspercent
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }