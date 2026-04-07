#!/usr/bin/env python3
"""
Verifier for post_incident_timeline task.

Scoring (100 pts, pass >= 60):
  10 pts  Dashboard 'Post-Incident Review' exists
   5 pts  Dashboard has >= 3 graphs
  10 pts  Graph 'Hourly Peak CPU' found
  15 pts  summarize(..., '1h', 'max') in CPU targets
  10 pts  aliasByNode in CPU targets
   5 pts  All 3 EC2 instances referenced in CPU targets
  10 pts  Graph 'Gap-Filled Temperature' found
  15 pts  keepLastValue(..., 5) with machine_temperature metric
  10 pts  Graph 'Request Rate Summary' found
  10 pts  alias(summarize(derivative(load_balancer... in rate target
"""

import json
import os
import tempfile

DASHBOARD_NAME = "Post-Incident Review"
RESULT_PATH = "/tmp/post_incident_timeline_result.json"

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

def verify_post_incident_timeline(trajectory, env_info, task_info):
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
    feedback_parts.append(f"[+10] Dashboard '{DASHBOARD_NAME}' exists")

    dashboard_state = dashboards[DASHBOARD_NAME]
    if "parse_error" in dashboard_state:
        return {"passed": False, "score": score, "feedback": f"Dashboard JSON parse error: {dashboard_state['parse_error']}"}

    graphs = _get_graphs(dashboard_state)

    if len(graphs) >= 3:
        score += 5
        feedback_parts.append(f"[+5] Dashboard has {len(graphs)} graphs")
    else:
        feedback_parts.append(f"[-] Dashboard has {len(graphs)} graphs (expected >= 3)")

    # Check Hourly Peak CPU
    cpu_match = _find_graph(graphs, "Hourly Peak CPU")
    if cpu_match:
        cpu_title, cpu_targets = cpu_match
        score += 10
        feedback_parts.append("[+10] Graph 'Hourly Peak CPU' found")
        
        has_summarize = False
        has_alias = False
        instances = set()
        for t in cpu_targets:
            tl = t.lower()
            if "summarize" in tl and "1h" in tl and "max" in tl:
                has_summarize = True
            if "aliasbynode" in tl:
                has_alias = True
            if "ec2_instance_1" in tl:
                instances.add(1)
            if "ec2_instance_2" in tl:
                instances.add(2)
            if "ec2_instance_3" in tl:
                instances.add(3)

        if has_summarize:
            score += 15
            feedback_parts.append("[+15] CPU graph uses summarize('1h', 'max')")
        else:
            feedback_parts.append("[-] CPU graph missing correct summarize function")
            
        if has_alias:
            score += 10
            feedback_parts.append("[+10] CPU graph uses aliasByNode")
        else:
            feedback_parts.append("[-] CPU graph missing aliasByNode")
            
        if len(instances) == 3:
            score += 5
            feedback_parts.append("[+5] All 3 EC2 instances targeted")
        else:
            feedback_parts.append(f"[-] Only {len(instances)} EC2 instances targeted")
    else:
        feedback_parts.append("[-] Graph 'Hourly Peak CPU' not found")

    # Check Gap-Filled Temperature
    temp_match = _find_graph(graphs, "Gap-Filled Temperature")
    if temp_match:
        temp_title, temp_targets = temp_match
        score += 10
        feedback_parts.append("[+10] Graph 'Gap-Filled Temperature' found")
        
        has_keep = False
        for t in temp_targets:
            tl = t.lower()
            if "keeplastvalue" in tl and "machine_temperature" in tl:
                has_keep = True
                break
        
        if has_keep:
            score += 15
            feedback_parts.append("[+15] Temperature graph uses keepLastValue")
        else:
            feedback_parts.append("[-] Temperature graph missing keepLastValue with correct metric")
    else:
        feedback_parts.append("[-] Graph 'Gap-Filled Temperature' not found")

    # Check Request Rate Summary
    rate_match = _find_graph(graphs, "Request Rate Summary")
    if rate_match:
        rate_title, rate_targets = rate_match
        score += 10
        feedback_parts.append("[+10] Graph 'Request Rate Summary' found")
        
        has_rate_logic = False
        for t in rate_targets:
            tl = t.lower()
            if "summarize" in tl and "derivative" in tl and "load_balancer" in tl:
                has_rate_logic = True
                break
        
        if has_rate_logic:
            score += 10
            feedback_parts.append("[+10] Rate graph uses summarize(derivative(...))")
        else:
            feedback_parts.append("[-] Rate graph missing summarize or derivative functions")
    else:
        feedback_parts.append("[-] Graph 'Request Rate Summary' not found")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }