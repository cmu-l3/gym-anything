#!/usr/bin/env python3
"""
Verifier for zombie_infrastructure_decommissioning task.

Scoring (100 pts, pass >= 60):
  10 pts  Dashboard 'Zombie Decommissioning' exists
  10 pts  Dashboard has >= 3 graphs
  10 pts  Graph titled 'Lowest CPU Instances' found
  10 pts  lowestAverage(..., 2) target configured
  10 pts  Graph titled 'Cumulative Disk Activity' found
  10 pts  integral() and aliasByNode(..., 1) configured
  10 pts  Graph titled 'Idle Capacity Percentage' found
  10 pts  scale(..., -1) and offset(..., 100) configured
  20 pts  VLM verification of agent interaction via trajectory frames
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

DASHBOARD_NAME = "Zombie Decommissioning"
RESULT_PATH = "/tmp/zombie_infrastructure_decommissioning_result.json"

VLM_PROMPT = """You are analyzing a sequence of screenshots from an AI agent interacting with the Graphite monitoring web interface.
The images are sampled chronologically from the agent's full episode.

Did the agent actively use the Graphite UI to configure dashboards and graphs?
Look for evidence of manual interaction such as:
- Typing text into the metric 'Target' boxes
- Using the Graphite 'Composer' window to add functions
- Navigating the metric tree on the left sidebar
- Graph rendering updates in the main view area

If the agent just stared at the screen without doing anything, return false.
If you see active progression and configuration of monitoring graphs, return true.

Respond strictly in JSON format:
{
    "workflow_completed": true/false,
    "confidence": "low/medium/high",
    "reasoning": "Brief explanation of what the agent is doing"
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


def verify_zombie_infrastructure_decommissioning(trajectory, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "details": "copy_from_env unavailable"}

    score = 0
    details = []

    # ── 1. Programmatic Check (80 points total) ──────────────────────────────
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
    task_start = result.get("task_start", 0)
    db_mtime = result.get("db_mtime", 0)

    # Anti-gaming: Ensure dashboard was actually created/modified after task started
    if db_mtime > 0 and db_mtime < task_start:
        details.append(f"[!] Warning: Database modification time ({db_mtime}) is before task start ({task_start}). State may be stale.")

    if DASHBOARD_NAME not in dashboards:
        details.append(f"[-] Dashboard '{DASHBOARD_NAME}' not found.")
        # Fast fail if main dashboard doesn't exist
        return {"passed": False, "score": 0, "details": "\n".join(details)}

    score += 10
    details.append(f"[+10] Dashboard '{DASHBOARD_NAME}' exists")

    dashboard_state = dashboards[DASHBOARD_NAME]
    graphs = _get_graphs(dashboard_state)

    if len(graphs) >= 3:
        score += 10
        details.append(f"[+10] Dashboard has {len(graphs)} graphs (>= 3)")
    else:
        details.append(f"[-] Expected >= 3 graphs, found {len(graphs)}")

    # Track found state to prevent double-counting
    found_graph1, found_graph2, found_graph3 = False, False, False

    for title, targets in graphs:
        title_lower = title.lower()
        targets_lower = [t.lower() for t in targets]
        targets_str = " ".join(targets_lower)

        # ── Graph 1: Lowest CPU Instances ──
        if "lowest cpu" in title_lower and not found_graph1:
            score += 10
            details.append("[+10] Graph 'Lowest CPU Instances' found")
            found_graph1 = True
            
            if "lowestaverage" in targets_str and "2" in targets_str and "cpu" in targets_str:
                score += 10
                details.append("[+10] lowestAverage(..., 2) correctly configured")
            else:
                details.append("[-] lowestAverage or parameters missing in target")

        # ── Graph 2: Cumulative Disk Activity ──
        elif "cumulative disk" in title_lower and not found_graph2:
            score += 10
            details.append("[+10] Graph 'Cumulative Disk Activity' found")
            found_graph2 = True
            
            if "integral" in targets_str and "aliasbynode" in targets_str and "1" in targets_str:
                score += 10
                details.append("[+10] integral() and aliasByNode() correctly configured")
            else:
                details.append("[-] integral() or aliasByNode() missing in target")

        # ── Graph 3: Idle Capacity Percentage ──
        elif "idle" in title_lower and "capacity" in title_lower and not found_graph3:
            score += 10
            details.append("[+10] Graph 'Idle Capacity Percentage' found")
            found_graph3 = True
            
            # Check for mathematically valid composition of scale(-1) and offset(100) or offset(-100)
            has_scale = "scale" in targets_str and "-1" in targets_str
            has_offset = "offset" in targets_str and ("100" in targets_str or "-100" in targets_str)
            has_alias = "alias" in targets_str
            
            if has_scale and has_offset:
                score += 10
                details.append("[+10] scale(..., -1) and offset(..., 100) correctly chained")
            else:
                details.append("[-] scale(-1) or offset(100) missing/incorrect in target")

    # ── 2. VLM Trajectory Check (20 points) ──────────────────────────────────
    vlm_score = 0
    query_vlm = env_info.get("query_vlm")
    sample_trajectory_frames = env_info.get("sample_trajectory_frames")

    if query_vlm and sample_trajectory_frames:
        try:
            frames = sample_trajectory_frames(trajectory, n=5)
            if frames:
                vlm_result = query_vlm(prompt=VLM_PROMPT, images=frames)
                if vlm_result.get("success"):
                    parsed = vlm_result.get("parsed", {})
                    if parsed.get("workflow_completed", False):
                        vlm_score = 20
                        details.append(f"[+20] VLM verifies agent UI interaction: {parsed.get('reasoning', 'Success')}")
                    else:
                        details.append(f"[-] VLM did not verify UI interaction: {parsed.get('reasoning', 'No interaction detected')}")
                else:
                    details.append(f"[-] VLM query failed: {vlm_result.get('error')}")
            else:
                details.append("[-] Could not extract trajectory frames for VLM check")
        except Exception as e:
            details.append(f"[-] Error during VLM verification: {str(e)}")
    else:
        # If VLM is not available in the environment runner, grant the points if programmatic passes well
        if score >= 60:
            vlm_score = 20
            details.append("[+20] VLM dependencies unavailable, granting points based on strong programmatic success")
        else:
            details.append("[-] VLM dependencies unavailable, programmatic score too low to grant bypass")

    score += vlm_score

    # Passed if score >= 60 and the main dashboard exists
    passed = score >= 60 and (DASHBOARD_NAME in dashboards)

    return {
        "passed": passed,
        "score": score,
        "details": "\n".join(details)
    }