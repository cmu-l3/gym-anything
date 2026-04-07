#!/usr/bin/env python3
"""
Verifier for synthetic_monitoring_pipeline task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/synthetic_monitoring_pipeline_result.json"

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

def verify_synthetic_monitoring_pipeline(trajectory, env_info, task_info):
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
    metrics_data = result.get("metrics_data", [])

    if isinstance(metrics_data, dict) and "error" in metrics_data:
        metrics_data = []

    response_time_data = []
    error_rate_data = []
    requests_data = []

    for series in metrics_data:
        target = series.get("target", "")
        # Filter out nulls
        datapoints = [p[0] for p in series.get("datapoints", []) if p[0] is not None]
        if "response_time_ms" in target:
            response_time_data.extend(datapoints)
        elif "error_rate" in target:
            error_rate_data.extend(datapoints)
        elif "requests_per_sec" in target:
            requests_data.extend(datapoints)

    # 1. Custom metric existence (7 points each)
    if response_time_data or any("response_time_ms" in s.get("target", "") for s in metrics_data):
        score += 7
        feedback_parts.append("[+7] response_time_ms metric exists")
    else:
        feedback_parts.append("[-] response_time_ms metric not found")

    if error_rate_data or any("error_rate" in s.get("target", "") for s in metrics_data):
        score += 7
        feedback_parts.append("[+7] error_rate metric exists")
    else:
        feedback_parts.append("[-] error_rate metric not found")

    if requests_data or any("requests_per_sec" in s.get("target", "") for s in metrics_data):
        score += 7
        feedback_parts.append("[+7] requests_per_sec metric exists")
    else:
        feedback_parts.append("[-] requests_per_sec metric not found")

    # 2. Data value check (Proof the agent sent the real specified values)
    if any(v > 500 for v in response_time_data):
        score += 7
        feedback_parts.append("[+7] response_time_ms spike > 500 found (Correct data sent)")
    if any(v > 0.1 for v in error_rate_data):
        score += 7
        feedback_parts.append("[+7] error_rate spike > 0.1 found (Correct data sent)")
    if len(requests_data) > 0:
        score += 5
        feedback_parts.append("[+5] requests_per_sec contains data points")

    # 3. Dashboard structure evaluation
    db_name = "Payment Service Health"
    if db_name in dashboards:
        score += 10
        feedback_parts.append(f"[+10] Dashboard '{db_name}' exists")
        db_state = dashboards[db_name]
        
        graphs = _get_graphs(db_state)
        if len(graphs) >= 3:
            score += 5
            feedback_parts.append(f"[+5] Dashboard has {len(graphs)} graphs")
            
        g1 = _find_graph(graphs, "Response Time vs Errors")
        if g1:
            score += 8
            feedback_parts.append("[+8] Graph 'Response Time vs Errors' found")
            t_str = " ".join(g1[1]).lower()
            if "response_time_ms" in t_str and "error_rate" in t_str:
                score += 10
                feedback_parts.append("[+10] Graph 1 contains both custom metrics")
                
        g2 = _find_graph(graphs, "Throughput")
        if g2:
            score += 5
            feedback_parts.append("[+5] Graph 'Throughput' found")
            if "requests_per_sec" in " ".join(g2[1]).lower():
                score += 5
                feedback_parts.append("[+5] Graph 2 contains requests_per_sec target")
                
        g3 = _find_graph(graphs, "Infrastructure Correlation")
        if g3:
            score += 7
            feedback_parts.append("[+7] Graph 'Infrastructure Correlation' found")
            t_str = " ".join(g3[1]).lower()
            if "response_time_ms" in t_str and "ec2_instance_1" in t_str and "cpu" in t_str:
                score += 10
                feedback_parts.append("[+10] Graph 3 contains correlation targets")
                
    else:
        feedback_parts.append(f"[-] Dashboard '{db_name}' not found")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }