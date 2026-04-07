#!/usr/bin/env python3
"""
Verifier for compute_station_distances@1 task.

Verification Strategy:
1. File Timeline (Anti-gaming): Ensures CSV and summary were modified after task start.
2. File Integrity: Checks for the existence and basic header format of the CSV.
3. Content & Math Validation: Parses the CSV to ensure all stations are present, 
   coordinates match ground truth, and Haversine distances are mathematically accurate.
4. Summary Text: Validates that origin params, nearest, and farthest stations are accurately mentioned.
5. VLM Trajectory (Hybrid): Checks that the agent actively used the terminal to perform queries or scripting.
"""

import json
import os
import io
import csv
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# --- VLM Prompts ---
TERMINAL_USAGE_PROMPT = """You are analyzing trajectory frames of an agent assigned to compute distances between earthquake epicenters and stations using SeisComP.
The agent must query a database or use command-line tools to extract coordinates and compute distances.

Look at the progression of these frames and determine:
1. TERMINAL_USED: Did the agent actively use a terminal window?
2. ACTIVE_WORK: Is there evidence of the agent typing commands (e.g., `mysql`, `python`, `scevtls`, `scinv`, `bash`) or writing a script to extract data and compute the distances?

Respond ONLY in valid JSON format:
{
    "terminal_used": true/false,
    "active_work_observed": true/false,
    "commands_or_scripts_seen": ["list any recognized commands or code"],
    "confidence": "high/medium/low"
}
"""

def _vlm_query(query_vlm, prompt, images):
    if not query_vlm or not images:
        return None
    try:
        res = query_vlm(prompt=prompt, images=images)
        if res.get("success"):
            return res.get("parsed", {})
    except Exception as e:
        logger.warning(f"VLM query failed: {e}")
    return None

def verify_compute_station_distances(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available."}

    # Extract task result
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
    
    gt = result.get('ground_truth', {})
    if "error" in gt or not gt.get("stations"):
        return {"passed": False, "score": 0, "feedback": "Ground truth is corrupted. Cannot verify."}

    # 1. Timeline Verification (Anti-gaming) [10 pts]
    task_start = result.get('task_start_time', 0)
    csv_mtime = result.get('csv_mtime', 0)
    sum_mtime = result.get('sum_mtime', 0)
    
    files_created_during_task = (csv_mtime >= task_start) and (sum_mtime >= task_start)
    if files_created_during_task:
        score += 10
        feedback_parts.append("Files created during task")
    else:
        feedback_parts.append("WARNING: Outputs predate task start (potential gaming)")

    # 2. CSV File Exists and Header check [10 pts]
    csv_content = result.get('csv_content', '').strip()
    if not result.get('csv_exists') or not csv_content:
        feedback_parts.append("CSV file missing or empty")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}
    
    lines = csv_content.split('\n')
    header = lines[0].lower().replace(" ", "")
    expected_header = "station,network,latitude,longitude,distance_km"
    
    if expected_header in header:
        score += 10
        feedback_parts.append("CSV header correct")
    else:
        feedback_parts.append(f"CSV header incorrect: {lines[0]}")

    # Parse CSV contents
    agent_data = {}
    reader = csv.reader(io.StringIO(csv_content))
    next(reader, None)  # Skip header
    for row in reader:
        if len(row) >= 5:
            sta = row[0].strip()
            try:
                agent_data[sta] = {
                    "lat": float(row[2]),
                    "lon": float(row[3]),
                    "dist": float(row[4])
                }
            except ValueError:
                continue

    # 3. Stations Present & Coords [15 pts]
    # 4. Distances correct [25 pts]
    gt_stations = {s['station']: s for s in gt['stations']}
    stations_found = 0
    coords_correct = 0
    dists_correct = 0
    agent_dists = []

    for sta, gt_s in gt_stations.items():
        if sta in agent_data:
            stations_found += 1
            agt_s = agent_data[sta]
            agent_dists.append(agt_s["dist"])
            
            # Coord check
            if abs(agt_s["lat"] - gt_s["lat"]) <= 0.01 and abs(agt_s["lon"] - gt_s["lon"]) <= 0.01:
                coords_correct += 1
                
            # Dist check (±5km and anti-gaming > 1000km)
            if abs(agt_s["dist"] - gt_s["distance_km"]) <= 5.0 and agt_s["dist"] > 1000:
                dists_correct += 1

    score += (stations_found * 1) # up to 5
    score += (coords_correct * 2) # up to 10
    score += (dists_correct * 5)  # up to 25
    feedback_parts.append(f"Found {stations_found}/5 stations, {coords_correct}/5 coords exact, {dists_correct}/5 distances exact")

    # 5. Rows sorted [10 pts]
    if len(agent_dists) >= 3 and agent_dists == sorted(agent_dists):
        score += 10
        feedback_parts.append("CSV correctly sorted")
    else:
        feedback_parts.append("CSV not properly sorted")

    # 6. Summary exists & Origin Params [10 pts]
    sum_content = result.get('sum_content', '').lower()
    if result.get('sum_exists') and sum_content:
        # Check if lat/lon values from origin are roughly present
        olat_str = f"{gt['origin']['lat']:.1f}"
        olon_str = f"{gt['origin']['lon']:.1f}"
        if olat_str in sum_content and olon_str in sum_content:
            score += 10
            feedback_parts.append("Summary origin params present")
        else:
            feedback_parts.append("Summary lacks exact origin coordinates")

        # 7. Summary Nearest/Farthest [10 pts]
        gt_near = gt['nearest'].lower()
        gt_far = gt['farthest'].lower()
        
        has_near = gt_near in sum_content and ('near' in sum_content or 'clos' in sum_content)
        has_far = gt_far in sum_content and ('far' in sum_content or 'max' in sum_content)
        
        if has_near: score += 5
        if has_far: score += 5
        feedback_parts.append(f"Summary near/far detection: {has_near}/{has_far}")
    else:
        feedback_parts.append("Summary file missing")

    # 8. VLM Trajectory Check [10 pts]
    from gym_anything.vlm import sample_trajectory_frames
    query_vlm = env_info.get('query_vlm')
    frames = sample_trajectory_frames(traj, n=4)
    vlm_result = _vlm_query(query_vlm, TERMINAL_USAGE_PROMPT, images=frames)
    
    vlm_passed = False
    if vlm_result:
        if vlm_result.get("terminal_used") and vlm_result.get("active_work_observed"):
            score += 10
            vlm_passed = True
            feedback_parts.append("VLM confirms terminal analytical workflow")
        else:
            feedback_parts.append("VLM: No visible terminal usage or active scripting")
    else:
        # Give fallback credit if VLM fails but programmatic logic is flawless
        if dists_correct == 5:
            score += 10
            feedback_parts.append("VLM unavailable, assuming terminal used based on perfect outputs")

    # Final logic
    key_criteria_met = files_created_during_task and (dists_correct >= 3)
    passed = (score >= 60) and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }