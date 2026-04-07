#!/usr/bin/env python3
"""
Verifier for blue_green_migration_tracking task.

Scoring System (100 pts total, pass >= 65):
- Dashboard Exists (10 pts)
- Dashboard has exactly 4 graphs (10 pts)
- Graph 1 (Blue Fleet Aggregate Load): `sumSeries` targeting instance 1 and 2, wrapped in `alias` (20 pts)
- Graph 2 (Green Fleet Load): targets instance 3, wrapped in `alias` (15 pts)
- Graph 3 (Migration Shift Percentage): `asPercent` comparing instance 3 against entire fleet (25 pts)
- Graph 4 (Migration Differential): `diffSeries` subtracting instance 3 from sum of 1 and 2 (20 pts)

Uses `copy_from_env` to load exported database configurations.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

DASHBOARD_NAME = "Blue-Green Migration"
RESULT_PATH = "/tmp/blue_green_migration_tracking_result.json"

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

def verify_blue_green_migration_tracking(trajectory, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}
    
    score = 0
    feedback_parts = []
    
    # 1. Load exported result JSON from the container
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

    # 2. Check Dashboard Existence (10 pts)
    if DASHBOARD_NAME not in dashboards:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Dashboard '{DASHBOARD_NAME}' not found. Available: {list(dashboards.keys())}"
        }
    
    score += 10
    feedback_parts.append(f"Dashboard '{DASHBOARD_NAME}' exists (+10 pts)")
    
    dashboard_state = dashboards[DASHBOARD_NAME]
    if "parse_error" in dashboard_state:
        return {
            "passed": False,
            "score": score,
            "feedback": f"Dashboard JSON parse error: {dashboard_state['parse_error']}"
        }

    graphs = _get_graphs(dashboard_state)
    
    # 3. Check Graph Count (10 pts)
    if len(graphs) >= 4:
        score += 10
        feedback_parts.append(f"Dashboard has {len(graphs)} graphs (+10 pts)")
    elif len(graphs) == 0:
        feedback_parts.append("Dashboard has 0 graphs (+0 pts)")
        return {"passed": False, "score": score, "feedback": "\n".join(feedback_parts)}
    else:
        feedback_parts.append(f"Dashboard has {len(graphs)} graphs, expected 4 (+0 pts)")

    # Identify graphs by title contents safely
    def find_graph(title_keywords):
        for title, targets in graphs:
            if all(kw.lower() in title.lower() for kw in title_keywords):
                return targets
        return None

    blue_targets = find_graph(["Blue"])
    green_targets = find_graph(["Green"])
    shift_targets = find_graph(["Percentage"]) or find_graph(["Shift"])
    diff_targets = find_graph(["Differential"])

    # If any specific graphs were missed by title, check via partial string match in target logic as fallback
    if not shift_targets:
        for t, tgts in graphs:
            if "aspercent" in _targets_str(tgts):
                shift_targets = tgts
                break
    if not diff_targets:
        for t, tgts in graphs:
            if "diffseries" in _targets_str(tgts):
                diff_targets = tgts
                break
    
    # 4. Check Blue Fleet Aggregate Load (20 pts)
    if blue_targets:
        ts = _targets_str(blue_targets)
        has_sum = "sumseries" in ts or "sum(" in ts
        has_inst1 = "ec2_instance_1" in ts
        has_inst2 = "ec2_instance_2" in ts
        has_alias = "alias(" in ts
        
        pts = 0
        if has_sum and has_inst1 and has_inst2:
            pts += 15
        if has_alias:
            pts += 5
        score += pts
        feedback_parts.append(f"Blue Fleet Graph: +{pts}/20 pts (sum={has_sum}, inst1={has_inst1}, inst2={has_inst2}, alias={has_alias})")
    else:
        feedback_parts.append("Blue Fleet Graph not found (+0/20 pts)")

    # 5. Check Green Fleet Load (15 pts)
    if green_targets:
        ts = _targets_str(green_targets)
        has_inst3 = "ec2_instance_3" in ts
        has_alias = "alias(" in ts
        
        pts = 0
        if has_inst3:
            pts += 10
        if has_alias:
            pts += 5
        score += pts
        feedback_parts.append(f"Green Fleet Graph: +{pts}/15 pts (inst3={has_inst3}, alias={has_alias})")
    else:
        feedback_parts.append("Green Fleet Graph not found (+0/15 pts)")
        
    # 6. Check Migration Shift Percentage (25 pts)
    if shift_targets:
        ts = _targets_str(shift_targets)
        has_percent = "aspercent(" in ts
        has_inst3 = "ec2_instance_3" in ts
        has_fleet = ("ec2_instance_*" in ts or "ec2_instance_?" in ts or ("ec2_instance_1" in ts and "ec2_instance_2" in ts))
        
        pts = 0
        if has_percent:
            pts += 10
        if has_inst3:
            pts += 5
        if has_fleet:
            pts += 10
        score += pts
        feedback_parts.append(f"Shift Percentage Graph: +{pts}/25 pts (asPercent={has_percent}, inst3={has_inst3}, fleet={has_fleet})")
    else:
        feedback_parts.append("Shift Percentage Graph not found (+0/25 pts)")
        
    # 7. Check Migration Differential (20 pts)
    if diff_targets:
        ts = _targets_str(diff_targets)
        has_diff = "diffseries(" in ts or "diff(" in ts
        has_inst3 = "ec2_instance_3" in ts
        has_1_and_2 = ("ec2_instance_1" in ts and "ec2_instance_2" in ts) or "sumseries" in ts or "sum(" in ts
        
        pts = 0
        if has_diff:
            pts += 10
        if has_inst3:
            pts += 5
        if has_1_and_2:
            pts += 5
        score += pts
        feedback_parts.append(f"Differential Graph: +{pts}/20 pts (diffSeries={has_diff}, inst3={has_inst3}, 1&2={has_1_and_2})")
    else:
        feedback_parts.append("Differential Graph not found (+0/20 pts)")
        
    passed = score >= 65
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }