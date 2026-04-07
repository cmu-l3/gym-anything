#!/usr/bin/env python3
"""
Verifier for implement_speed_zone@1 task.
Uses copy_from_env to load processed metrics from /tmp/task_result.json
Combines programmatic verification with trajectory VLM to ensure command-line usage.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_implement_speed_zone(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    task_start = result.get("task_start_time", 0)

    # 1. Plain XML exports exist (10 points)
    exports = result.get("plain_xml_exports", {})
    valid_exports = sum(1 for v in exports.values() if v.get("exists") and v.get("size", 0) > 100)
    if valid_exports == 4:
        score += 10
        feedback_parts.append("Plain XML exported correctly")
    elif valid_exports > 0:
        score += 5
        feedback_parts.append(f"Partial plain XML export ({valid_exports}/4 files)")
    else:
        feedback_parts.append("Plain XML files missing")

    # 2. Modified Edge File (20 points)
    mod_edg = result.get("modified_edge_file", {})
    expected_edges = result.get("expected_modified_edges", 0)
    
    if mod_edg.get("exists") and mod_edg.get("valid"):
        edges_to_833 = mod_edg.get("edges_to_833", 0)
        mtime = mod_edg.get("mtime", 0)
        
        # Check anti-gaming
        if mtime >= task_start:
            if edges_to_833 > 0:
                if expected_edges > 0 and abs(edges_to_833 - expected_edges) < 100:
                    score += 20
                    feedback_parts.append(f"Edge file modified successfully ({edges_to_833} edges updated)")
                else:
                    score += 10
                    feedback_parts.append(f"Edge file modified, but counts irregular (Found: {edges_to_833}, Expected: ~{expected_edges})")
            else:
                feedback_parts.append("Edge file saved but speeds not changed to 8.33")
        else:
            feedback_parts.append("Modified edge file timestamp is BEFORE task start (suspicious)")
    else:
        feedback_parts.append("Modified edge file missing or invalid")

    # 3. Reimported Network (10 points)
    net = result.get("reimported_net", {})
    if net.get("exists") and net.get("valid") and net.get("junctions", 0) > 10 and net.get("edges", 0) > 10:
        score += 10
        feedback_parts.append("Network successfully reimported")
    else:
        feedback_parts.append("Reimported network missing or invalid")

    # 4. SUMO Configuration (10 points)
    cfg = result.get("sumo_config", {})
    if cfg.get("exists") and cfg.get("valid") and cfg.get("has_net") and cfg.get("has_routes") and cfg.get("has_tripinfo"):
        score += 10
        feedback_parts.append("Valid SUMO configuration created")
    elif cfg.get("exists"):
        score += 5
        feedback_parts.append("SUMO config created but missing critical attributes")
    else:
        feedback_parts.append("SUMO config missing")

    # 5. Simulation Output & Duration Increase (30 points)
    sim = result.get("simulation_output", {})
    baseline_avg = result.get("baseline_avg_duration", 0)
    
    if sim.get("exists") and sim.get("valid"):
        if sim.get("mtime", 0) >= task_start:
            if sim.get("trip_count", 0) > 50:
                score += 15
                feedback_parts.append("Simulation completed successfully")
                
                # Check Duration Increase
                zona30_avg = sim.get("avg_duration", 0)
                if baseline_avg > 0:
                    pct_increase = ((zona30_avg - baseline_avg) / baseline_avg) * 100
                    if pct_increase >= 5.0:
                        score += 15
                        feedback_parts.append(f"Travel time increased correctly by {pct_increase:.1f}%")
                    elif pct_increase > 0:
                        score += 7
                        feedback_parts.append(f"Travel time increased slightly ({pct_increase:.1f}%)")
                    else:
                        feedback_parts.append("Travel time did not increase")
            else:
                score += 5
                feedback_parts.append("Simulation output invalid (too few trips)")
        else:
            feedback_parts.append("Tripinfo file timestamp is BEFORE task start (suspicious)")
    else:
        feedback_parts.append("Simulation tripinfo missing or invalid")

    # 6. Summary File (10 points)
    summary = result.get("summary_file", {})
    if summary.get("exists"):
        content = summary.get("content", "").lower()
        has_metrics = sum([
            any(kw in content for kw in ['baseline', 'original', 'before']),
            any(kw in content for kw in ['zona30', 'new', 'after']),
            any(kw in content for kw in ['%', 'percent', 'increase', 'change'])
        ])
        if has_metrics >= 2:
            score += 10
            feedback_parts.append("Summary file complete")
        else:
            score += 5
            feedback_parts.append("Summary file created but missing some metrics")
    else:
        feedback_parts.append("Summary file missing")

    # 7. VLM Trajectory Verification (10 points)
    try:
        from gym_anything.vlm import sample_trajectory_frames
        query_vlm = env_info.get('query_vlm')
        if query_vlm:
            frames = sample_trajectory_frames(traj, n=4)
            prompt = """Review these trajectory screenshots of a terminal.
            Did the user actively use command-line tools (e.g., netconvert, sumo, text editors like nano/vim/sed, or python) to modify files and run simulations?
            We are verifying that work was actually done in the terminal.
            Return JSON: {"terminal_used_for_task": true/false}"""
            
            vlm_res = query_vlm(images=frames, prompt=prompt)
            if vlm_res.get("parsed", {}).get("terminal_used_for_task", False):
                score += 10
                feedback_parts.append("VLM verified active terminal usage")
            else:
                feedback_parts.append("VLM did NOT verify active terminal usage")
        else:
            feedback_parts.append("VLM unavailable, skipping trajectory check")
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")

    # Determine passing state
    key_criteria_met = (
        mod_edg.get("exists") and 
        mod_edg.get("mtime", 0) >= task_start and 
        sim.get("exists") and 
        sim.get("mtime", 0) >= task_start
    )
    
    passed = score >= 60 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }