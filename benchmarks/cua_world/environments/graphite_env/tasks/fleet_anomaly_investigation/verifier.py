"""
Verifier for fleet_anomaly_investigation task.

Scoring (100 pts, pass >= 60):
  15 pts  Dashboard 'SRE Incident Response' exists
   5 pts  Dashboard has >= 1 graph
  15 pts  Graph titled 'EC2 Fleet CPU Correlation' found
  10 pts  movingAverage target for ec2_instance_1.cpu.utilization
  10 pts  movingAverage target for ec2_instance_2.cpu.utilization
  10 pts  movingAverage target for ec2_instance_3.cpu.cloudwatch_utilization
  20 pts  averageSeries target covering EC2 fleet CPU metrics
  15 pts  movingAverage window is exactly 10
"""

import json
import os
import re
import tempfile

DASHBOARD_NAME = "SRE Incident Response"
GRAPH_TITLE = "EC2 Fleet CPU Correlation"
RESULT_PATH = "/tmp/fleet_anomaly_investigation_result.json"

EC2_INSTANCE_CHECKS = [
    ("ec2_instance_1.cpu.utilization", "ec2_instance_1"),
    ("ec2_instance_2.cpu.utilization", "ec2_instance_2"),
    ("ec2_instance_3.cpu.cloudwatch_utilization", "ec2_instance_3 (cloudwatch)"),
]


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


def _targets_str(targets):
    """Join all targets into one lowercase string for broad substring search."""
    return " ".join(targets).lower()


def verify_fleet_anomaly_investigation(trajectory, env_info, task_info):
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
                f"Dashboards present: {list(dashboards.keys())}"
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

    # ── Check 2: Has at least 1 graph (5 pts) ─────────────────────────────────
    if not graphs:
        details.append("[-] No graphs in dashboard")
        return {"passed": False, "score": score, "details": "\n".join(details)}
    score += 5
    details.append(f"[+5] Dashboard contains {len(graphs)} graph(s)")

    # ── Check 3: Find graph with correct title (15 pts) ───────────────────────
    # Try exact match first, then case-insensitive
    target_targets = None
    for title, targets in graphs:
        if title == GRAPH_TITLE:
            target_targets = targets
            score += 15
            details.append(f"[+15] Graph titled '{GRAPH_TITLE}' found (exact match)")
            break
    if target_targets is None:
        for title, targets in graphs:
            if GRAPH_TITLE.lower() in title.lower():
                target_targets = targets
                score += 15
                details.append(f"[+15] Graph titled '{GRAPH_TITLE}' found (case-insensitive match: '{title}')")
                break
    if target_targets is None:
        details.append(f"[-] No graph with title '{GRAPH_TITLE}' found")
        # Fall back to first graph that contains EC2 metrics for partial credit
        for title, targets in graphs:
            if "ec2_instance" in _targets_str(targets):
                target_targets = targets
                details.append(f"  (Using graph '{title}' for remaining checks)")
                break

    if target_targets is None:
        return {"passed": False, "score": score, "details": "\n".join(details)}

    ts = _targets_str(target_targets)

    # ── Check 4: movingAverage targets for each EC2 instance (10 pts each) ───
    has_moving_avg = "movingaverage" in ts
    for metric_suffix, label in EC2_INSTANCE_CHECKS:
        # Accept: individual metric OR wildcard that covers this instance
        # Wildcard ec2_instance_* covers instances 1,2,3 but NOT the cloudwatch suffix
        found = False
        for t in target_targets:
            tl = t.lower()
            if "movingaverage" not in tl:
                continue
            # Direct metric reference
            if metric_suffix.lower() in tl:
                found = True
                break
            # Wildcard covering numeric instances (only for non-cloudwatch)
            if "cloudwatch" not in metric_suffix and (
                "ec2_instance_*.cpu.utilization" in tl
                or "ec2_instance_?.cpu.utilization" in tl
            ):
                found = True
                break
        if found:
            score += 10
            details.append(f"[+10] movingAverage target for {label}")
        else:
            details.append(f"[-] No movingAverage target for {label}")

    # ── Check 5: averageSeries fleet baseline (20 pts) ────────────────────────
    avg_found = any(
        "averageseries" in t.lower() and "ec2_instance" in t.lower()
        for t in target_targets
    )
    if avg_found:
        score += 20
        details.append("[+20] averageSeries fleet baseline target found")
    else:
        details.append("[-] No averageSeries target covering EC2 fleet")

    # ── Check 6: movingAverage window = 10 (15 pts) ───────────────────────────
    window_ok = False
    for t in target_targets:
        # Match movingAverage(..., 10) with optional spaces and optional quotes
        if re.search(r'movingAverage\s*\(.*?,\s*["\']?10["\']?\s*\)', t, re.IGNORECASE):
            window_ok = True
            break
        # Also catch compact form: ...,10) with no space
        if re.search(r'movingaverage', t.lower()) and re.search(r',\s*["\']?10["\']?\s*\)', t, re.IGNORECASE):
            window_ok = True
            break
    if window_ok:
        score += 15
        details.append("[+15] movingAverage window of 10 confirmed")
    else:
        details.append("[-] movingAverage window of 10 not confirmed (check target syntax)")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "details": "\n".join(details),
    }
