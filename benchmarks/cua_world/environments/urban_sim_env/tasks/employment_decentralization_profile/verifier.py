#!/usr/bin/env python3
"""Verifier for employment_decentralization_profile task."""

import json
import tempfile
import os
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_employment_decentralization(traj, env_info, task_info):
    """
    Verify the spatial employment decentralization analysis.
    
    Checks CBD identification, top sectors, and spatial distance calculations 
    against dynamically generated ground truth.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    tolerance_pct = metadata.get('tolerance_pct', 2.0) / 100.0
    
    score = 0
    feedback = []

    # 1. Retrieve payloads
    agent_result = None
    ground_truth = None

    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            agent_result = json.load(f)
            
        copy_from_env("/tmp/ground_truth.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            ground_truth = json.load(f)
    except Exception as e:
        feedback.append(f"Could not read result or ground truth files: {e}")
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)

    if not agent_result or not ground_truth:
        return {"passed": False, "score": 0, "feedback": "; ".join(feedback)}

    # Check for basic files and file generation (10 points)
    file_score = 0
    has_nb = agent_result.get("notebook_exists") and agent_result.get("notebook_modified")
    has_json = agent_result.get("json_exists") and agent_result.get("json_created")
    has_csv = agent_result.get("csv_exists") and agent_result.get("csv_created")
    
    if has_nb: file_score += 2
    if has_json: file_score += 2
    if has_csv: file_score += 3
    
    # Plot Evaluation (10 points)
    plot_score = 0
    if agent_result.get('plot_exists'):
        if agent_result.get('plot_created'):
            plot_score += 5
        if agent_result.get('plot_size_kb', 0) >= 15:
            plot_score += 5
        else:
            plot_score += 2  # Plot exists but is suspiciously small
            feedback.append("Plot file is smaller than expected (likely empty).")
            
    score += file_score + plot_score
    feedback.append(f"File Output & Chart Generation: {file_score + plot_score}/20")

    # Anti-gaming verification: check notebook code
    nb_a = agent_result.get("notebook_analysis", {})
    if not (nb_a.get("has_distance") and nb_a.get("has_median")):
        feedback.append("Warning: Notebook lacks evidence of distance calculation or median operations.")
        # We don't fail outright if math is right, but it's suspicious.

    # 2. CBD Identification (25 points)
    cbd_score = 0
    agent_cbd = agent_result.get("agent_cbd_info", {})
    gt_zone = ground_truth.get("cbd_zone_id")
    gt_x = ground_truth.get("cbd_x", 0)
    gt_y = ground_truth.get("cbd_y", 0)

    try:
        ag_zone = int(agent_cbd.get("cbd_zone_id", -1))
        ag_x = float(agent_cbd.get("cbd_x", -1))
        ag_y = float(agent_cbd.get("cbd_y", -1))

        if ag_zone == gt_zone:
            cbd_score += 10
            feedback.append(f"CBD Zone correctly identified ({gt_zone}).")
        else:
            feedback.append(f"CBD Zone incorrect (Expected: {gt_zone}, Got: {ag_zone}).")

        # Give generous tolerance for coordinates due to varying float/join methods
        if abs(ag_x - gt_x) / max(gt_x, 1) < 0.005 and abs(ag_y - gt_y) / max(gt_y, 1) < 0.005:
            cbd_score += 15
            feedback.append("CBD coordinates calculated accurately.")
        else:
            feedback.append(f"CBD coordinates inaccurate (Expected: ~{gt_x:.1f}, {gt_y:.1f}).")
    except (ValueError, TypeError):
        feedback.append("Failed to parse agent CBD JSON outputs.")
        
    score += cbd_score

    # 3. CSV Analysis: Top Sectors, Median Distances, P75 Distances (55 points)
    sectors_score = 0
    median_score = 0
    p75_score = 0
    
    agent_metrics = agent_result.get("agent_sector_metrics", [])
    gt_sectors = ground_truth.get("top_3_sectors", [])
    gt_stats = ground_truth.get("sector_stats", {})

    if agent_metrics and isinstance(agent_metrics, list):
        # Top Sectors Identified (15 points) -> 5 points per correct sector
        agent_sector_ids = []
        for row in agent_metrics:
            try:
                # Find matching column for sector_id
                sec_key = next((k for k in row.keys() if 'sector' in k), None)
                if sec_key:
                    agent_sector_ids.append(int(row[sec_key]))
            except (ValueError, TypeError):
                continue
                
        correct_sectors = set(agent_sector_ids).intersection(set(gt_sectors))
        sectors_score += len(correct_sectors) * 5
        feedback.append(f"Identified {len(correct_sectors)}/3 correct top sectors.")

        # Distance Accuracy
        # (25 pts for medians, 15 pts for p75s -> split among correct sectors)
        pts_per_median = 25.0 / 3.0
        pts_per_p75 = 15.0 / 3.0

        for row in agent_metrics:
            try:
                sec_key = next((k for k in row.keys() if 'sector' in k), None)
                if not sec_key: continue
                s_id = str(int(row[sec_key]))
                
                if s_id in gt_stats:
                    gt_med = gt_stats[s_id]["median_dist"]
                    gt_p75 = gt_stats[s_id]["p75_dist"]
                    
                    # Extract agent values safely
                    med_key = next((k for k in row.keys() if 'median' in k), None)
                    p75_key = next((k for k in row.keys() if '75' in k or 'p75' in k), None)
                    
                    if med_key and not math.isnan(float(row[med_key])):
                        ag_med = float(row[med_key])
                        if abs(ag_med - gt_med) / max(gt_med, 1) <= tolerance_pct:
                            median_score += pts_per_median
                            
                    if p75_key and not math.isnan(float(row[p75_key])):
                        ag_p75 = float(row[p75_key])
                        if abs(ag_p75 - gt_p75) / max(gt_p75, 1) <= tolerance_pct:
                            p75_score += pts_per_p75
            except (ValueError, TypeError):
                continue
                
        feedback.append(f"Median distance points: {int(median_score)}/25.")
        feedback.append(f"P75 distance points: {int(p75_score)}/15.")
    else:
        feedback.append("Valid CSV output with sector metrics was not found.")

    score += int(sectors_score + median_score + p75_score)

    # Determine passing state
    final_score = min(int(score), 100)
    passed = final_score >= 65 and len(correct_sectors) >= 1 and cbd_score > 5
    
    return {
        "passed": passed,
        "score": final_score,
        "feedback": " | ".join(feedback)
    }