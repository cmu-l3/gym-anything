#!/usr/bin/env python3
"""
Verifier for incident_blast_radius_visualization task.

Hybrid Verification Strategy:
1. Primary Programmatic Check (80 pts): Reads Graphite SQLite database dump to 
   analyze exact formulas, targets, and parameters used.
2. VLM Trajectory Check (20 pts): Verifies the agent actively manipulated the 
   UI by analyzing intermediate workflow frames.

Pass Threshold: 70 points
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

DASHBOARD_NAME = "Post-Incident Blast Radius"
RESULT_PATH = "/tmp/incident_blast_radius_visualization_result.json"

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

def verify_incident_blast_radius_visualization(trajectory, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    score = 0
    feedback = []

    # 1. Load exported result JSON using copy_from_env -------------------------
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

    # 2. Verify Dashboard Exists -----------------------------------------------
    if DASHBOARD_NAME not in dashboards:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Dashboard '{DASHBOARD_NAME}' not found. Dashboards present: {list(dashboards.keys())}"
        }
    
    score += 10
    feedback.append(f"[+10] Dashboard '{DASHBOARD_NAME}' exists")
    
    dashboard_state = dashboards[DASHBOARD_NAME]
    graphs = _get_graphs(dashboard_state)
    
    # 3. Verify Graph Count ----------------------------------------------------
    if len(graphs) == 3:
        score += 10
        feedback.append("[+10] Dashboard has exactly 3 graphs")
    elif len(graphs) > 3:
        score += 10
        feedback.append(f"[+10] Dashboard has {len(graphs)} graphs (>= 3)")
    else:
        feedback.append(f"[-] Dashboard has {len(graphs)} graphs (expected 3)")

    # 4. Process Target Components ---------------------------------------------
    db_base = False
    web_base = False
    lb_base = False
    
    threshold_count = 0
    infinite_count = 0
    format_count = 0
    
    for title, targets in graphs:
        # Standardize strings for easier substring checks
        tl_targets = [t.lower().replace(" ", "") for t in targets]
        
        # Check for Base Metrics within this specific graph
        if any("rds_database.cpu.utilization" in t and "removebelowvalue" not in t for t in tl_targets):
            db_base = True
        elif any("rds_database.cpu.utilization" in t for t in tl_targets) and not db_base:
            db_base = True # Fallback if agent merged metric and overlay

        if any("speed_sensor_1" in t and "removebelowvalue" not in t for t in tl_targets):
            web_base = True
            
        if any("nonnegativederivative" in t and "requests.count" in t for t in tl_targets):
            lb_base = True
            
        # Check for Overlay Components within this specific graph
        graph_has_threshold = False
        graph_has_infinite = False
        graph_has_format = False
        
        for t in tl_targets:
            if "removebelowvalue" in t and "rds_database.cpu.utilization" in t and "80" in t:
                graph_has_threshold = True
                if "drawasinfinite" in t:
                    graph_has_infinite = True
                if "color" in t and ("red" in t or "ff0000" in t):
                    graph_has_format = True
                    
        if graph_has_threshold:
            threshold_count += 1
        if graph_has_infinite:
            infinite_count += 1
        if graph_has_format:
            format_count += 1

    # Award points for Base Metrics
    if db_base:
        score += 5
        feedback.append("[+5] DB Base Metric (RDS CPU) found")
    if web_base:
        score += 5
        feedback.append("[+5] Web Base Metric (Web Speed) found")
    if lb_base:
        score += 5
        feedback.append("[+5] LB Base Metric (LB Request Rate via nonNegativeDerivative) found")
        
    # Award points for Overlays
    threshold_pts = min(3, threshold_count) * 5
    score += threshold_pts
    if threshold_pts > 0:
        feedback.append(f"[+{threshold_pts}] Threshold isolation (removeBelowValue) found in {min(3, threshold_count)}/3 graphs")
        
    infinite_pts = min(3, infinite_count) * 5
    score += infinite_pts
    if infinite_pts > 0:
        feedback.append(f"[+{infinite_pts}] Infinite Shading Band (drawAsInfinite) found in {min(3, infinite_count)}/3 graphs")
        
    format_pts = min(3, format_count) * 5
    score += format_pts
    if format_pts > 0:
        feedback.append(f"[+{format_pts}] Presentation Formatting (color=red) found in {min(3, format_count)}/3 graphs")

    # 5. VLM Trajectory Verification -------------------------------------------
    vlm_score = 0
    query_vlm = env_info.get("query_vlm")
    if query_vlm and trajectory:
        try:
            # Fallback to manual trajectory sampling if library is unavailable in execution env
            try:
                from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
                frames = sample_trajectory_frames(trajectory, n=3)
                final = get_final_screenshot(trajectory)
                images = frames + [final] if final else frames
            except ImportError:
                images = []
                for step in trajectory[::max(1, len(trajectory)//4)]:
                    if "observation" in step and "image" in step["observation"]:
                        images.append(step["observation"]["image"])

            if images:
                prompt = """You are verifying a Graphite monitoring dashboard creation task.
The agent was asked to create a dashboard named 'Post-Incident Blast Radius' with 3 graphs showing a red danger zone (vertical bands).
Examine these trajectory frames.
1. Did the agent navigate the Graphite web UI?
2. Are there multiple graphs visible?
3. Are there red vertical bands (drawAsInfinite) visible on the graphs?

Reply in JSON: {"ui_navigated": true, "graphs_visible": true, "red_bands_visible": true}"""
                
                vlm_res = query_vlm(prompt=prompt, images=images)
                if vlm_res and isinstance(vlm_res, dict) and vlm_res.get("success"):
                    parsed = vlm_res.get("parsed", {})
                    if parsed.get("ui_navigated"): vlm_score += 5
                    if parsed.get("graphs_visible"): vlm_score += 5
                    if parsed.get("red_bands_visible"): vlm_score += 10
                    
                    if vlm_score > 0:
                        feedback.append(f"[+{vlm_score}] VLM Trajectory Verification passed")
                else:
                    feedback.append("[0] VLM query did not succeed")
        except Exception as e:
            feedback.append(f"VLM verification error: {str(e)}")
            
    score += vlm_score

    # Determine final success state
    key_criteria_met = (score >= 70) and db_base and web_base and (threshold_count > 0)
    passed = key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }