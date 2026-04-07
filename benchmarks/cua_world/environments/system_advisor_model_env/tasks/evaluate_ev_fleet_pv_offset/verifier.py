#!/usr/bin/env python3
"""Verifier for evaluate_ev_fleet_pv_offset task.

Validates exact programmatic constraints on generated load profiles
and physical/financial reconciliation using mathematical checks,
plus VLM trajectory analysis to prevent spoofing.
"""

import json
import os
import tempfile
import math
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_evaluate_ev_fleet_pv_offset(traj, env_info, task_info):
    """
    Verify that the EV fleet PV offset analysis was calculated correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_load = float(metadata.get('expected_load_kwh', 262800))
    expected_base_cost = float(metadata.get('expected_base_cost_usd', 39420))
    
    score = 0
    feedback_parts = []
    
    # ================================================================
    # Read basic exported validation data
    # ================================================================
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Check file exists and was modified
    file_exists = result.get('file_exists') is True
    file_modified = result.get('file_modified') is True
    script_exists = result.get('script_exists') is True
    
    if not file_exists:
        return {"passed": False, "score": 0, "feedback": "Required JSON output file not found."}
    
    score += 5
    if file_modified:
        score += 5
        feedback_parts.append("File created during task")
    if script_exists:
        score += 5
        feedback_parts.append("Python script saved")

    # ================================================================
    # Independent cross-check: Copy actual JSON file from agent
    # ================================================================
    agent_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/home/ga/Documents/SAM_Projects/ev_fleet_pv_analysis.json", agent_json.name)
        with open(agent_json.name, 'r') as f:
            agent_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": score, "feedback": "Agent JSON is missing or malformed."}
    finally:
        if os.path.exists(agent_json.name):
            os.unlink(agent_json.name)

    # Convert to float safely
    def safe_float(key):
        try:
            return float(agent_data.get(key, 0))
        except (ValueError, TypeError):
            return 0.0

    pv_prod = safe_float('pv_annual_production_kwh')
    load_demand = safe_float('load_annual_demand_kwh')
    grid_import = safe_float('annual_grid_import_kwh')
    grid_export = safe_float('annual_grid_export_kwh')
    cost_no_pv = safe_float('cost_without_pv_usd')
    cost_with_pv = safe_float('cost_with_pv_usd')
    annual_savings = safe_float('annual_savings_usd')

    # ================================================================
    # Math Verification 1: Deterministic Load & Baseline Cost
    # ================================================================
    # The load profile is mathematically defined: 12h @ 10kW + 12h @ 50kW = 720 kWh/day = 262,800 kWh/year
    if math.isclose(load_demand, expected_load, rel_tol=1e-4):
        score += 20
        feedback_parts.append(f"Accurate baseline load ({load_demand:.0f} kWh)")
    else:
        feedback_parts.append(f"Incorrect baseline load: expected ~{expected_load}, got {load_demand}")

    # Baseline cost without PV: 262,800 kWh * $0.15 = $39,420
    if math.isclose(cost_no_pv, expected_base_cost, rel_tol=1e-4):
        score += 15
        feedback_parts.append(f"Accurate base cost (${cost_no_pv:.2f})")
    else:
        feedback_parts.append(f"Incorrect base cost: expected ~{expected_base_cost}, got {cost_no_pv}")

    # ================================================================
    # Math Verification 2: Energy Balance Integrity
    # ================================================================
    # Net Energy = Import - Export. This must roughly equal Net Demand = Load - PV Production
    net_grid = grid_import - grid_export
    net_demand = load_demand - pv_prod
    
    # We allow some tolerance for hourly clipping/rounding differences in the sum
    if abs(net_grid - net_demand) < 10.0 and pv_prod > 50000:
        score += 20
        feedback_parts.append("Energy balance is valid")
    else:
        feedback_parts.append(f"Energy balance mismatch: NetGrid={net_grid:.1f}, NetDemand={net_demand:.1f}")

    # ================================================================
    # Math Verification 3: Financial Integrity
    # ================================================================
    # Savings must exactly equal Cost without PV minus Cost with PV
    calculated_savings = cost_no_pv - cost_with_pv
    if math.isclose(annual_savings, calculated_savings, abs_tol=5.0) and cost_with_pv > 0:
        score += 15
        feedback_parts.append("Financial savings math is valid")
    else:
        feedback_parts.append(f"Financial math mismatch: Reported Savings={annual_savings}, Expected={calculated_savings}")

    # ================================================================
    # VLM Trajectory Verification
    # ================================================================
    # Verify the agent actually wrote and executed a script (anti-spoofing)
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=4)
            final_frame = get_final_screenshot(traj)
            
            if frames and final_frame:
                all_frames = frames + [final_frame]
                prompt = (
                    "You are verifying an agent completing a Python scripting task for PySAM. "
                    "Looking at these trajectory frames, did the agent write a Python script "
                    "in a text editor/IDE and execute it in a terminal? "
                    "Respond in JSON format: {\"script_written\": true/false, \"script_executed\": true/false}"
                )
                
                vlm_res = query_vlm(images=all_frames, prompt=prompt)
                if vlm_res.get("success"):
                    parsed = vlm_res.get("parsed", {})
                    if parsed.get("script_written") and parsed.get("script_executed"):
                        score += 15
                        feedback_parts.append("VLM verified script authoring/execution")
                    else:
                        feedback_parts.append("VLM could not confirm script execution")
        except Exception as e:
            logger.warning(f"VLM trajectory verification failed: {e}")

    # ================================================================
    # Final Scoring
    # ================================================================
    # Required passing conditions: Reasonable score, file exists, and accurate load math
    passed = score >= 70 and file_exists and math.isclose(load_demand, expected_load, rel_tol=1e-4)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }