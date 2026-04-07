#!/usr/bin/env python3
"""
Verifier for whisper_namespace_migration task.

Scoring (100 pts, pass >= 60):
  20 pts  Compute Whisper files successfully migrated to infrastructure/compute/
  20 pts  Network Whisper files successfully migrated to infrastructure/network/
  10 pts  Legacy servers/ Whisper files completely removed
  10 pts  Search index successfully rebuilt with infrastructure.* paths
  10 pts  Dashboard 'Namespace Migration Audit' exists
  15 pts  Graph 'Compute Tier' targets correct infrastructure.compute metrics
  15 pts  Graph 'Network Tier' targets correct infrastructure.network metrics

Key Criteria to Pass: Both file migrations must be successful and total score >= 60.
"""

import json
import os
import tempfile

DASHBOARD_NAME = "Namespace Migration Audit"
COMPUTE_GRAPH_TITLE = "Compute Tier"
NETWORK_GRAPH_TITLE = "Network Tier"
RESULT_PATH = "/tmp/whisper_namespace_migration_result.json"

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

def _has_target_with(targets, required_substrings):
    """Check if any target contains ALL the required substrings (case-insensitive)."""
    for t in targets:
        tl = t.lower()
        if all(sub.lower() in tl for sub in required_substrings):
            return True
    return False

def verify_whisper_namespace_migration(trajectory, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}
    
    score = 0
    details = []

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
            "feedback": f"Could not load result file: {e}"
        }

    compute_migrated = result.get("compute_migrated", False)
    network_migrated = result.get("network_migrated", False)
    legacy_removed = result.get("legacy_removed", False)
    index_updated = result.get("index_updated", False)
    dashboards = result.get("dashboards", {})

    # 1. Compute Migration
    if compute_migrated:
        score += 20
        details.append("[+20] Compute Whisper files migrated successfully")
    else:
        details.append("[-] Compute Whisper files NOT migrated to infrastructure/compute/")

    # 2. Network Migration
    if network_migrated:
        score += 20
        details.append("[+20] Network Whisper files migrated successfully")
    else:
        details.append("[-] Network Whisper files NOT migrated to infrastructure/network/")

    # 3. Legacy Files Removal
    if legacy_removed:
        score += 10
        details.append("[+10] Legacy servers/ Whisper files removed")
    else:
        details.append("[-] Legacy servers/ Whisper files still exist")

    # 4. Search Index Update
    if index_updated:
        score += 10
        details.append("[+10] Search index rebuilt with infrastructure.* paths")
    else:
        details.append("[-] Search index NOT rebuilt with infrastructure.* paths")

    # 5. Dashboard Configuration Validation
    if DASHBOARD_NAME in dashboards:
        score += 10
        details.append(f"[+10] Dashboard '{DASHBOARD_NAME}' exists")
        db_state = dashboards[DASHBOARD_NAME]
        graphs = _get_graphs(db_state)
        
        compute_graph_targets = None
        network_graph_targets = None
        
        # Locate compute graph
        for title, targets in graphs:
            if title == COMPUTE_GRAPH_TITLE:
                compute_graph_targets = targets
                break
        if compute_graph_targets is None:
            # Fuzzy match as fallback
            for title, targets in graphs:
                if COMPUTE_GRAPH_TITLE.lower() in title.lower():
                    compute_graph_targets = targets
                    break
                    
        if compute_graph_targets is not None:
            if _has_target_with(compute_graph_targets, ["infrastructure", "compute", "ec2_instance"]):
                score += 15
                details.append(f"[+15] Graph '{COMPUTE_GRAPH_TITLE}' targets correct infrastructure.compute metrics")
            else:
                details.append(f"[-] Graph '{COMPUTE_GRAPH_TITLE}' does NOT target infrastructure.compute metrics")
        else:
            details.append(f"[-] Graph '{COMPUTE_GRAPH_TITLE}' not found")

        # Locate network graph
        for title, targets in graphs:
            if title == NETWORK_GRAPH_TITLE:
                network_graph_targets = targets
                break
        if network_graph_targets is None:
            # Fuzzy match as fallback
            for title, targets in graphs:
                if NETWORK_GRAPH_TITLE.lower() in title.lower():
                    network_graph_targets = targets
                    break

        if network_graph_targets is not None:
            if _has_target_with(network_graph_targets, ["infrastructure", "network", "load_balancer"]):
                score += 15
                details.append(f"[+15] Graph '{NETWORK_GRAPH_TITLE}' targets correct infrastructure.network metrics")
            else:
                details.append(f"[-] Graph '{NETWORK_GRAPH_TITLE}' does NOT target infrastructure.network metrics")
        else:
            details.append(f"[-] Graph '{NETWORK_GRAPH_TITLE}' not found")
    else:
        details.append(f"[-] Dashboard '{DASHBOARD_NAME}' not found")

    passed = (score >= 60) and compute_migrated and network_migrated
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(details)
    }