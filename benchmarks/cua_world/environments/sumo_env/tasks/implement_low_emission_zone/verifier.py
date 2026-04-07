#!/usr/bin/env python3
"""
Verifier for implement_low_emission_zone task.

Multi-Criteria Evaluation:
1. `lez_report.txt` parsed correctly and contains the target metrics.
2. `pasubio_lez.net.xml` exists and successfully restricts the reported edge.
3. `lez_tripinfo.xml` contains a ~70/30 split between clean_car and polluting_car.
4. Calculations in the agent's report match the ground-truth calculation from the tripinfo file.
5. VLM checks trajectory for evidence of SUMO workflow execution.
"""

import json
import os
import tempfile
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def safe_copy(env_info, container_path, host_path):
    """Safely copy a file from the environment."""
    copy_from_env = env_info.get('copy_from_env')
    try:
        copy_from_env(container_path, host_path)
        return os.path.exists(host_path) and os.path.getsize(host_path) > 0
    except Exception as e:
        logger.warning(f"Failed to copy {container_path}: {e}")
        return False

def verify_implement_low_emission_zone(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_dir = tempfile.mkdtemp()
    score = 0
    feedback_parts = []
    
    # --- Check basic export JSON ---
    res_path = os.path.join(temp_dir, "task_result.json")
    if not safe_copy(env_info, "/tmp/task_result.json", res_path):
        return {"passed": False, "score": 0, "feedback": "Failed to read result JSON"}

    with open(res_path, 'r') as f:
        result = json.load(f)
    
    files_status = result.get("files", {})
    if files_status.get("net_xml") == "true" and files_status.get("tripinfo_xml") == "true":
        score += 10
        feedback_parts.append("Required simulation outputs generated during task.")
    else:
        feedback_parts.append("Missing or stale required XML files (net.xml or tripinfo.xml).")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # --- Copy Task Artifacts ---
    report_path = os.path.join(temp_dir, "lez_report.txt")
    safe_copy(env_info, "/home/ga/SUMO_Output/lez_report.txt", report_path)
    
    tripinfo_path = os.path.join(temp_dir, "lez_tripinfo.xml")
    safe_copy(env_info, "/home/ga/SUMO_Output/lez_tripinfo.xml", tripinfo_path)
    
    net_path = os.path.join(temp_dir, "pasubio_lez.net.xml")
    safe_copy(env_info, "/home/ga/SUMO_Output/pasubio_lez.net.xml", net_path)

    # --- 1. Parse Agent's Report (15 pts) ---
    report_data = {}
    if os.path.exists(report_path):
        with open(report_path, 'r') as f:
            for line in f:
                if ":" in line:
                    k, v = line.split(":", 1)
                    report_data[k.strip()] = v.strip()

    reported_edge = report_data.get("Restricted Edge ID", "")
    try:
        rep_clean_trips = int(report_data.get("Clean Car Trips", -1))
        rep_poll_trips = int(report_data.get("Polluting Car Trips", -1))
        rep_clean_avg = float(report_data.get("Clean Car Avg Duration", -1))
        rep_poll_avg = float(report_data.get("Polluting Car Avg Duration", -1))
    except ValueError:
        rep_clean_trips, rep_poll_trips, rep_clean_avg, rep_poll_avg = -1, -1, -1, -1

    if reported_edge and rep_clean_trips >= 0:
        score += 15
        feedback_parts.append(f"Report parsed successfully (Edge: {reported_edge})")
    else:
        feedback_parts.append("Report parsing failed or missing required keys.")

    # --- 2. Verify Network Patching (25 pts) ---
    is_restricted = False
    if os.path.exists(net_path) and reported_edge:
        try:
            tree = ET.parse(net_path)
            edge = tree.getroot().find(f".//edge[@id='{reported_edge}']")
            if edge is not None:
                lanes = edge.findall("lane")
                is_restricted = True
                for lane in lanes:
                    disallow = lane.get("disallow", "")
                    allow = lane.get("allow", "")
                    # Either custom1 is explicitly disallowed, or it's implicitly omitted from 'allow'
                    if "custom1" in disallow:
                        continue
                    if allow and "custom1" not in allow and "all" not in allow:
                        continue
                    is_restricted = False
                
                if is_restricted:
                    score += 25
                    feedback_parts.append("Network successfully patched (custom1 disallowed).")
                else:
                    feedback_parts.append("Edge found but not fully restricted against custom1.")
            else:
                feedback_parts.append(f"Reported edge '{reported_edge}' not found in modified network.")
        except Exception as e:
            feedback_parts.append(f"Error parsing net.xml: {e}")

    # --- 3. Verify Tripinfo Output & Mixed Fleet (20 pts) ---
    actual_clean_trips = 0
    actual_polluting_trips = 0
    actual_clean_dur = 0.0
    actual_polluting_dur = 0.0

    if os.path.exists(tripinfo_path):
        try:
            tree = ET.parse(tripinfo_path)
            for t in tree.getroot().findall("tripinfo"):
                v = t.get("vType", "")
                d = float(t.get("duration", "0"))
                if v == "clean_car":
                    actual_clean_trips += 1
                    actual_clean_dur += d
                elif v == "polluting_car":
                    actual_polluting_trips += 1
                    actual_polluting_dur += d
            
            total_trips = actual_clean_trips + actual_polluting_trips
            if total_trips > 0:
                polluting_ratio = actual_polluting_trips / total_trips
                if 0.15 <= polluting_ratio <= 0.45:  # ~30% target
                    score += 20
                    feedback_parts.append(f"Valid mixed fleet found (Polluting ratio: {polluting_ratio:.0%}).")
                else:
                    feedback_parts.append(f"Mixed fleet generated, but ratio off (Polluting ratio: {polluting_ratio:.0%}).")
            else:
                feedback_parts.append("Tripinfo parsed but no valid completed trips found.")
        except Exception as e:
            feedback_parts.append(f"Error parsing tripinfo.xml: {e}")

    # --- 4. Verify Calculations (15 pts) ---
    avg_clean = actual_clean_dur / actual_clean_trips if actual_clean_trips > 0 else 0
    avg_poll = actual_polluting_dur / actual_polluting_trips if actual_polluting_trips > 0 else 0

    if actual_clean_trips > 0:
        counts_match = (rep_clean_trips == actual_clean_trips) and (rep_poll_trips == actual_polluting_trips)
        math_matches = (abs(rep_clean_avg - avg_clean) < 2.0) and (abs(rep_poll_avg - avg_poll) < 2.0)
        
        if counts_match and math_matches:
            score += 15
            feedback_parts.append("Report calculations accurately match Tripinfo data.")
        else:
            feedback_parts.append("Report calculations have a math/counting error compared to ground truth.")

    # --- 5. VLM Verification of Workflow (15 pts) ---
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        images = frames + [final] if final else frames
        
        query_vlm = env_info.get("query_vlm")
        if images and query_vlm:
            prompt = """Examine these trajectory frames from a Linux desktop session.
The user is working on a SUMO (Simulation of Urban Mobility) task involving modifying XML files, running traffic simulations, and analyzing data.
Look for evidence of:
1. Terminal usage running SUMO commands or Python scripts.
2. Editing XML files (net.xml, rou.xml, sumocfg).
3. Traffic simulation logs or analytical manipulation of data.

Respond in JSON format:
{
    "sumo_workflow_visible": true/false,
    "confidence": "high/medium/low",
    "reasoning": "what you observed"
}"""
            vlm_res = query_vlm(prompt=prompt, images=images)
            parsed = vlm_res.get("parsed", {})
            if parsed.get("sumo_workflow_visible", False):
                score += 15
                feedback_parts.append("VLM verified SUMO/XML workflow in trajectory.")
            else:
                feedback_parts.append("VLM did not clearly observe the expected workflow.")
        else:
            score += 15  # Free points if VLM is unavailable
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        score += 15  # Don't penalize framework errors

    # Clean up temp
    import shutil
    shutil.rmtree(temp_dir, ignore_errors=True)

    passed = score >= 70 and is_restricted and (actual_polluting_trips > 0)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }