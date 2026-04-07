#!/usr/bin/env python3
"""
Verifier for executive_styled_capacity_report task.

Scoring (100 pts, pass >= 60):
  10 pts  Dashboard 'Executive Capacity Report' exists
  10 pts  Dashboard has >= 2 graphs
  10 pts  Graph 'Compute Headroom' found
  10 pts  Compute Metric correctly styled (ec2_instance_1, blue, cactiStyle, alias)
  10 pts  Compute Threshold correctly styled (constantLine 85, red, dashed, alias)
  10 pts  Graph 'Thermal Headroom' found
  10 pts  Thermal Metric correctly styled (machine_temperature, orange, cactiStyle, alias)
  10 pts  Thermal Threshold correctly styled (constantLine 80, red, dashed, alias)
  20 pts  VLM Verification of visual properties (dashed lines, cacti text, correct colors)

Uses copy_from_env to safely retrieve the database export without code execution vulnerabilities.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

DASHBOARD_NAME = "Executive Capacity Report"
RESULT_PATH = "/tmp/executive_capacity_report_result.json"

COMPUTE_TITLE = "Compute Headroom"
THERMAL_TITLE = "Thermal Headroom"

# Helper for substring matching in Graphite target syntax
def _target_has_all(target_str, required_substrings):
    t_lower = target_str.lower().replace('"', "'")
    for req in required_substrings:
        if req.lower() not in t_lower:
            return False
    return True

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

def verify_executive_capacity_report(trajectory, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    score = 0
    feedback_parts = []

    # ── 1. Load result file ──────────────────────────────────────────────────
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

    # ── 2. Check Dashboard Existence (10 pts) ────────────────────────────────
    if DASHBOARD_NAME not in dashboards:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Dashboard '{DASHBOARD_NAME}' not found.",
        }
    
    score += 10
    feedback_parts.append(f"Dashboard '{DASHBOARD_NAME}' exists")
    
    dashboard_state = dashboards[DASHBOARD_NAME]
    if "parse_error" in dashboard_state:
        return {
            "passed": False,
            "score": score,
            "feedback": f"Dashboard parse error: {dashboard_state['parse_error']}",
        }

    graphs = _get_graphs(dashboard_state)

    # ── 3. Check Graph Count (10 pts) ────────────────────────────────────────
    if len(graphs) >= 2:
        score += 10
        feedback_parts.append(f"Dashboard has >= 2 graphs")
    else:
        feedback_parts.append(f"Expected >= 2 graphs, found {len(graphs)}")

    # ── 4. Evaluate Compute Graph (30 pts) ───────────────────────────────────
    compute_graph = _find_graph(graphs, COMPUTE_TITLE)
    if compute_graph:
        score += 10
        feedback_parts.append(f"Graph '{COMPUTE_TITLE}' found")
        targets = compute_graph[1]

        # Check Target A (Metric styling)
        c_metric_reqs = ["ec2_instance_1", "cpu.utilization", "color", "'blue'", "cactistyle", "alias"]
        if any(_target_has_all(t, c_metric_reqs) for t in targets):
            score += 10
            feedback_parts.append("Compute Metric properly styled (blue, cactiStyle, alias)")
        else:
            feedback_parts.append("Compute Metric missing required styling functions")

        # Check Target B (Threshold styling)
        c_thresh_reqs = ["constantline(85)", "color", "'red'", "dashed", "alias"]
        if any(_target_has_all(t, c_thresh_reqs) for t in targets):
            score += 10
            feedback_parts.append("Compute Threshold properly styled (constantLine 85, red, dashed, alias)")
        else:
            feedback_parts.append("Compute Threshold missing required styling (e.g., constantLine 85, red, dashed)")
    else:
        feedback_parts.append(f"Graph '{COMPUTE_TITLE}' NOT found")

    # ── 5. Evaluate Thermal Graph (30 pts) ───────────────────────────────────
    thermal_graph = _find_graph(graphs, THERMAL_TITLE)
    if thermal_graph:
        score += 10
        feedback_parts.append(f"Graph '{THERMAL_TITLE}' found")
        targets = thermal_graph[1]

        # Check Target A (Metric styling)
        t_metric_reqs = ["datacenter.machine_temperature", "color", "'orange'", "cactistyle", "alias"]
        if any(_target_has_all(t, t_metric_reqs) for t in targets):
            score += 10
            feedback_parts.append("Thermal Metric properly styled (orange, cactiStyle, alias)")
        else:
            feedback_parts.append("Thermal Metric missing required styling functions")

        # Check Target B (Threshold styling)
        t_thresh_reqs = ["constantline(80)", "color", "'red'", "dashed", "alias"]
        if any(_target_has_all(t, t_thresh_reqs) for t in targets):
            score += 10
            feedback_parts.append("Thermal Threshold properly styled (constantLine 80, red, dashed, alias)")
        else:
            feedback_parts.append("Thermal Threshold missing required styling (e.g., constantLine 80, red, dashed)")
    else:
        feedback_parts.append(f"Graph '{THERMAL_TITLE}' NOT found")

    # ── 6. Secondary VLM Verification (20 pts) ───────────────────────────────
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        
        frames = sample_trajectory_frames(trajectory, n=3)
        final_img = get_final_screenshot(trajectory)
        if final_img:
            frames.append(final_img)

        vlm_prompt = """You are verifying the visual styling of a Graphite dashboard named "Executive Capacity Report".
        
        Look at these screenshots. Does the dashboard visibly contain:
        1. Dashed lines (indicating thresholds, likely red)?
        2. Specifically colored metric lines (blue and orange)?
        3. "Cacti-style" legends below the graphs (text indicating Current, Min, Max values for the metrics)?
        
        Respond in JSON format:
        {
            "has_dashed_lines": true/false,
            "has_colored_lines": true/false,
            "has_cacti_legends": true/false,
            "confidence": "high/medium/low",
            "reasoning": "Brief explanation"
        }
        """

        vlm_result = query_vlm(prompt=vlm_prompt, images=frames)
        if vlm_result.get("success"):
            parsed = vlm_result.get("parsed", {})
            visual_checks_passed = sum([
                parsed.get("has_dashed_lines", False),
                parsed.get("has_colored_lines", False),
                parsed.get("has_cacti_legends", False)
            ])
            
            # Award points based on visual features found (max 20 pts)
            vlm_points = min(20, int((visual_checks_passed / 3.0) * 20))
            score += vlm_points
            feedback_parts.append(f"VLM Visual Verification: {visual_checks_passed}/3 features found (+{vlm_points} pts)")
        else:
            feedback_parts.append(f"VLM check failed: {vlm_result.get('error', 'unknown error')}. Awarding partial credit (10 pts) for programmatic success.")
            score += 10 # Fallback points if VLM errors out
            
    except Exception as e:
        logger.warning(f"VLM verification exception: {e}")
        feedback_parts.append("VLM module not available, skipped visual verification.")
        # If VLM is unavailable, scale the score so maximum is still 100
        # Programmatic max is 80. If they got 80, they get 100.
        score = int((score / 80.0) * 100.0)

    # ── 7. Final Check ───────────────────────────────────────────────────────
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }