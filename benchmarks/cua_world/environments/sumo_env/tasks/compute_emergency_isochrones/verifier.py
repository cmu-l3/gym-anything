#!/usr/bin/env python3
"""
Verifier for compute_emergency_isochrones task.

VERIFICATION METRICS:
1. File Existence & Timestamps (10 points) - Outputs must exist and be created during task.
2. Formatting Valid (10 points) - The selection file must strictly follow the `edge:ID` format.
3. Correct Start Edge (20 points) - The starting edge must perfectly match the deterministic rule.
4. Isochrone Precision (30 points) - >95% of the edges in the agent's file are truly reachable.
5. Isochrone Recall (30 points) - >95% of the truly reachable edges are included.
"""

import json
import os
import sys
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_compute_emergency_isochrones(traj, env_info, task_info):
    """
    Verify the computed isochrone against the ground truth.
    Uses copy_from_env to read pre-exported verification data from the container.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load task result: {e}")
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # Verify Ground Truth Data
    gt_data = result.get('gt_data', {})
    if not gt_data.get('success', False):
        return {"passed": False, "score": 0, "feedback": "Ground truth calculation failed in container."}
    
    gt_start_edge = gt_data.get('start_edge')
    gt_reachable = set(gt_data.get('reachable', []))
    
    # 1. File Existence and Timestamps (10 pts)
    summary_exists = result.get('summary_exists', False)
    selection_exists = result.get('selection_exists', False)
    file_created = result.get('file_created_during_task', False)
    
    if not (summary_exists and selection_exists):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Missing output files (both summary and selection required)."
        }
        
    if file_created:
        score += 10
        feedback_parts.append("Files successfully generated.")
    else:
        feedback_parts.append("Files exist but were not created during the task run (possible cheating).")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Extract Agent Lines
    summary_lines = result.get('summary_lines', [])
    selection_lines = result.get('selection_lines', [])
    
    # 2. Format Validation (10 pts)
    agent_edges = set()
    format_errors = 0
    
    for line in selection_lines:
        if line.startswith("edge:"):
            agent_edges.add(line[5:])
        else:
            format_errors += 1
            
    if format_errors == 0 and len(selection_lines) > 0:
        score += 10
        feedback_parts.append("Selection file formatting perfectly matches 'edge:ID'.")
    elif len(selection_lines) > 0:
        feedback_parts.append(f"Format error: {format_errors} lines do not start with 'edge:'.")
    else:
        feedback_parts.append("Selection file is empty.")

    # 3. Correct Start Edge (20 pts)
    agent_start_edge = summary_lines[0] if len(summary_lines) > 0 else ""
    if agent_start_edge == gt_start_edge:
        score += 20
        feedback_parts.append(f"Correct start edge identified ({gt_start_edge}).")
    else:
        feedback_parts.append(f"Incorrect start edge: Expected '{gt_start_edge}', got '{agent_start_edge}'.")

    # 4 & 5. Isochrone Precision and Recall (30 pts each)
    true_positives = agent_edges.intersection(gt_reachable)
    
    precision = len(true_positives) / len(agent_edges) if len(agent_edges) > 0 else 0.0
    recall = len(true_positives) / len(gt_reachable) if len(gt_reachable) > 0 else 0.0
    
    if precision > 0.95:
        score += 30
        feedback_parts.append(f"Precision high: {precision*100:.1f}%.")
    else:
        feedback_parts.append(f"Precision low: {precision*100:.1f}%.")
        
    if recall > 0.95:
        score += 30
        feedback_parts.append(f"Recall high: {recall*100:.1f}%.")
    else:
        feedback_parts.append(f"Recall low: {recall*100:.1f}%.")

    # Overall Status Calculation
    # Pass requires >=80 pts AND perfect Start Edge AND perfect format
    passed = (
        score >= 80 and 
        agent_start_edge == gt_start_edge and 
        format_errors == 0
    )

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "gt_start_edge": gt_start_edge,
            "agent_start_edge": agent_start_edge,
            "gt_reachable_count": len(gt_reachable),
            "agent_reachable_count": len(agent_edges),
            "precision": precision,
            "recall": recall
        }
    }