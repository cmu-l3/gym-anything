"""
Verifier for cross_tier_infrastructure_health task.

Scoring (100 pts, pass >= 60):
  10 pts  Dashboard 'Infrastructure Health' exists
  10 pts  Dashboard has >= 4 graphs
  15 pts  'EC2 Compute Tier' graph with EC2 CPU metric
  15 pts  'Database Tier' graph with RDS CPU metric
  20 pts  'Load Balancer Tier' graph with derivative(LB requests)
  15 pts  'Storage Tier' graph with disk write_bytes metric
  15 pts  All 4 graph titles exactly match expected names
"""

import json
import os
import tempfile

DASHBOARD_NAME = "Infrastructure Health"
RESULT_PATH = "/tmp/cross_tier_infrastructure_health_result.json"

EXPECTED_GRAPHS = {
    "EC2 Compute Tier": {
        "metric_keywords": ["ec2_instance", "cpu"],
        "description": "EC2 CPU metric",
    },
    "Database Tier": {
        "metric_keywords": ["rds_database", "cpu"],
        "description": "RDS CPU metric",
    },
    "Load Balancer Tier": {
        "metric_keywords": ["load_balancer", "requests"],
        "require_function": "derivative",
        "description": "derivative(LB requests)",
    },
    "Storage Tier": {
        "metric_keywords": ["disk", "write"],
        "description": "disk write_bytes metric",
    },
}


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


def _targets_contain(targets, keywords):
    """Return True if any target contains ALL keywords (case-insensitive)."""
    for t in targets:
        tl = t.lower()
        if all(kw.lower() in tl for kw in keywords):
            return True
    return False


def _find_graph_for_tier(graphs, expected_title, metric_keywords, require_function=None):
    """
    Find the best matching graph for a tier.
    Returns (found_exact_title, targets) or (False, None).
    """
    # Exact title match first
    for title, targets in graphs:
        if title == expected_title:
            if require_function:
                if _targets_contain(targets, [require_function] + metric_keywords):
                    return True, targets
                return True, targets  # title found but function may be missing
            return True, targets

    # Case-insensitive title match
    for title, targets in graphs:
        if expected_title.lower() in title.lower():
            return False, targets  # close title but not exact

    # Fall back: find by metric content
    for title, targets in graphs:
        if _targets_contain(targets, metric_keywords):
            return False, targets

    return False, None


def verify_cross_tier_infrastructure_health(trajectory, env_info, task_info):
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

    # ── Check 2: Has >= 4 graphs (10 pts) ─────────────────────────────────────
    if len(graphs) >= 4:
        score += 10
        details.append(f"[+10] Dashboard has {len(graphs)} graphs (>= 4)")
    else:
        details.append(f"[-] Expected >= 4 graphs, found {len(graphs)}")

    # ── Check 3-6: Each tier graph ────────────────────────────────────────────
    # Track exact title matches for the bonus
    exact_title_count = 0
    tier_scores = {
        "EC2 Compute Tier": 15,
        "Database Tier": 15,
        "Load Balancer Tier": 20,
        "Storage Tier": 15,
    }

    for tier_name, config in EXPECTED_GRAPHS.items():
        keywords = config["metric_keywords"]
        req_func = config.get("require_function")
        desc = config["description"]
        pts = tier_scores[tier_name]

        exact_match, tier_targets = _find_graph_for_tier(
            graphs, tier_name, keywords, req_func
        )

        if exact_match:
            exact_title_count += 1

        if tier_targets is None:
            details.append(f"[-] '{tier_name}' graph not found (no matching metrics)")
            continue

        # Check metric content
        has_metric = _targets_contain(tier_targets, keywords)

        if req_func:
            # Load Balancer: must use derivative()
            has_func = any(
                req_func.lower() in t.lower() and "load_balancer" in t.lower()
                for t in tier_targets
            )
            if has_func:
                score += pts
                details.append(f"[+{pts}] '{tier_name}': {desc} with {req_func}() found")
            elif has_metric:
                # Has the metric but missing derivative — partial points
                partial = pts // 2
                score += partial
                details.append(
                    f"[+{partial}] '{tier_name}': metric found but {req_func}() missing "
                    f"(partial credit)"
                )
            else:
                details.append(f"[-] '{tier_name}': neither {req_func}() nor metric found")
        else:
            if has_metric:
                score += pts
                details.append(f"[+{pts}] '{tier_name}': {desc} found")
            else:
                details.append(f"[-] '{tier_name}': {desc} not found in targets")

    # ── Check 7: All 4 titles exactly correct (15 pts) ────────────────────────
    if exact_title_count == 4:
        score += 15
        details.append("[+15] All 4 graph titles exactly match expected names")
    else:
        details.append(
            f"[-] Only {exact_title_count}/4 graph titles exactly matched "
            f"(case-sensitive)"
        )

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "details": "\n".join(details),
    }
