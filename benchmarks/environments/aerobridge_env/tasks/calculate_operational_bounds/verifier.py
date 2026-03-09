#!/usr/bin/env python3
"""
Verifier for calculate_operational_bounds task.
"""

import json
import os
import tempfile
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_calculate_operational_bounds(traj, env_info, task_info):
    """
    Verify that the agent calculated the correct bounding box for the flight plans.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Extract data
    output_exists = result.get("output_exists", False)
    file_created = result.get("file_created_during_task", False)
    script_exists = result.get("script_exists", False)
    agent_output = result.get("agent_output_content", {})
    ground_truth = result.get("ground_truth", {})
    
    score = 0
    feedback_parts = []
    
    # Criterion 1: Output file creation (20 pts)
    if output_exists and file_created:
        score += 20
        feedback_parts.append("JSON output file created successfully.")
    elif output_exists:
        score += 10
        feedback_parts.append("JSON output file exists but timestamp suggests it wasn't created during task?")
    else:
        feedback_parts.append("JSON output file not found.")

    # Criterion 2: Script creation (20 pts)
    if script_exists:
        score += 20
        feedback_parts.append("Analysis script found.")
    else:
        feedback_parts.append("Analysis script not found (agent should write a script).")

    # Criterion 3: Accuracy (60 pts)
    # Check if ground truth is valid
    if "error" in ground_truth:
        return {
            "passed": False, 
            "score": score, 
            "feedback": f"Verifier Error: Ground truth calculation failed ({ground_truth['error']}). Task setup likely failed."
        }
    
    gt_min_lat = ground_truth.get("min_lat")
    gt_max_lat = ground_truth.get("max_lat")
    gt_min_lon = ground_truth.get("min_lon")
    gt_max_lon = ground_truth.get("max_lon")

    # Check agent output validity
    if not isinstance(agent_output, dict) or not all(k in agent_output for k in ["min_lat", "max_lat", "min_lon", "max_lon"]):
        feedback_parts.append("Agent output JSON is missing required keys or invalid.")
    else:
        # Compare values
        tolerance = task_info.get("metadata", {}).get("tolerance_degrees", 0.0001)
        
        matches = 0
        try:
            ag_min_lat = float(agent_output["min_lat"])
            ag_max_lat = float(agent_output["max_lat"])
            ag_min_lon = float(agent_output["min_lon"])
            ag_max_lon = float(agent_output["max_lon"])

            # Helper for readable feedback
            def check(val, gt, name):
                if abs(val - gt) <= tolerance:
                    return True
                return False

            if check(ag_min_lat, gt_min_lat, "min_lat"): matches += 1
            if check(ag_max_lat, gt_max_lat, "max_lat"): matches += 1
            if check(ag_min_lon, gt_min_lon, "min_lon"): matches += 1
            if check(ag_max_lon, gt_max_lon, "max_lon"): matches += 1
            
            # 15 points per correct value
            score += (matches * 15)
            
            if matches == 4:
                feedback_parts.append("All coordinate bounds calculated correctly.")
            else:
                feedback_parts.append(f"Only {matches}/4 bounds matched ground truth.")
                feedback_parts.append(f"Ground Truth: {gt_min_lat}, {gt_max_lat}, {gt_min_lon}, {gt_max_lon}")
                feedback_parts.append(f"Agent Output: {ag_min_lat}, {ag_max_lat}, {ag_min_lon}, {ag_max_lon}")

        except (ValueError, TypeError):
            feedback_parts.append("Agent output values could not be parsed as floats.")

    # Final verdict
    passed = score >= 80  # Requires file creation + script + at least 3/4 values correct (or all 4 correct without script?)
    # Adjust logic: if they got 4/4 correct (60pts) + file (20pts) = 80pts, pass even if script missing?
    # Task desc says "Write a Python script", so script is implicitly required, but if they delete it?
    # Let's stick to score >= 80.
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }