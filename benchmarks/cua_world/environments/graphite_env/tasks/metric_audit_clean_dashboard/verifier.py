"""
Verifier for metric_audit_clean_dashboard task.

Scoring (100 pts, pass >= 60):
  10 pts  Dashboard 'Validated Production Metrics' exists
   5 pts  Dashboard has >= 1 graph
  10 pts  ec2_instance_1.cpu.utilization present in any graph target
  10 pts  ec2_instance_2.cpu.utilization present in any graph target
  10 pts  ec2_instance_3.cpu.cloudwatch_utilization present in any graph target

  Absence criteria — GATED: awarded only if ALL 3 valid metrics confirmed above:
  20 pts  No UNKNOWN_HOST metric in any target
  15 pts  No ec2_instance_99 metric in any target
  20 pts  No test_node metric in any target

Anti-gaming note: Absence criteria are only awarded when all 3 valid metrics
are present, preventing an empty dashboard from trivially passing absence checks.
Wildcards that could expand to contaminated metrics are treated as potential
contamination for ec2_instance_99 checks.
"""

import json
import os
import tempfile

DASHBOARD_NAME = "Validated Production Metrics"
RESULT_PATH = "/tmp/metric_audit_clean_dashboard_result.json"

VALID_METRICS = [
    ("ec2_instance_1.cpu.utilization", "ec2_instance_1.cpu.utilization"),
    ("ec2_instance_2.cpu.utilization", "ec2_instance_2.cpu.utilization"),
    ("ec2_instance_3.cpu.cloudwatch_utilization", "ec2_instance_3.cpu.cloudwatch_utilization"),
]

CONTAMINATION_PATTERNS = [
    ("UNKNOWN_HOST", "UNKNOWN_HOST", 20),
    ("ec2_instance_99", "ec2_instance_99", 15),
    ("test_node", "test_node", 20),
]


def _get_all_targets(dashboard_state):
    """Collect all target strings from all graphs in the dashboard."""
    all_targets = []
    for entry in dashboard_state.get("graphs", []):
        if not isinstance(entry, (list, tuple)) or len(entry) < 2:
            continue
        params = entry[1] if isinstance(entry[1], dict) else {}
        targets = params.get("target", [])
        if isinstance(targets, str):
            targets = [targets]
        all_targets.extend(str(t) for t in targets)
    return all_targets


def _get_graphs(dashboard_state):
    """Return list of (title, targets_list) from dashboard state dict."""
    graphs = []
    for entry in dashboard_state.get("graphs", []):
        if not isinstance(entry, (list, tuple)) or len(entry) < 2:
            continue
        params = entry[1] if isinstance(entry[1], dict) else {}
        title = params.get("title", "")
        targets = params.get("target", [])
        if isinstance(targets, str):
            targets = [targets]
        graphs.append((title, [str(t) for t in targets]))
    return graphs


def _wildcard_could_match_contaminated(target):
    """
    Detect wildcards like ec2_instance_* that would expand to include ec2_instance_99.
    Returns True if the wildcard is broad enough to capture contaminated instances.
    """
    tl = target.lower()
    if "ec2_instance_*" in tl or "ec2_instance_?" in tl:
        # Wildcard covers all instances including _99
        return True
    return False


def verify_metric_audit_clean_dashboard(trajectory, env_info, task_info):
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

    # ── Check 1: Dashboard exists (10 pts) ────────────────────────────────────
    if DASHBOARD_NAME not in dashboards:
        return {
            "passed": False,
            "score": 0,
            "details": (
                f"Dashboard '{DASHBOARD_NAME}' not found. "
                f"Present: {list(dashboards.keys())}"
            ),
        }
    score += 10
    details.append(f"[+10] Dashboard '{DASHBOARD_NAME}' exists")

    dashboard_state = dashboards[DASHBOARD_NAME]
    if "parse_error" in dashboard_state:
        return {
            "passed": False,
            "score": score,
            "details": f"Dashboard JSON parse error: {dashboard_state['parse_error']}",
        }

    graphs = _get_graphs(dashboard_state)
    all_targets = _get_all_targets(dashboard_state)

    # ── Check 2: Has >= 1 graph (5 pts) ──────────────────────────────────────
    if not graphs:
        details.append("[-] No graphs in dashboard")
        return {"passed": False, "score": score, "details": "\n".join(details)}
    score += 5
    details.append(f"[+5] Dashboard has {len(graphs)} graph(s)")

    # ── Checks 3-5: Valid metrics present (10 pts each) ───────────────────────
    valid_count = 0
    for metric_suffix, label in VALID_METRICS:
        found = any(metric_suffix.lower() in t.lower() for t in all_targets)
        if found:
            score += 10
            valid_count += 1
            details.append(f"[+10] Legitimate metric '{metric_suffix}' present")
        else:
            details.append(f"[-] Legitimate metric '{metric_suffix}' NOT found in any target")

    all_valid_present = (valid_count == 3)

    # ── Checks 6-8: Absence criteria (GATED on all 3 valid present) ──────────
    if not all_valid_present:
        details.append(
            f"[!] Absence checks SKIPPED — only {valid_count}/3 valid metrics found. "
            f"Absence criteria require all 3 valid metrics to prevent gaming."
        )
    else:
        details.append("[!] All 3 valid metrics present — evaluating absence criteria:")

        for pattern, label, pts in CONTAMINATION_PATTERNS:
            # Check if any target contains this contamination pattern
            contaminated = False
            contaminated_targets = []

            for t in all_targets:
                tl = t.lower()
                if pattern.lower() in tl:
                    contaminated = True
                    contaminated_targets.append(t)
                # Special case: wildcards that could expand to ec2_instance_99
                elif pattern == "ec2_instance_99" and _wildcard_could_match_contaminated(t):
                    contaminated = True
                    contaminated_targets.append(f"[wildcard: {t}]")

            if contaminated:
                details.append(
                    f"[-] CONTAMINATION DETECTED: '{pattern}' found in targets: "
                    f"{contaminated_targets}"
                )
            else:
                score += pts
                details.append(f"[+{pts}] '{pattern}' correctly excluded from all targets")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "details": "\n".join(details),
    }
