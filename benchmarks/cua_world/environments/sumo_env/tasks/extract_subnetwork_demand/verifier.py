#!/usr/bin/env python3
"""
Verifier for extract_subnetwork_demand task.

Verifies that the agent correctly extracted a micro-network, adapted demand, 
and assembled a valid SUMO configuration.
"""

import os
import json
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_extract_subnetwork_demand(traj, env_info, task_info):
    """
    Verify the micro-simulation subnetwork extraction.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_width = metadata.get('target_width', 200)
    target_height = metadata.get('target_height', 200)
    tolerance = metadata.get('tolerance', 150)

    # Read result from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    task_start = result.get('task_start_time', 0)
    net_exists = result.get('net_exists', False)
    rou_exists = result.get('rou_exists', False)
    cfg_exists = result.get('cfg_exists', False)
    
    # 1. Network Extracted (15 points)
    if net_exists and result.get('net_mtime', 0) >= task_start:
        score += 15
        feedback_parts.append("Micro network created")
        
        # 2. Network Cropped properly (25 points)
        orig_edges = result.get('orig_edges', 1)
        micro_edges = result.get('micro_edges', 0)
        
        # Subnetwork should have fewer edges than original
        if 0 < micro_edges < (orig_edges * 0.8):
            score += 10
            feedback_parts.append(f"Network edge count reduced ({micro_edges} vs {orig_edges})")
        else:
            feedback_parts.append(f"Network edge count invalid ({micro_edges})")

        # Check Bounding Box size
        conv_bound_str = result.get('conv_boundary', '')
        if conv_bound_str:
            try:
                parts = [float(x) for x in conv_bound_str.split(',')]
                if len(parts) == 4:
                    width = parts[2] - parts[0]
                    height = parts[3] - parts[1]
                    
                    if abs(width - target_width) <= tolerance and abs(height - target_height) <= tolerance:
                        score += 15
                        feedback_parts.append(f"Bounding box dimensions correct (~{width:.0f}x{height:.0f})")
                    else:
                        feedback_parts.append(f"Bounding box size off target: {width:.0f}x{height:.0f}")
            except Exception as e:
                feedback_parts.append("Could not parse convBoundary")
    else:
        feedback_parts.append("Micro network missing or not created during task")

    # 3. Routes Cut (20 points)
    if rou_exists and result.get('rou_mtime', 0) >= task_start:
        score += 20
        feedback_parts.append("Micro routes created")
    else:
        feedback_parts.append("Micro routes missing or not created during task")

    # 4. Config Assembled (10 points)
    if cfg_exists and result.get('cfg_mtime', 0) >= task_start:
        score += 10
        feedback_parts.append("Configuration file created")
    else:
        feedback_parts.append("Configuration file missing")

    # 5. Simulation Execution Success (30 points)
    simulation_ran = result.get('simulation_ran', False)
    simulation_exit = result.get('simulation_exit_code', 999)
    
    if simulation_ran and simulation_exit == 0:
        score += 30
        feedback_parts.append("Simulation executed successfully (exit code 0)")
    elif simulation_ran:
        feedback_parts.append(f"Simulation failed to execute (exit code {simulation_exit})")
    else:
        feedback_parts.append("Simulation check not run (missing config)")

    # Key criteria: Simulation must run successfully to prove all components map correctly
    key_criteria_met = (simulation_ran and simulation_exit == 0) and net_exists and rou_exists
    passed = score >= 70 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }