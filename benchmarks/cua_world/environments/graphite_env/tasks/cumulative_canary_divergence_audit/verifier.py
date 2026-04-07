"""
Verifier for cumulative_canary_divergence_audit task.

Scoring (100 pts, pass >= 60):
  10 pts  Dashboard 'Canary Release Audit' exists
  10 pts  Dashboard has >= 3 graphs
  10 pts  Baseline graph: Legacy Avg correctly targets instances 1 and 2
  10 pts  Baseline graph: Canary correctly targets instance 3
  20 pts  Delta graph: Nests diffSeries(Canary, averageSeries(Legacy))
  25 pts  Penalty graph: Wraps the exact Delta logic inside integral()
  15 pts  All 4 targets across the 3 graphs possess the exact requested alias() labels
"""

import json
import os
import tempfile
import re

DASHBOARD_NAME = "Canary Release Audit"
RESULT_PATH = "/tmp/cumulative_canary_divergence_audit_result.json"

EXPECTED_ALIASES = [
    "legacyfleet",
    "canarynode",
    "instantaneousdelta",
    "netcumulativepenalty"
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

def _clean_target(t):
    """Removes spaces and makes string lowercase for robust checking."""
    return t.lower().replace(" ", "")

def _has_canary(t_clean):
    """Checks if target includes instance 3."""
    return "ec2_instance_3.cpu.cloudwatch_utilization" in t_clean

def _has_legacy_avg(t_clean):
    """Checks if target includes averageSeries of instances 1 and 2 exclusively."""
    if "averageseries(" not in t_clean:
        return False
    
    # Must explicitly mention 1 and 2
    has_1_and_2 = ("ec2_instance_1.cpu.utilization" in t_clean and "ec2_instance_2.cpu.utilization" in t_clean)
    has_brace_expansion = "ec2_instance_{1,2}.cpu.utilization" in t_clean or "ec2_instance_{2,1}.cpu.utilization" in t_clean
    
    # Must NOT mention 3 inside the average series or use broad wildcards
    has_broad_wildcard = "ec2_instance_*" in t_clean or "ec2_instance_?" in t_clean
    
    return (has_1_and_2 or has_brace_expansion) and not has_broad_wildcard

def _is_valid_delta(t_clean):
    """Checks if diffSeries subtracts legacy average from canary."""
    if "diffseries(" not in t_clean:
        return False
    
    # Must have both components
    if not _has_canary(t_clean) or not _has_legacy_avg(t_clean):
        return False
        
    # Canary must come BEFORE legacy average to subtract properly (Canary - Legacy)
    canary_idx = t_clean.find("ec2_instance_3")
    avg_idx = t_clean.find("averageseries")
    
    return canary_idx < avg_idx

def _is_valid_penalty(t_clean):
    """Checks if integral wraps the valid delta."""
    if "integral(" not in t_clean:
        return False
    return _is_valid_delta(t_clean)

def verify_cumulative_canary_divergence_audit(trajectory, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "details": "copy_from_env unavailable"}
    
    score = 0
    details = []

    # ── Load result file ──────────────────────────────────────────────────────
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
            "details": f"Could not load result file: {e}",
        }

    dashboards = result.get("dashboards", {})

    # ── Check 1: Dashboard exists (10 pts) ────────────────────────────────────
    if DASHBOARD_NAME not in dashboards:
        return {
            "passed": False,
            "score": 0,
            "details": f"Dashboard '{DASHBOARD_NAME}' not found. Present: {list(dashboards.keys())}",
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

    # ── Check 2: Has >= 3 graphs (10 pts) ─────────────────────────────────────
    if len(graphs) >= 3:
        score += 10
        details.append(f"[+10] Dashboard has {len(graphs)} graphs (>= 3)")
    else:
        details.append(f"[-] Expected >= 3 graphs, found {len(graphs)}")

    # Flat list of all cleaned targets to check aliasing and formulas
    all_targets_clean = []
    for _, targets in graphs:
        all_targets_clean.extend([_clean_target(t) for t in targets])

    # Variables to track accomplishments
    has_baseline_legacy = False
    has_baseline_canary = False
    has_delta = False
    has_penalty = False
    aliases_found = set()

    # Evaluate all targets globally (handles out of order / misnamed graphs gracefully)
    for t_clean in all_targets_clean:
        # Alias checking
        for alias in EXPECTED_ALIASES:
            if f"alias(" in t_clean and f",'{alias}')" in t_clean or f',"{alias}")' in t_clean:
                aliases_found.add(alias)
            
        # Baseline Legacy checking (average without diff or integral)
        if _has_legacy_avg(t_clean) and "diffseries(" not in t_clean and "integral(" not in t_clean:
            has_baseline_legacy = True
            
        # Baseline Canary checking (canary without diff or integral)
        if _has_canary(t_clean) and "diffseries(" not in t_clean and "integral(" not in t_clean:
            has_baseline_canary = True
            
        # Delta checking (diffSeries without integral)
        if _is_valid_delta(t_clean) and "integral(" not in t_clean:
            has_delta = True
            
        # Penalty checking (integral over diffSeries)
        if _is_valid_penalty(t_clean):
            has_penalty = True

    # ── Check 3: Baseline Legacy (10 pts) ─────────────────────────────────────
    if has_baseline_legacy:
        score += 10
        details.append("[+10] Found correct Legacy Fleet average baseline target")
    else:
        details.append("[-] Missing or incorrect Legacy Fleet average baseline target")

    # ── Check 4: Baseline Canary (10 pts) ─────────────────────────────────────
    if has_baseline_canary:
        score += 10
        details.append("[+10] Found correct Canary Node baseline target")
    else:
        details.append("[-] Missing or incorrect Canary Node baseline target")

    # ── Check 5: Delta Composition (20 pts) ───────────────────────────────────
    if has_delta:
        score += 20
        details.append("[+20] Found correct diffSeries(Canary, LegacyAvg) delta target")
    else:
        details.append("[-] Missing or incorrect diffSeries(Canary, LegacyAvg) target (ensure canary is first argument)")

    # ── Check 6: Penalty Composition (25 pts) ─────────────────────────────────
    if has_penalty:
        score += 25
        details.append("[+25] Found correct integral(diffSeries(...)) penalty target")
    else:
        details.append("[-] Missing or incorrect integral penalty target wrapping the delta")

    # ── Check 7: Aliasing (15 pts) ────────────────────────────────────────────
    if len(aliases_found) == 4:
        score += 15
        details.append("[+15] All 4 required aliases applied correctly")
    else:
        pts = int((len(aliases_found) / 4) * 15)
        score += pts
        details.append(f"[+{pts}] Found {len(aliases_found)}/4 required aliases. Missing: {set(EXPECTED_ALIASES) - aliases_found}")

    # Pass condition: must hit 60 points and have at least some delta or penalty math
    key_math_met = has_delta or has_penalty
    passed = score >= 60 and key_math_met

    if not key_math_met:
        details.append("[-] Failed critical transformation requirements (Delta/Penalty).")

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(details)
    }