#!/usr/bin/env python3
"""
Verifier for normalized_dependency_correlation task.

Scoring (100 pts, pass >= 60):
  10 pts  Dashboard 'Dependency Bottleneck Correlation' exists
  15 pts  All 3 required graphs exist (5 pts each)
  15 pts  RDS metric wrapped in normalize() and correctly aliased
  15 pts  Web Speed metric wrapped in normalize() and correctly aliased
  15 pts  EC2 metric wrapped in normalize() and correctly aliased
  15 pts  Load metric wrapped in nonNegativeDerivative() and normalize()
  15 pts  Load metric wrapped in color('red') and correctly aliased
"""

import json
import os
import tempfile

DASHBOARD_NAME = "Dependency Bottleneck Correlation"
RESULT_PATH = "/tmp/normalized_dependency_correlation_result.json"

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

def _target_matches(t, required_substrings):
    """Check if a target string contains all the required substrings (case-insensitive)."""
    t_lower = t.lower()
    return all(s.lower() in t_lower for s in required_substrings)

def _find_target(targets, required_substrings):
    """Find if any target in the list matches all required substrings."""
    for t in targets:
        if _target_matches(t, required_substrings):
            return True
    return False

def verify_normalized_dependency_correlation(trajectory, env_info, task_info):
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
    if DASHBOARD_NAME not in dashboards:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Dashboard '{DASHBOARD_NAME}' not found.",
        }
    
    score += 10
    feedback_parts.append(f"Dashboard '{DASHBOARD_NAME}' exists")
    
    dashboard_state = dashboards[DASHBOARD_NAME]
    graphs = _get_graphs(dashboard_state)
    
    # ── Check Graphs ──────────────────────────────────────────────────────────
    titles = [g[0] for g in graphs]
    db_found = any("Database vs Load" in t for t in titles)
    web_found = any("Web Speed vs Load" in t for t in titles)
    ec2_found = any("EC2 vs Load" in t for t in titles)
    
    graphs_found = sum([db_found, web_found, ec2_found])
    score += graphs_found * 5
    if graphs_found == 3:
        feedback_parts.append("All 3 required graphs found")
    else:
        feedback_parts.append(f"Found {graphs_found}/3 required graphs")
        
    all_targets = []
    for _, targets in graphs:
        all_targets.extend(targets)
        
    # ── Check Metric 1: RDS (15 pts) ──────────────────────────────────────────
    if _find_target(all_targets, ["servers.rds_database.cpu.utilization", "normalize", "alias", "db cpu"]):
        score += 15
        feedback_parts.append("RDS metric correctly normalized and aliased")
    else:
        feedback_parts.append("RDS metric missing or incorrect")
        
    # ── Check Metric 2: Web Speed (15 pts) ────────────────────────────────────
    if _find_target(all_targets, ["servers.web_traffic.speed_sensor_1", "normalize", "alias", "web speed"]):
        score += 15
        feedback_parts.append("Web Speed metric correctly normalized and aliased")
    else:
        feedback_parts.append("Web Speed metric missing or incorrect")
        
    # ── Check Metric 3: EC2 (15 pts) ──────────────────────────────────────────
    if _find_target(all_targets, ["servers.ec2_instance_1.cpu.utilization", "normalize", "alias", "ec2 cpu"]):
        score += 15
        feedback_parts.append("EC2 CPU metric correctly normalized and aliased")
    else:
        feedback_parts.append("EC2 CPU metric missing or incorrect")
        
    # ── Check Load Metric (30 pts split) ──────────────────────────────────────
    load_targets = [t for t in all_targets if "servers.load_balancer.requests.count" in t]
    
    if load_targets:
        # Check normalization transformations
        if _find_target(load_targets, ["nonnegativederivative", "normalize"]):
            score += 15
            feedback_parts.append("Load metric transformations correct")
        else:
            feedback_parts.append("Load metric transformations incorrect")
            
        # Check styling transformations
        if _find_target(load_targets, ["color", "red", "alias", "load"]):
            score += 15
            feedback_parts.append("Load metric styling correct")
        else:
            feedback_parts.append("Load metric styling incorrect")
    else:
        feedback_parts.append("Load metric missing entirely")
        
    # The agent successfully passes if they built the dashboard and got enough transformations
    passed = score >= 60 and ("Load metric transformations correct" in feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }