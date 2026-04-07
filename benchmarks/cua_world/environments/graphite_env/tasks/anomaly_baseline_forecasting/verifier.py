"""
Verifier for anomaly_baseline_forecasting task.

Scoring (100 pts, pass >= 60):
  15 pts  Dashboard 'Anomaly Detection' exists
   5 pts  Dashboard has >= 1 graph
  15 pts  Graph 'Holt-Winters CPU Forecast' found
  30 pts  holtWintersForecast(servers.ec2_instance_2.cpu.utilization) target
  30 pts  holtWintersConfidenceBands(servers.ec2_instance_2.cpu.utilization) target
   5 pts  Both forecast AND confidence bands present (completeness bonus)
"""

import json
import os
import tempfile

DASHBOARD_NAME = "Anomaly Detection"
GRAPH_TITLE = "Holt-Winters CPU Forecast"
TARGET_METRIC = "ec2_instance_2.cpu.utilization"
RESULT_PATH = "/tmp/anomaly_baseline_forecasting_result.json"


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


def _has_hw_target(targets, function_name, metric_suffix):
    """
    Check if any target calls function_name() with a metric containing metric_suffix.
    Case-insensitive function name, exact metric suffix match.
    """
    fn_lower = function_name.lower()
    for t in targets:
        tl = t.lower()
        if fn_lower in tl and metric_suffix.lower() in tl:
            return True
    return False


def verify_anomaly_baseline_forecasting(trajectory, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "details": "copy_from_env unavailable"}
    result_path = RESULT_PATH

    score = 0
    details = []

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
            "details": f"Could not load result file: {e}",
        }

    dashboards = result.get("dashboards", {})

    # ── Check 1: Dashboard exists (15 pts) ────────────────────────────────────
    if DASHBOARD_NAME not in dashboards:
        return {
            "passed": False,
            "score": 0,
            "details": (
                f"Dashboard '{DASHBOARD_NAME}' not found. "
                f"Present: {list(dashboards.keys())}"
            ),
        }
    score += 15
    details.append(f"[+15] Dashboard '{DASHBOARD_NAME}' exists")

    dashboard_state = dashboards[DASHBOARD_NAME]
    if "parse_error" in dashboard_state:
        return {
            "passed": False,
            "score": score,
            "details": f"Dashboard JSON parse error: {dashboard_state['parse_error']}",
        }

    graphs = _get_graphs(dashboard_state)

    # ── Check 2: Has >= 1 graph (5 pts) ──────────────────────────────────────
    if not graphs:
        details.append("[-] No graphs in dashboard")
        return {"passed": False, "score": score, "details": "\n".join(details)}
    score += 5
    details.append(f"[+5] Dashboard has {len(graphs)} graph(s)")

    # ── Check 3: Find graph with correct title (15 pts) ───────────────────────
    hw_targets = None
    for title, targets in graphs:
        if title == GRAPH_TITLE:
            hw_targets = targets
            score += 15
            details.append(f"[+15] Graph '{GRAPH_TITLE}' found (exact match)")
            break
    if hw_targets is None:
        for title, targets in graphs:
            if GRAPH_TITLE.lower() in title.lower():
                hw_targets = targets
                score += 15
                details.append(f"[+15] Graph '{GRAPH_TITLE}' found (matched '{title}')")
                break
    if hw_targets is None:
        details.append(f"[-] No graph with title '{GRAPH_TITLE}' found")
        # Try to find by Holt-Winters function content
        for title, targets in graphs:
            if any("holtwinters" in t.lower() for t in targets):
                hw_targets = targets
                details.append(f"  (Using graph '{title}' for Holt-Winters checks)")
                break

    if hw_targets is None:
        return {"passed": False, "score": score, "details": "\n".join(details)}

    # ── Check 4: holtWintersForecast for ec2_instance_2 (30 pts) ─────────────
    has_forecast = _has_hw_target(hw_targets, "holtWintersForecast", TARGET_METRIC)
    if has_forecast:
        score += 30
        details.append(f"[+30] holtWintersForecast({TARGET_METRIC}) target found")
    else:
        # Check if they used the function but on wrong instance
        for t in hw_targets:
            if "holtwinters" in t.lower() and "forecast" in t.lower():
                if "ec2_instance" in t.lower():
                    details.append(
                        f"[-] holtWintersForecast found but NOT targeting {TARGET_METRIC}"
                        f" (found: {t})"
                    )
                else:
                    details.append(f"[-] holtWintersForecast found but no EC2 metric: {t}")
                break
        else:
            details.append("[-] No holtWintersForecast target found")

    # ── Check 5: holtWintersConfidenceBands for ec2_instance_2 (30 pts) ──────
    has_bands = _has_hw_target(hw_targets, "holtWintersConfidenceBands", TARGET_METRIC)
    if has_bands:
        score += 30
        details.append(f"[+30] holtWintersConfidenceBands({TARGET_METRIC}) target found")
    else:
        for t in hw_targets:
            if "holtwinters" in t.lower() and "confidence" in t.lower():
                if "ec2_instance" in t.lower():
                    details.append(
                        f"[-] holtWintersConfidenceBands found but NOT targeting {TARGET_METRIC}"
                        f" (found: {t})"
                    )
                else:
                    details.append(
                        f"[-] holtWintersConfidenceBands found but no EC2 metric: {t}"
                    )
                break
        else:
            details.append("[-] No holtWintersConfidenceBands target found")

    # ── Check 6: Both present (5 pt bonus) ───────────────────────────────────
    if has_forecast and has_bands:
        score += 5
        details.append("[+5] Both Holt-Winters forecast and confidence bands present")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "details": "\n".join(details),
    }
