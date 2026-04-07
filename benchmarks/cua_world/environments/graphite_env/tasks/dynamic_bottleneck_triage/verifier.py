#!/usr/bin/env python3
"""
Verifier for dynamic_bottleneck_triage task.

Hybrid Verification Strategy:
1. Programmatic (Primary): Parses Graphite's SQLite dashboard DB to precisely
   verify that the correct dynamic functions (highestAverage, highestMax, exclude, etc.)
   were applied to the correct graphs.
2. VLM Trajectory (Secondary): Evaluates the framework's trajectory screenshots
   to ensure the agent actively built the dashboard through the UI.

Scoring (100 pts, pass >= 70):
  10 pts  Dashboard 'Dynamic Bottleneck Triage' exists
   5 pts  Graph 'Production CPU Saturated Nodes' exists
  10 pts  CPU Dynamic Limit: highestAverage(..., 2)
  10 pts  CPU Noise Exclusion: exclude(..., 'instance_3')
  10 pts  Legend Formatting: aliasByNode(..., 1)
   5 pts  Graph 'Peak Disk Write Analysis' exists
  10 pts  Disk Peak Isolation: highestMax(..., 1)
   5 pts  Graph 'Aggregated Fleet Writes' exists
  15 pts  Fleet Writes Summed: sumSeries(...) and alias(...)
  20 pts  VLM verification of trajectory workflow progression
"""

import json
import os
import re
import tempfile
import logging

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

DASHBOARD_NAME = "Dynamic Bottleneck Triage"
RESULT_PATH = "/tmp/dynamic_bottleneck_triage_result.json"

GRAPH_CPU = "Production CPU Saturated Nodes"
GRAPH_DISK_PEAK = "Peak Disk Write Analysis"
GRAPH_DISK_SUM = "Aggregated Fleet Writes"

VLM_PROMPT = """You are verifying an agent's workflow in a web-based monitoring tool (Graphite).

Look at these sequential trajectory screenshots. They show the progression of the agent's work over time.
Did the agent actively build a dashboard? Look for evidence of:
1. Navigating the metric tree on the left panel
2. Adding graphs to the main dashboard area
3. Typing or selecting functions (like highestAverage, sumSeries, exclude) in the UI
4. The dashboard getting progressively more complete

Return a JSON object with:
{
    "workflow_progress_observed": true/false,
    "evidence": "brief explanation of the actions observed across the frames"
}
"""

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
    for title, targets in graphs:
        if title == expected_title:
            return targets
    for title, targets in graphs:
        if expected_title.lower() in title.lower():
            return targets
    return None

def verify_dynamic_bottleneck_triage(trajectory, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    query_vlm = env_info.get("query_vlm")
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    score = 0
    feedback_parts = []

    # ── 1. Load Result File ───────────────────────────────────────────────────
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

    # ── 2. Check Dashboard Existence (10 pts) ─────────────────────────────────
    if DASHBOARD_NAME not in dashboards:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Dashboard '{DASHBOARD_NAME}' not found. Present: {list(dashboards.keys())}"
        }
    
    score += 10
    feedback_parts.append(f"[+10] Dashboard '{DASHBOARD_NAME}' exists")
    
    dashboard_state = dashboards[DASHBOARD_NAME]
    graphs = _get_graphs(dashboard_state)

    # ── 3. Evaluate Graph 1: CPU Saturated Nodes (Total 35 pts) ───────────────
    cpu_targets = _find_graph(graphs, GRAPH_CPU)
    if cpu_targets is not None:
        score += 5
        feedback_parts.append(f"[+5] Graph '{GRAPH_CPU}' exists")
        
        target_str = " ".join(cpu_targets).lower()
        
        # highestAverage(..., 2)
        if re.search(r'highestaverage\s*\(.*,\s*2\s*\)', target_str):
            score += 10
            feedback_parts.append("[+10] highestAverage(..., 2) applied")
        else:
            feedback_parts.append("[-] Missing highestAverage with N=2")
            
        # exclude(..., 'instance_3')
        if re.search(r'exclude\s*\(.*(instance_3|3).*?\)', target_str):
            score += 10
            feedback_parts.append("[+10] exclude(..., 'instance_3') applied")
        else:
            feedback_parts.append("[-] Missing exclude for instance_3")
            
        # aliasByNode(..., 1)
        if re.search(r'aliasbynode\s*\(.*,\s*1\s*\)', target_str):
            score += 10
            feedback_parts.append("[+10] aliasByNode(..., 1) applied")
        else:
            feedback_parts.append("[-] Missing aliasByNode with index 1")
    else:
        feedback_parts.append(f"[-] Graph '{GRAPH_CPU}' missing")

    # ── 4. Evaluate Graph 2: Peak Disk Write (Total 15 pts) ───────────────────
    disk_peak_targets = _find_graph(graphs, GRAPH_DISK_PEAK)
    if disk_peak_targets is not None:
        score += 5
        feedback_parts.append(f"[+5] Graph '{GRAPH_DISK_PEAK}' exists")
        
        target_str = " ".join(disk_peak_targets).lower()
        
        if re.search(r'highestmax\s*\(.*,\s*1\s*\)', target_str):
            score += 10
            feedback_parts.append("[+10] highestMax(..., 1) applied")
        else:
            feedback_parts.append("[-] Missing highestMax with N=1")
    else:
        feedback_parts.append(f"[-] Graph '{GRAPH_DISK_PEAK}' missing")

    # ── 5. Evaluate Graph 3: Aggregated Fleet Writes (Total 20 pts) ───────────
    disk_sum_targets = _find_graph(graphs, GRAPH_DISK_SUM)
    if disk_sum_targets is not None:
        score += 5
        feedback_parts.append(f"[+5] Graph '{GRAPH_DISK_SUM}' exists")
        
        target_str = " ".join(disk_sum_targets).lower()
        
        has_sum = "sumseries" in target_str
        has_alias = re.search(r'alias\s*\(.*total fleet writes.*?\)', target_str)
        
        if has_sum and has_alias:
            score += 15
            feedback_parts.append("[+15] sumSeries and correct alias applied")
        elif has_sum:
            score += 8
            feedback_parts.append("[+8] sumSeries applied (alias missing/incorrect)")
        else:
            feedback_parts.append("[-] Missing sumSeries aggregation")
    else:
        feedback_parts.append(f"[-] Graph '{GRAPH_DISK_SUM}' missing")

    # ── 6. VLM Trajectory Verification (20 pts) ───────────────────────────────
    if query_vlm:
        try:
            frames = sample_trajectory_frames(trajectory, n=4)
            final = get_final_screenshot(trajectory)
            if frames and final:
                vlm_res = query_vlm(images=frames + [final], prompt=VLM_PROMPT)
                if vlm_res and vlm_res.get("success"):
                    parsed = vlm_res.get("parsed", {})
                    if parsed.get("workflow_progress_observed"):
                        score += 20
                        feedback_parts.append("[+20] VLM verified active dashboard building workflow")
                    else:
                        feedback_parts.append("[-] VLM did not observe dashboard workflow progression")
                else:
                    logger.warning("VLM query failed or returned no success.")
        except Exception as e:
            logger.warning(f"VLM verification error: {e}")
            feedback_parts.append(f"[!] VLM verification skipped/failed: {e}")

    # Final scoring calculation
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }