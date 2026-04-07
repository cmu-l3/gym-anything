#!/usr/bin/env python3
"""
Verifier for executive_presentation_styling task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

DASHBOARD_NAME = "Customer Monthly Report"
FLEET_GRAPH = "Aggregate Fleet Compute"
DB_GRAPH = "Database Saturation Risk"
TRAFFIC_GRAPH = "Traffic Volume Trend"
RESULT_PATH = "/tmp/executive_presentation_styling_result.json"

def _get_graphs(dashboard_state):
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
    for title, targets in graphs:
        if title == expected_title:
            return title, targets
    for title, targets in graphs:
        if expected_title.lower() in title.lower():
            return title, targets
    return None

def verify_executive_presentation_styling(trajectory, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    score = 0
    feedback_parts = []

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
    if DASHBOARD_NAME not in dashboards:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Dashboard '{DASHBOARD_NAME}' not found."
        }

    score += 10
    feedback_parts.append(f"Dashboard '{DASHBOARD_NAME}' exists")

    dashboard_state = dashboards[DASHBOARD_NAME]
    if "parse_error" in dashboard_state:
        return {
            "passed": False,
            "score": score,
            "feedback": f"Dashboard JSON parse error: {dashboard_state['parse_error']}"
        }

    graphs = _get_graphs(dashboard_state)

    # Check 1: Fleet Graph
    fleet_match = _find_graph(graphs, FLEET_GRAPH)
    if fleet_match:
        score += 10
        feedback_parts.append(f"Graph '{FLEET_GRAPH}' found")
        _, targets = fleet_match

        has_stacked = False
        has_alias = False
        for t in targets:
            tl = t.lower().replace(" ", "")
            if "ec2_instance" in tl:
                if "stacked(" in tl:
                    has_stacked = True
                if "alias(" in tl or "aliasbynode(" in tl:
                    has_alias = True

        if has_stacked:
            score += 15
            feedback_parts.append("stacked() applied to fleet metrics")
        else:
            feedback_parts.append("stacked() missing on fleet metrics")

        if has_alias:
            score += 15
            feedback_parts.append("alias/aliasByNode applied to fleet metrics")
        else:
            feedback_parts.append("alias missing on fleet metrics")
    else:
        feedback_parts.append(f"Graph '{FLEET_GRAPH}' not found")

    # Check 2: Database Graph
    db_match = _find_graph(graphs, DB_GRAPH)
    if db_match:
        score += 10
        feedback_parts.append(f"Graph '{DB_GRAPH}' found")
        _, targets = db_match

        has_color = False
        has_linewidth = False

        for t in targets:
            tl = t.lower().replace(" ", "")
            if "rds_database" in tl:
                if "color(" in tl and "red" in tl:
                    has_color = True
                if "linewidth(" in tl and "3" in tl:
                    has_linewidth = True

        if has_color:
            score += 10
            feedback_parts.append("color(..., 'red') applied")
        if has_linewidth:
            score += 10
            feedback_parts.append("lineWidth(..., 3) applied")
    else:
        feedback_parts.append(f"Graph '{DB_GRAPH}' not found")

    # Check 3: Traffic Graph
    traffic_match = _find_graph(graphs, TRAFFIC_GRAPH)
    if traffic_match:
        score += 10
        feedback_parts.append(f"Graph '{TRAFFIC_GRAPH}' found")
        _, targets = traffic_match

        raw_correct = False
        trend_correct = False

        for t in targets:
            tl = t.lower().replace(" ", "")
            if "speed_sensor_1" in tl:
                if "movingaverage" in tl and "12" in tl:
                    if "color" in tl and "blue" in tl and "linewidth" in tl and "2" in tl and "alias" in tl and "trend" in tl:
                        trend_correct = True
                    elif "movingaverage" in tl:
                        trend_correct = True # Partial credit logic boolean
                else:
                    if "color" in tl and ("gray" in tl or "grey" in tl) and "alias" in tl and "raw" in tl:
                        raw_correct = True
                    elif "speed_sensor_1" in tl:
                        raw_correct = True

        if raw_correct and trend_correct:
            score += 10
            feedback_parts.append("Traffic graph targets configured properly")
        elif raw_correct or trend_correct:
            score += 5
            feedback_parts.append("Traffic graph partially configured")
    else:
        feedback_parts.append(f"Graph '{TRAFFIC_GRAPH}' not found")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }