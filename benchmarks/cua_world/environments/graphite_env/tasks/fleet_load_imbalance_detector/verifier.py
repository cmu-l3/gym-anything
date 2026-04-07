"""
Verifier for fleet_load_imbalance_detector task.

Scoring (100 pts, pass >= 60):
  10 pts  Dashboard 'Load Balancer Equity' exists
  10 pts  Dashboard contains exactly 3 graphs
  25 pts  Graph 'EC2 Fleet CPU Spread' exists with correct mathematical target
          (rangeOfSeries OR diffSeries with maxSeries and minSeries)
  25 pts  Graph 'Traffic Sensor Divergence' exists with correct mathematical target
          (absolute with diffSeries OR rangeOfSeries)
  30 pts  Graph 'Average Fleet Headroom' exists with correct mathematical target
          (100 minus average using constantLine/offset and diffSeries/scale)
"""

import json
import os
import tempfile

DASHBOARD_NAME = "Load Balancer Equity"
RESULT_PATH = "/tmp/fleet_load_imbalance_detector_result.json"

SPREAD_TITLE = "EC2 Fleet CPU Spread"
DIVERGENCE_TITLE = "Traffic Sensor Divergence"
HEADROOM_TITLE = "Average Fleet Headroom"


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


def verify_fleet_load_imbalance_detector(trajectory, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}
    result_path = RESULT_PATH

    score = 0
    feedback_parts = []

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
            "feedback": f"Could not load result file: {e}",
        }

    dashboards = result.get("dashboards", {})

    # ── Check 1: Dashboard exists (10 pts) ────────────────────────────────────
    if DASHBOARD_NAME not in dashboards:
        # Fallback: check case-insensitive
        found_dash = None
        for d_name in dashboards:
            if d_name.lower() == DASHBOARD_NAME.lower():
                found_dash = d_name
                break
        
        if not found_dash:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Dashboard '{DASHBOARD_NAME}' not found. Present: {list(dashboards.keys())}"
            }
        else:
            dashboard_state = dashboards[found_dash]
            score += 10
            feedback_parts.append(f"[+10] Dashboard '{found_dash}' exists (case-insensitive match)")
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

    # ── Check 2: Contains exactly 3 graphs (10 pts) ───────────────────────────
    if len(graphs) == 3:
        score += 10
        feedback_parts.append("[+10] Dashboard contains exactly 3 graphs")
    elif len(graphs) > 0:
        score += 5
        feedback_parts.append(f"[+5] Dashboard contains {len(graphs)} graphs (expected 3)")
    else:
        feedback_parts.append("[-] Dashboard contains no graphs")
        return {"passed": False, "score": score, "feedback": "\n".join(feedback_parts)}

    # ── Check 3: EC2 Fleet CPU Spread (25 pts) ────────────────────────────────
    spread_match = _find_graph(graphs, SPREAD_TITLE)
    if spread_match:
        _, spread_targets = spread_match
        target_str = " ".join(spread_targets).lower()
        
        has_ec2 = "ec2_instance" in target_str
        has_range = "rangeofseries" in target_str
        has_diff_max_min = "diffseries" in target_str and "maxseries" in target_str and "minseries" in target_str
        
        if has_ec2 and (has_range or has_diff_max_min):
            score += 25
            feedback_parts.append(f"[+25] Graph '{SPREAD_TITLE}' correctly calculates spread")
        else:
            feedback_parts.append(f"[-] Graph '{SPREAD_TITLE}' missing rangeOfSeries or max/min diff math")
    else:
        feedback_parts.append(f"[-] Graph '{SPREAD_TITLE}' not found")

    # ── Check 4: Traffic Sensor Divergence (25 pts) ───────────────────────────
    divergence_match = _find_graph(graphs, DIVERGENCE_TITLE)
    if divergence_match:
        _, div_targets = divergence_match
        target_str = " ".join(div_targets).lower()
        
        has_sensors = "speed_sensor_1" in target_str and "speed_sensor_2" in target_str
        has_abs_diff = "absolute" in target_str and "diffseries" in target_str
        has_range = "rangeofseries" in target_str
        
        if has_sensors and (has_abs_diff or has_range):
            score += 25
            feedback_parts.append(f"[+25] Graph '{DIVERGENCE_TITLE}' correctly calculates absolute divergence")
        else:
            feedback_parts.append(f"[-] Graph '{DIVERGENCE_TITLE}' missing absolute/diffSeries math or sensors")
    else:
        feedback_parts.append(f"[-] Graph '{DIVERGENCE_TITLE}' not found")

    # ── Check 5: Average Fleet Headroom (30 pts) ──────────────────────────────
    headroom_match = _find_graph(graphs, HEADROOM_TITLE)
    if headroom_match:
        _, head_targets = headroom_match
        target_str = " ".join(head_targets).lower()
        
        has_avg = "averageseries" in target_str or "avg" in target_str
        has_100 = "100" in target_str
        has_inversion = "diffseries" in target_str or ("scale" in target_str and "-1" in target_str)
        
        if has_avg and has_100 and has_inversion:
            score += 30
            feedback_parts.append(f"[+30] Graph '{HEADROOM_TITLE}' correctly calculates 100 - average headroom")
        else:
            feedback_parts.append(f"[-] Graph '{HEADROOM_TITLE}' missing 100-inversion logic or average function")
    else:
        feedback_parts.append(f"[-] Graph '{HEADROOM_TITLE}' not found")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }