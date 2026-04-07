#!/usr/bin/env python3
"""
Verifier for production_slo_monitoring_pipeline task.

Stub verifier -- primary evaluation will be done via vlm_checklist_verifier.
This performs basic structural checks on the exported dashboard JSON and
metrics data to provide a baseline programmatic score.

Scoring (100 pts, pass >= 60):
  10 pts  Custom metrics fed (apps.payment.* exist in Render API data)
  10 pts  Dashboard 'Payment Service SLO' exists
  16 pts  Graph 'Request Rate' with summarize + threshold(800)
  18 pts  Graph 'Error Budget Burn' with integral + removeBelowValue + scale + threshold(100)
  16 pts  Graph 'Latency SLI' with movingAverage + threshold(500)
  16 pts  Graph 'Service Health Correlation' with secondYAxis + divideSeries
  14 pts  Graph 'Incident Detection' with diffSeries + drawAsInfinite + stdev
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

DASHBOARD_NAME = "Payment Service SLO"
RESULT_PATH = "/tmp/production_slo_monitoring_pipeline_result.json"


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
        graphs.append((title, [str(t).lower() for t in targets]))
    return graphs


def _find_graph(graphs, expected_title):
    """Find a graph by exact title, falling back to case-insensitive partial match."""
    for title, targets in graphs:
        if title == expected_title:
            return targets
    for title, targets in graphs:
        if expected_title.lower() in title.lower():
            return targets
    return None


def _targets_contain(targets, *keywords):
    """Check if joined target strings contain all keywords (case-insensitive)."""
    joined = " ".join(targets)
    return all(kw in joined for kw in keywords)


def verify_production_slo_monitoring_pipeline(trajectory, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    score = 0
    feedback = []

    # Load result file
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
    if isinstance(metrics_data, dict):
        metrics_data = []

    # --- Check 1: Custom metrics fed (10 pts) ---
    found_metrics = set()
    for series in metrics_data:
        target = series.get("target", "")
        datapoints = [p[0] for p in series.get("datapoints", []) if p[0] is not None]
        if datapoints:
            if "requests_per_sec" in target:
                found_metrics.add("rps")
            elif "error_rate" in target:
                found_metrics.add("err")
            elif "latency_p99_ms" in target:
                found_metrics.add("lat")

    if len(found_metrics) >= 3:
        score += 10
        feedback.append("[+10] All 3 custom metrics have data")
    elif len(found_metrics) > 0:
        score += 5
        feedback.append(f"[+5] {len(found_metrics)}/3 custom metrics have data")
    else:
        feedback.append("[-] No custom metrics found in Render API data")

    # --- Check 2: Dashboard exists (10 pts) ---
    if DASHBOARD_NAME not in dashboards:
        feedback.append(f"[-] Dashboard '{DASHBOARD_NAME}' not found. Present: {list(dashboards.keys())}")
        return {"passed": False, "score": score, "feedback": "\n".join(feedback)}

    score += 10
    feedback.append(f"[+10] Dashboard '{DASHBOARD_NAME}' exists")

    dashboard_state = dashboards[DASHBOARD_NAME]
    if "parse_error" in dashboard_state:
        feedback.append(f"[-] Dashboard JSON parse error: {dashboard_state['parse_error']}")
        return {"passed": False, "score": score, "feedback": "\n".join(feedback)}

    graphs = _get_graphs(dashboard_state)

    # --- Check 3: Graph 'Request Rate' (16 pts) ---
    g1 = _find_graph(graphs, "Request Rate")
    if g1 is not None:
        if _targets_contain(g1, "summarize", "requests_per_sec"):
            score += 10
            feedback.append("[+10] 'Request Rate' has summarize on requests_per_sec")
        else:
            score += 3
            feedback.append("[+3] 'Request Rate' graph exists but targets incomplete")
        if _targets_contain(g1, "threshold(800"):
            score += 6
            feedback.append("[+6] 'Request Rate' has threshold(800)")
    else:
        feedback.append("[-] Graph 'Request Rate' not found")

    # --- Check 4: Graph 'Error Budget Burn' (18 pts) ---
    g2 = _find_graph(graphs, "Error Budget Burn")
    if g2 is not None:
        if _targets_contain(g2, "integral", "removebelowvalue", "scale"):
            score += 12
            feedback.append("[+12] 'Error Budget Burn' has integral+removeBelowValue+scale chain")
        else:
            score += 3
            feedback.append("[+3] 'Error Budget Burn' graph exists but targets incomplete")
        if _targets_contain(g2, "threshold(100"):
            score += 6
            feedback.append("[+6] 'Error Budget Burn' has threshold(100)")
    else:
        feedback.append("[-] Graph 'Error Budget Burn' not found")

    # --- Check 5: Graph 'Latency SLI' (16 pts) ---
    g3 = _find_graph(graphs, "Latency SLI")
    if g3 is not None:
        pts = 0
        if _targets_contain(g3, "latency_p99_ms"):
            pts += 4
        if _targets_contain(g3, "movingaverage"):
            pts += 6
        if _targets_contain(g3, "threshold(500"):
            pts += 6
        score += pts
        if pts > 0:
            feedback.append(f"[+{pts}] 'Latency SLI' partial match")
        else:
            feedback.append("[+0] 'Latency SLI' graph exists but no matching targets")
    else:
        feedback.append("[-] Graph 'Latency SLI' not found")

    # --- Check 6: Graph 'Service Health Correlation' (16 pts) ---
    g4 = _find_graph(graphs, "Service Health Correlation")
    if g4 is not None:
        pts = 0
        if _targets_contain(g4, "scale", "error_rate"):
            pts += 6
        if _targets_contain(g4, "secondyaxis", "divideseries"):
            pts += 10
        score += pts
        if pts > 0:
            feedback.append(f"[+{pts}] 'Service Health Correlation' partial match")
        else:
            feedback.append("[+0] 'Service Health Correlation' graph exists but no matching targets")
    else:
        feedback.append("[-] Graph 'Service Health Correlation' not found")

    # --- Check 7: Graph 'Incident Detection' (14 pts) ---
    g5 = _find_graph(graphs, "Incident Detection")
    if g5 is not None:
        pts = 0
        if _targets_contain(g5, "diffseries", "movingaverage"):
            pts += 5
        if _targets_contain(g5, "drawasinfinite", "removebelowvalue"):
            pts += 5
        if _targets_contain(g5, "stdev"):
            pts += 4
        score += pts
        if pts > 0:
            feedback.append(f"[+{pts}] 'Incident Detection' partial match")
        else:
            feedback.append("[+0] 'Incident Detection' graph exists but no matching targets")
    else:
        feedback.append("[-] Graph 'Incident Detection' not found")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }
