#!/usr/bin/env python3
"""
Verifier for noc_wall_visual_alerting task.

Scoring (100 pts, pass >= 60):
  10 pts  Dashboard 'NOC Wall Display' exists
   5 pts  RDS Graph exists
  15 pts  RDS metric styling (`lineWidth` 3, `color` 'blue')
  20 pts  RDS critical threshold (`threshold`/`constantLine` 85, `color` 'red', `alias` 'Critical')
   5 pts  Traffic Graph exists
  15 pts  Traffic metric math (`absolute`, `diffSeries`, speed_sensor_1, speed_sensor_2)
  10 pts  Traffic metric styling (`lineWidth` 2, `color` 'orange')
  20 pts  Traffic tolerance threshold (`threshold`/`constantLine` 500, `color` 'yellow', `alias` 'Tolerance')
"""

import json
import os
import tempfile
import re

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
        graphs.append((title, [str(t).lower() for t in targets])) # Lowercased for easier analysis
    return graphs

def _find_graph(graphs, expected_title):
    for title, targets in graphs:
        if title == expected_title:
            return targets
    # Fallback to case-insensitive partial match
    for title, targets in graphs:
        if expected_title.lower() in title.lower():
            return targets
    return None

def verify_noc_wall_visual_alerting(trajectory, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}
    
    metadata = task_info.get("metadata", {})
    dashboard_name = metadata.get("expected_dashboard_name", "NOC Wall Display")
    result_path = metadata.get("result_file", "/tmp/noc_wall_visual_alerting_result.json")

    score = 0
    feedback_parts = []

    # 1. Load result file safely
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
            "feedback": f"Could not load result file: {e}"
        }

    dashboards = result.get("dashboards", {})

    # 2. Check Dashboard Exists (10 pts)
    if dashboard_name not in dashboards:
        feedback_parts.append(f"Dashboard '{dashboard_name}' not found.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}
    
    score += 10
    feedback_parts.append(f"[+10] Dashboard '{dashboard_name}' exists")
    
    dashboard_state = dashboards[dashboard_name]
    if "parse_error" in dashboard_state:
        return {"passed": False, "score": score, "feedback": f"Dashboard parse error"}

    graphs = _get_graphs(dashboard_state)

    # 3. Analyze Graph 1: RDS CPU Risk
    rds_targets = _find_graph(graphs, "RDS CPU Risk")
    if rds_targets is not None:
        score += 5
        feedback_parts.append(f"[+5] Graph 'RDS CPU Risk' exists")

        # Check RDS Target Styling
        has_rds_metric = False
        rds_styled = False
        for t in rds_targets:
            if "rds_database.cpu.utilization" in t:
                has_rds_metric = True
                if ("color" in t and ("blue" in t)) and ("linewidth" in t and "3" in t):
                    rds_styled = True
                    break
        
        if rds_styled:
            score += 15
            feedback_parts.append("[+15] RDS metric perfectly styled (blue, width 3)")
        elif has_rds_metric:
            score += 5
            feedback_parts.append("[+5] RDS metric present but styling incomplete")
        
        # Check RDS Critical Threshold
        has_rds_thresh = False
        for t in rds_targets:
            if ("threshold(85" in t or "constantline(85" in t) and ("red" in t) and ("critical" in t):
                has_rds_thresh = True
                break
        
        if has_rds_thresh:
            score += 20
            feedback_parts.append("[+20] RDS threshold 85 styled correctly (red, alias Critical)")
        else:
            # Partial checks
            for t in rds_targets:
                if "threshold(85" in t or "constantline(85" in t:
                    score += 10
                    feedback_parts.append("[+10] RDS threshold 85 exists, but missing correct color/alias")
                    break
    else:
        feedback_parts.append("[-] Graph 'RDS CPU Risk' NOT found")


    # 4. Analyze Graph 2: Traffic Imbalance
    traffic_targets = _find_graph(graphs, "Traffic Imbalance")
    if traffic_targets is not None:
        score += 5
        feedback_parts.append(f"[+5] Graph 'Traffic Imbalance' exists")

        # Check Traffic Metric Math & Styling
        has_traffic_math = False
        traffic_styled = False
        for t in traffic_targets:
            if "absolute" in t and "diffseries" in t and "speed_sensor_1" in t and "speed_sensor_2" in t:
                has_traffic_math = True
                if ("color" in t and ("orange" in t)) and ("linewidth" in t and "2" in t):
                    traffic_styled = True
                    break

        if has_traffic_math:
            score += 15
            feedback_parts.append("[+15] Traffic math correctly applied (absolute diffSeries)")
            if traffic_styled:
                score += 10
                feedback_parts.append("[+10] Traffic delta perfectly styled (orange, width 2)")
            else:
                feedback_parts.append("[-] Traffic delta missing correct color or linewidth")
        else:
            feedback_parts.append("[-] Traffic math (absolute diffSeries) not found")

        # Check Traffic Tolerance Threshold
        has_traffic_thresh = False
        for t in traffic_targets:
            if ("threshold(500" in t or "constantline(500" in t) and ("yellow" in t) and ("tolerance" in t):
                has_traffic_thresh = True
                break
        
        if has_traffic_thresh:
            score += 20
            feedback_parts.append("[+20] Traffic threshold 500 styled correctly (yellow, alias Tolerance)")
        else:
            for t in traffic_targets:
                if "threshold(500" in t or "constantline(500" in t:
                    score += 10
                    feedback_parts.append("[+10] Traffic threshold 500 exists, but missing correct color/alias")
                    break
    else:
        feedback_parts.append("[-] Graph 'Traffic Imbalance' NOT found")

    # Determine passing status
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }