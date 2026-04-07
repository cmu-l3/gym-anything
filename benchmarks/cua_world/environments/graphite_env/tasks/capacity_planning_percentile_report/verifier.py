"""
Verifier for capacity_planning_percentile_report task.

Scoring (100 pts, pass >= 60):
  15 pts  Dashboard 'Capacity Planning Q4' exists
  10 pts  Dashboard has >= 2 graphs
  15 pts  Graph 'P95 CPU Utilization' found
  20 pts  percentileOfSeries target with ec2_instance wildcard
  10 pts  Percentile value is 95 (not 90, 99, etc.)
  15 pts  Graph 'CPU Variability' found
  15 pts  stddevSeries target with ec2_instance wildcard
"""

import json
import os
import re
import tempfile

DASHBOARD_NAME = "Capacity Planning Q4"
RESULT_PATH = "/tmp/capacity_planning_percentile_report_result.json"

P95_GRAPH_TITLE = "P95 CPU Utilization"
STDDEV_GRAPH_TITLE = "CPU Variability"


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


def _has_ec2_wildcard(targets):
    """Check if any target uses ec2_instance wildcard for CPU metrics."""
    for t in targets:
        tl = t.lower()
        if "ec2_instance_*" in tl or "ec2_instance_?" in tl:
            return True
        # Also accept multiple explicit ec2_instance targets (agent enumerated them)
        if "ec2_instance_1" in tl and "ec2_instance_2" in tl:
            return True
    return False


def verify_capacity_planning_percentile_report(trajectory, env_info, task_info):
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

    # ── Check 2: Has >= 2 graphs (10 pts) ─────────────────────────────────────
    if len(graphs) < 2:
        details.append(f"[-] Expected >= 2 graphs, found {len(graphs)}")
        if not graphs:
            return {"passed": False, "score": score, "details": "\n".join(details)}
    else:
        score += 10
        details.append(f"[+10] Dashboard has {len(graphs)} graph(s)")

    # ── Check 3: P95 graph title (15 pts) ─────────────────────────────────────
    p95_match = _find_graph(graphs, P95_GRAPH_TITLE)
    if p95_match:
        p95_title, p95_targets = p95_match
        score += 15
        if p95_title == P95_GRAPH_TITLE:
            details.append(f"[+15] Graph '{P95_GRAPH_TITLE}' found (exact)")
        else:
            details.append(f"[+15] Graph '{P95_GRAPH_TITLE}' found (matched '{p95_title}')")
    else:
        details.append(f"[-] Graph '{P95_GRAPH_TITLE}' not found")
        # Attempt to find by function content
        p95_targets = None
        for title, targets in graphs:
            if any("percentile" in t.lower() for t in targets):
                p95_targets = targets
                details.append(f"  (Using graph '{title}' for P95 checks)")
                break

    # ── Check 4: percentileOfSeries with ec2 wildcard (20 pts) ────────────────
    if p95_targets is not None:
        has_percentile_func = any(
            "percentileofseries" in t.lower() and "ec2_instance" in t.lower()
            for t in p95_targets
        )
        if has_percentile_func:
            score += 20
            details.append("[+20] percentileOfSeries with ec2_instance metrics found")
        else:
            details.append("[-] No percentileOfSeries(ec2_instance) target found")

        # ── Check 5: Percentile value = 95 (10 pts) ───────────────────────────
        percentile_95 = False
        for t in p95_targets:
            if "percentile" not in t.lower():
                continue
            # Match , 95) or ,95) with optional quotes
            if re.search(r',\s*["\']?95["\']?\s*[,)]', t, re.IGNORECASE):
                percentile_95 = True
                break
        if percentile_95:
            score += 10
            details.append("[+10] Percentile value confirmed as 95")
        else:
            details.append("[-] Percentile value 95 not confirmed in target syntax")
    else:
        details.append("[-] Skipping P95 function checks (no graph found)")

    # ── Check 6: CPU Variability graph title (15 pts) ─────────────────────────
    stddev_match = _find_graph(graphs, STDDEV_GRAPH_TITLE)
    if stddev_match:
        stddev_title, stddev_targets = stddev_match
        score += 15
        if stddev_title == STDDEV_GRAPH_TITLE:
            details.append(f"[+15] Graph '{STDDEV_GRAPH_TITLE}' found (exact)")
        else:
            details.append(f"[+15] Graph '{STDDEV_GRAPH_TITLE}' found (matched '{stddev_title}')")
    else:
        details.append(f"[-] Graph '{STDDEV_GRAPH_TITLE}' not found")
        stddev_targets = None
        for title, targets in graphs:
            if any("stddev" in t.lower() for t in targets):
                stddev_targets = targets
                details.append(f"  (Using graph '{title}' for stddev checks)")
                break

    # ── Check 7: stddevSeries with ec2 metrics (15 pts) ───────────────────────
    if stddev_targets is not None:
        has_stddev = any(
            "stddevseries" in t.lower() and "ec2_instance" in t.lower()
            for t in stddev_targets
        )
        if has_stddev:
            score += 15
            details.append("[+15] stddevSeries with ec2_instance metrics found")
        else:
            details.append("[-] No stddevSeries(ec2_instance) target found")
    else:
        details.append("[-] Skipping stddev checks (no graph found)")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "details": "\n".join(details),
    }
