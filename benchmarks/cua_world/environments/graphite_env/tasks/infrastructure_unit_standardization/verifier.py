#!/usr/bin/env python3
"""
Verifier for infrastructure_unit_standardization task.

Scoring (100 pts, pass >= 60):
  10 pts  Dashboard 'GOC Standard Units' exists
  10 pts  Dashboard has exactly 4 graphs
  20 pts  Temp F Conversion: Graph 1 correctly applies scale(1.8) and offset(32) to the temperature metric with alias "Temp F"
  20 pts  MB Scaling: Graph 2 correctly applies scale(0.000001) to the network metric with alias "Ingress MB"
  20 pts  Rate Conversion: Graph 3 correctly applies nonNegativeDerivative() to the LB counter with alias "Requests/Interval"
  20 pts  Ratio Calculation: Graph 4 correctly applies divideSeries() to the speed sensors with alias "Speed Ratio"
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

DASHBOARD_NAME = "GOC Standard Units"
RESULT_PATH = "/tmp/infrastructure_unit_standardization_result.json"

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

def _find_graph_by_title(graphs, expected_title):
    """Find a graph by exact title, then case-insensitive partial match."""
    for title, targets in graphs:
        if title == expected_title:
            return title, targets
    for title, targets in graphs:
        if expected_title.lower() in title.lower():
            return title, targets
    return None, None

def _check_target(targets, keywords):
    """Check if any target contains ALL provided keywords (case-insensitive)."""
    for target in targets:
        tl = target.lower()
        if all(k.lower() in tl for k in keywords):
            return True
    return False

def verify_infrastructure_unit_standardization(trajectory, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}
    
    score = 0
    details = []

    # 1. Load result file
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

    # 2. Check if Dashboard exists
    if DASHBOARD_NAME not in dashboards:
        details.append(f"[-] Dashboard '{DASHBOARD_NAME}' not found. Present dashboards: {list(dashboards.keys())}")
        return {"passed": False, "score": 0, "feedback": "\n".join(details)}
    
    score += 10
    details.append(f"[+10] Dashboard '{DASHBOARD_NAME}' exists")

    dashboard_state = dashboards[DASHBOARD_NAME]
    if "parse_error" in dashboard_state:
        details.append(f"[-] Dashboard JSON parse error: {dashboard_state['parse_error']}")
        return {"passed": False, "score": score, "feedback": "\n".join(details)}

    graphs = _get_graphs(dashboard_state)

    # 3. Check graph count
    if len(graphs) >= 4:
        score += 10
        details.append(f"[+10] Dashboard has {len(graphs)} graphs (>= 4)")
    else:
        details.append(f"[-] Dashboard only has {len(graphs)} graphs (expected 4)")

    # 4. Verify Graph 1 (Datacenter Temp)
    g1_title, g1_targets = _find_graph_by_title(graphs, "Datacenter Temp (Fahrenheit)")
    if g1_targets:
        if _check_target(g1_targets, ["servers.datacenter.machine_temperature", "scale", "1.8", "offset", "32", "alias", "Temp F"]):
            score += 20
            details.append("[+20] Graph 1 ('Datacenter Temp (Fahrenheit)') correctly uses scale(), offset(), and alias()")
        else:
            details.append("[-] Graph 1 targets are missing required functions (scale/offset/alias) or correct arguments")
    else:
        details.append("[-] Graph titled 'Datacenter Temp (Fahrenheit)' not found")

    # 5. Verify Graph 2 (Network Ingress MB)
    g2_title, g2_targets = _find_graph_by_title(graphs, "Network Ingress (MB)")
    if g2_targets:
        has_correct_target = False
        for t in g2_targets:
            tl = t.lower()
            if "servers.ec2_instance_1.network.bytes_in" in tl and "alias" in tl and "ingress mb" in tl and "scale" in tl:
                # Accept common representations of 10^-6
                if "0.000001" in tl or "1e-06" in tl or "1e-6" in tl or ".000001" in tl:
                    has_correct_target = True
        
        if has_correct_target:
            score += 20
            details.append("[+20] Graph 2 ('Network Ingress (MB)') correctly uses scale(0.000001) and alias()")
        else:
            details.append("[-] Graph 2 targets are missing scale(), the 0.000001 multiplier, or alias()")
    else:
        details.append("[-] Graph titled 'Network Ingress (MB)' not found")

    # 6. Verify Graph 3 (LB Request Rate)
    g3_title, g3_targets = _find_graph_by_title(graphs, "LB Request Rate")
    if g3_targets:
        has_correct_target = False
        for t in g3_targets:
            tl = t.lower()
            if "servers.load_balancer.requests.count" in tl and "alias" in tl and "requests/interval" in tl:
                # Allow either derivative or nonNegativeDerivative
                if "derivative" in tl or "nonnegativederivative" in tl:
                    has_correct_target = True
        
        if has_correct_target:
            score += 20
            details.append("[+20] Graph 3 ('LB Request Rate') correctly uses derivative function and alias()")
        else:
            details.append("[-] Graph 3 targets are missing the derivative() function or correct alias")
    else:
        details.append("[-] Graph titled 'LB Request Rate' not found")

    # 7. Verify Graph 4 (Web Speed Ratio)
    g4_title, g4_targets = _find_graph_by_title(graphs, "Web Speed Ratio")
    if g4_targets:
        if _check_target(g4_targets, ["divideseries", "servers.web_traffic.speed_sensor_1", "servers.web_traffic.speed_sensor_2", "alias", "speed ratio"]):
            score += 20
            details.append("[+20] Graph 4 ('Web Speed Ratio') correctly uses divideSeries() and alias()")
        else:
            details.append("[-] Graph 4 targets are missing divideSeries() or correct alias")
    else:
        details.append("[-] Graph titled 'Web Speed Ratio' not found")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(details)
    }