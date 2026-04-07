#!/usr/bin/env python3
"""
Verifier for resource_consumption_accounting task.

Scoring (100 pts, pass >= 60):
  10 pts  Dashboard 'Resource Accounting' exists
  10 pts  Dashboard has >= 3 graphs
  10 pts  Graph 'Hourly Network Ingress' found
  10 pts  summarize() with network.bytes_in metric
   5 pts  summarize uses 1-hour interval ('1h' or '1hour')
  10 pts  Graph 'Cumulative Network Consumption' found
  15 pts  integral() with network.bytes_in metric
  10 pts  Graph 'Disk Write Rate (MB)' found
  10 pts  scale() with disk.write_bytes metric
   5 pts  Scale factor is byte-to-MB range (1e-7 to 1e-3)
   5 pts  Both instances' disk metrics present
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

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

def verify_resource_consumption_accounting(trajectory, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}
    
    metadata = task_info.get("metadata", {})
    expected_dashboard_name = metadata.get("expected_dashboard_name", "Resource Accounting")
    hourly_network_title = metadata.get("hourly_network_title", "Hourly Network Ingress")
    cumulative_network_title = metadata.get("cumulative_network_title", "Cumulative Network Consumption")
    disk_write_title = metadata.get("disk_write_title", "Disk Write Rate (MB)")
    scale_factor_min = metadata.get("scale_factor_min", 1e-7)
    scale_factor_max = metadata.get("scale_factor_max", 1e-3)
    result_path = metadata.get("result_file", "/tmp/resource_consumption_accounting_result.json")

    score = 0
    feedback_parts = []

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
            "feedback": f"Could not load result file: {e}"
        }

    dashboards = result.get("dashboards", {})

    # ── Check 1: Dashboard exists (10 pts) ────────────────────────────────────
    if expected_dashboard_name not in dashboards:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Dashboard '{expected_dashboard_name}' not found. Present: {list(dashboards.keys())}"
        }
    
    score += 10
    feedback_parts.append(f"Dashboard '{expected_dashboard_name}' exists")

    dashboard_state = dashboards[expected_dashboard_name]
    if "parse_error" in dashboard_state:
        return {
            "passed": False,
            "score": score,
            "feedback": f"Dashboard JSON parse error: {dashboard_state['parse_error']}"
        }

    graphs = _get_graphs(dashboard_state)

    # ── Check 2: Has >= 3 graphs (10 pts) ─────────────────────────────────────
    if len(graphs) >= 3:
        score += 10
        feedback_parts.append(f"Dashboard has {len(graphs)} graph(s)")
    else:
        feedback_parts.append(f"Dashboard missing expected number of graphs (found {len(graphs)})")

    # ── Check 3: Hourly Network Ingress Graph ─────────────────────────────────
    hn_graph = _find_graph(graphs, hourly_network_title)
    if hn_graph:
        score += 10
        feedback_parts.append(f"Graph '{hourly_network_title}' found")
        _, targets = hn_graph
        
        # Look for summarize() with network.bytes_in
        summarize_found = False
        interval_correct = False
        for t in targets:
            tl = t.lower()
            if "summarize" in tl and "network.bytes_in" in tl:
                summarize_found = True
                
                # Check interval
                match = re.search(r"summarize\s*\([^,]+,\s*['\"]([^'\"]+)['\"]", t, re.IGNORECASE)
                if match:
                    interval = match.group(1).lower()
                    if interval in ['1h', '1hour', '1hours']:
                        interval_correct = True
                        break
        
        if summarize_found:
            score += 10
            feedback_parts.append("summarize() applied to network metric")
            if interval_correct:
                score += 5
                feedback_parts.append("summarize interval is correct (1h)")
            else:
                feedback_parts.append("summarize interval is missing or incorrect")
        else:
            feedback_parts.append("summarize() not found on network metric")
    else:
        feedback_parts.append(f"Graph '{hourly_network_title}' not found")

    # ── Check 4: Cumulative Network Consumption Graph ─────────────────────────
    cn_graph = _find_graph(graphs, cumulative_network_title)
    if cn_graph:
        score += 10
        feedback_parts.append(f"Graph '{cumulative_network_title}' found")
        _, targets = cn_graph
        
        integral_found = any("integral" in t.lower() and "network.bytes_in" in t.lower() for t in targets)
        if integral_found:
            score += 15
            feedback_parts.append("integral() applied to network metric")
        else:
            feedback_parts.append("integral() not found on network metric")
    else:
        feedback_parts.append(f"Graph '{cumulative_network_title}' not found")

    # ── Check 5: Disk Write Rate Graph ────────────────────────────────────────
    dw_graph = _find_graph(graphs, disk_write_title)
    if dw_graph:
        score += 10
        feedback_parts.append(f"Graph '{disk_write_title}' found")
        _, targets = dw_graph
        
        scale_found = False
        factor_in_range = False
        
        for t in targets:
            tl = t.lower()
            if "scale" in tl and "disk.write_bytes" in tl:
                scale_found = True
                # Extract scale factor
                match = re.search(r"scale\s*\([^,]+,\s*([-+]?[0-9]*\.?[0-9]+([eE][-+]?[0-9]+)?)\)", t)
                if match:
                    try:
                        factor = float(match.group(1))
                        if scale_factor_min <= factor <= scale_factor_max:
                            factor_in_range = True
                            break
                    except ValueError:
                        pass
        
        if scale_found:
            score += 10
            feedback_parts.append("scale() applied to disk metric")
            if factor_in_range:
                score += 5
                feedback_parts.append("Scale factor is within reasonable byte-to-MB range")
            else:
                feedback_parts.append("Scale factor seems incorrect for MB conversion")
        else:
            feedback_parts.append("scale() not found on disk metric")
            
        # Check both instances
        combined_targets = " ".join(targets).lower()
        has_inst1 = "ec2_instance_1" in combined_targets
        has_inst2 = "ec2_instance_2" in combined_targets
        has_wildcard = "ec2_instance_*" in combined_targets or "ec2_instance_?" in combined_targets
        
        if (has_inst1 and has_inst2) or has_wildcard:
            score += 5
            feedback_parts.append("Both EC2 instances included in disk graph")
        else:
            feedback_parts.append("Missing one or more EC2 instances in disk graph")
    else:
        feedback_parts.append(f"Graph '{disk_write_title}' not found")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }