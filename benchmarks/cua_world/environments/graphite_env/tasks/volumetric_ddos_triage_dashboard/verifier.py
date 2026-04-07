#!/usr/bin/env python3
"""
Verifier for volumetric_ddos_triage_dashboard task.

Scoring (100 pts, pass >= 70):
  10 pts  Dashboard 'DDoS Threat Triage' exists
  10 pts  Dashboard has >= 4 graphs
  10 pts  'Inbound Request Volume' graph target matches
  20 pts  'Inbound Bandwidth Rate' graph target matches
  25 pts  'Average Payload Size' graph target matches
  25 pts  'Traffic Anomaly' graph target matches
"""

import json
import os
import re
import tempfile

DASHBOARD_NAME = "DDoS Threat Triage"
RESULT_PATH = "/tmp/volumetric_ddos_triage_dashboard_result.json"

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

def _strip_spaces(s):
    return re.sub(r'\s+', '', s.lower())

def verify_volumetric_ddos_triage_dashboard(trajectory, env_info, task_info):
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
            "feedback": (
                f"Dashboard '{DASHBOARD_NAME}' not found. "
                f"Present: {list(dashboards.keys())}"
            ),
        }
    score += 10
    feedback_parts.append(f"[+10] Dashboard '{DASHBOARD_NAME}' exists")

    dashboard_state = dashboards[DASHBOARD_NAME]
    if "parse_error" in dashboard_state:
        return {
            "passed": False,
            "score": score,
            "feedback": f"Dashboard JSON parse error: {dashboard_state['parse_error']}",
        }

    graphs = _get_graphs(dashboard_state)

    if len(graphs) >= 4:
        score += 10
        feedback_parts.append(f"[+10] Dashboard has {len(graphs)} graphs (>= 4)")
    else:
        feedback_parts.append(f"[-] Expected >= 4 graphs, found {len(graphs)}")

    vol_found = False
    bw_found = False
    payload_found = False
    anomaly_found = False

    for title, targets in graphs:
        t_title = title.lower()
        t_targets = [_strip_spaces(t) for t in targets]
        joined_targets = "".join(t_targets)

        # 1. Inbound Request Volume
        if "volume" in t_title and "request" in t_title and not vol_found:
            if "servers.load_balancer.requests.count" in joined_targets and "divide" not in joined_targets and "diff" not in joined_targets:
                score += 10
                feedback_parts.append("[+10] 'Inbound Request Volume' graph matches")
                vol_found = True
        
        # 2. Inbound Bandwidth Rate
        if "bandwidth" in t_title and "rate" in t_title and not bw_found:
            if "nonnegativederivative" in joined_targets and "servers.ec2_instance_1.network.bytes_in" in joined_targets and "divide" not in joined_targets:
                score += 20
                feedback_parts.append("[+20] 'Inbound Bandwidth Rate' graph matches")
                bw_found = True
        
        # 3. Average Payload Size
        if "payload" in t_title and "size" in t_title and not payload_found:
            if "divideseries" in joined_targets and "nonnegativederivative" in joined_targets and "bytes_in" in joined_targets and "requests.count" in joined_targets:
                score += 25
                feedback_parts.append("[+25] 'Average Payload Size' graph matches")
                payload_found = True

        # 4. Traffic Anomaly
        if "anomaly" in t_title and not anomaly_found:
            if "diffseries" in joined_targets and "movingaverage" in joined_targets and "requests.count" in joined_targets and "30" in joined_targets:
                score += 25
                feedback_parts.append("[+25] 'Traffic Anomaly' graph matches")
                anomaly_found = True

    if not vol_found: feedback_parts.append("[-] 'Inbound Request Volume' missing or incorrect")
    if not bw_found: feedback_parts.append("[-] 'Inbound Bandwidth Rate' missing or incorrect")
    if not payload_found: feedback_parts.append("[-] 'Average Payload Size' missing or incorrect")
    if not anomaly_found: feedback_parts.append("[-] 'Traffic Anomaly' missing or incorrect")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }