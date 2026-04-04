#!/usr/bin/env python3
"""
Verifier for compute_loop_rating_curve task.
"""

import json
import tempfile
import os
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_compute_loop_rating_curve(traj, env_info, task_info):
    """
    Verify the agent's calculation of loop rating curves.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load result JSON
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
    
    # 2. Check CSV existence and timing (20 pts)
    if result.get("csv_exists") and result.get("csv_created_during_task"):
        score += 20
        feedback_parts.append("Summary CSV created successfully.")
    elif result.get("csv_exists"):
        score += 10
        feedback_parts.append("Summary CSV exists but timestamp is old.")
    else:
        feedback_parts.append("Summary CSV not found.")

    # 3. Check Plot existence and validity (20 pts)
    plot_size = result.get("plot_size", 0)
    if result.get("plot_exists") and result.get("plot_created_during_task") and plot_size > 10000:
        score += 20
        feedback_parts.append("Plot created successfully.")
    elif result.get("plot_exists"):
        score += 5
        feedback_parts.append("Plot exists but might be invalid or old.")
    else:
        feedback_parts.append("Plot not found.")

    # 4. Verify CSV Content vs Ground Truth (60 pts)
    agent_data = result.get("csv_content", [])
    ground_truth = result.get("ground_truth", [])
    
    # Handle error in ground truth calculation
    if isinstance(ground_truth, dict) and "error" in ground_truth:
        logger.warning(f"Ground truth calculation failed: {ground_truth['error']}")
        # Fallback: check if agent data looks reasonable
        if len(agent_data) == 3:
            score += 30
            feedback_parts.append("Agent provided data, but ground truth comparison failed (awarding partial credit).")
    elif not agent_data:
        feedback_parts.append("No data in CSV.")
    else:
        # Match rows by position or RS
        matches = 0
        total_error = 0.0
        
        required_columns = ["river_station", "position", "peak_flow_cfs", "max_loop_width_cfs"]
        
        # Check columns
        if len(agent_data) > 0:
            keys = agent_data[0].keys()
            if all(col in keys for col in required_columns):
                score += 10
                feedback_parts.append("CSV has correct columns.")
            else:
                feedback_parts.append(f"CSV missing columns. Found: {list(keys)}")

        # Check values
        for gt_row in ground_truth:
            gt_pos = gt_row.get("position")
            gt_width = gt_row.get("max_loop_width", 0)
            
            # Find matching agent row
            agent_row = next((r for r in agent_data if r.get("position") == gt_pos), None)
            
            if agent_row:
                try:
                    agent_width = float(agent_row.get("max_loop_width_cfs", 0))
                    
                    # Calculate percent error
                    if gt_width > 0:
                        error = abs(agent_width - gt_width) / gt_width
                        total_error += error
                        
                        if error < 0.25: # 25% tolerance
                            matches += 1
                    else:
                        # If ground truth is 0 (unlikely for loop), just check if agent is small
                        if agent_width < 100:
                            matches += 1
                except:
                    pass
        
        # Award points for accuracy
        if matches == 3:
            score += 50
            feedback_parts.append("All 3 cross-sections calculated accurately.")
        elif matches == 2:
            score += 30
            feedback_parts.append("2 cross-sections calculated accurately.")
        elif matches == 1:
            score += 15
            feedback_parts.append("1 cross-section calculated accurately.")
        elif len(agent_data) == 3:
            # Data present but inaccurate
            score += 5
            feedback_parts.append("Data present but values deviate >25% from ground truth.")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }