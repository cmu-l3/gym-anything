#!/usr/bin/env python3
"""Verifier for simulate_pv_fleet_vpp task.

Uses physics-based cross-checks, invariant checking, AND VLM trajectory verification.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_simulate_pv_fleet_vpp(traj, env_info, task_info):
    """
    Verify the VPP fleet simulation results.
    
    Scoring Breakdown (100 Points Total):
    - Output JSON Valid & Modified: 15 points
    - Python Script Exists & Used PySAM: 10 points
    - Fleet Capacity Valid (exactly 25.0): 10 points
    - Energy Summation Check: 15 points
    - Peak Magnitude Check (kW conversion bounds): 15 points
    - Physical Logic Invariant (180 > 90, 270): 15 points
    - Peak Hour Valid: 5 points
    - VLM Trajectory Check (Agent wrote script): 15 points
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available."}

    score = 0
    feedback_parts = []
    
    # 1. Read the export_result.sh metadata
    temp_meta = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_meta.name)
        with open(temp_meta.name, 'r') as f:
            meta_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read metadata: {e}"}
    finally:
        if os.path.exists(temp_meta.name):
            os.unlink(temp_meta.name)

    # Pre-checks from metadata
    script_exists = meta_result.get('script_exists') is True or str(meta_result.get('script_exists')) == 'true'
    script_pysam = meta_result.get('script_contains_pysam') is True or str(meta_result.get('script_contains_pysam')) == 'true'
    json_exists = meta_result.get('json_exists') is True or str(meta_result.get('json_exists')) == 'true'
    json_modified = meta_result.get('json_modified_during_task') is True or str(meta_result.get('json_modified_during_task')) == 'true'
    
    if script_exists and script_pysam:
        score += 10
        feedback_parts.append("Script exists and imports PySAM")
    elif script_exists:
        score += 5
        feedback_parts.append("Script exists (missing PySAM import?)")
    else:
        feedback_parts.append("Script file not found")
        
    if not json_exists:
        feedback_parts.append("JSON results file NOT found")
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    if json_modified:
        score += 5
        feedback_parts.append("Results modified during task")

    # 2. Read the actual VPP results JSON
    agent_json_path = task_info.get('metadata', {}).get('expected_json_filename', '/home/ga/Documents/SAM_Projects/vpp_fleet_results.json')
    temp_results = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    vpp_data = None
    
    try:
        copy_from_env(agent_json_path, temp_results.name)
        with open(temp_results.name, 'r') as f:
            vpp_data = json.load(f)
        score += 10
        feedback_parts.append("JSON is validly formatted")
    except Exception as e:
        feedback_parts.append(f"Output JSON parsing failed: {e}")
    finally:
        if os.path.exists(temp_results.name):
            os.unlink(temp_results.name)
            
    # 3. Deep Analysis of the JSON Content
    if vpp_data and isinstance(vpp_data, dict):
        # Capacity check
        capacity = vpp_data.get('total_fleet_capacity_kw', 0)
        if abs(capacity - 25.0) < 0.1:
            score += 10
            feedback_parts.append("Fleet capacity is 25kW")
        else:
            feedback_parts.append(f"Fleet capacity incorrect: {capacity} != 25.0")
            
        # Summation check
        total_energy = vpp_data.get('total_annual_energy_kwh', 0)
        ind_energies = vpp_data.get('individual_annual_energies', {})
        
        if isinstance(ind_energies, dict) and len(ind_energies) == 5:
            expected_azimuths = ["90", "135", "180", "225", "270"]
            has_all_azimuths = all(str(a) in ind_energies for a in expected_azimuths)
            
            if has_all_azimuths:
                calculated_sum = sum(float(v) for v in ind_energies.values())
                if total_energy > 0 and abs(calculated_sum - total_energy) / total_energy < 0.05:
                    score += 15
                    feedback_parts.append("Energy aggregation is mathematically correct")
                else:
                    feedback_parts.append("Total energy does not match sum of individual energies")
                
                # Physical Logic Invariant Check (180 should produce more than 90 and 270 in Phoenix)
                e_90 = float(ind_energies["90"])
                e_180 = float(ind_energies["180"])
                e_270 = float(ind_energies["270"])
                
                if e_180 > e_90 and e_180 > e_270:
                    score += 15
                    feedback_parts.append("Physical invariants passed (South > East/West)")
                else:
                    feedback_parts.append("Physical invariants failed (South not highest)")
            else:
                feedback_parts.append("Missing expected azimuths in individual_annual_energies")
        else:
            feedback_parts.append("individual_annual_energies missing or invalid format")
            
        # Peak Magnitude Check
        peak_kw = float(vpp_data.get('peak_hourly_generation_kw', 0))
        # 25kW DC system should peak somewhere between 18kW and 25kW AC.
        if 18.0 <= peak_kw <= 26.0:
            score += 15
            feedback_parts.append(f"Peak magnitude valid ({peak_kw:.1f} kW)")
        elif 18000 <= peak_kw <= 26000:
            # Agent forgot to convert Watts to kW
            score += 5
            feedback_parts.append(f"Peak magnitude valid but wrong units ({peak_kw} W instead of kW)")
        else:
            feedback_parts.append(f"Peak magnitude implausible ({peak_kw})")
            
        # Peak Hour
        peak_hour = vpp_data.get('peak_generation_hour_index')
        if isinstance(peak_hour, int) and 0 <= peak_hour <= 8759:
            score += 5
            feedback_parts.append("Peak hour index in bounds")
        else:
            feedback_parts.append("Peak hour index invalid")

    # 4. VLM Trajectory Verification
    if query_vlm:
        from gym_anything.vlm import sample_trajectory_frames
        frames = sample_trajectory_frames(traj, n=4)
        if frames:
            prompt = """You are evaluating an AI agent performing a coding task.
Look at these screenshots taken during the task.
Did the agent use a text editor (e.g., nano, vim, gedit, terminal) or IDE to actively write Python code?
Look for PySAM imports or simulation logic in the code.
Respond in JSON format:
{
    "wrote_code": true/false,
    "reasoning": "Brief explanation of what the agent is doing"
}"""
            vlm_result = query_vlm(prompt=prompt, images=frames)
            if vlm_result.get("success"):
                parsed = vlm_result.get("parsed", {})
                if parsed.get("wrote_code", False):
                    score += 15
                    feedback_parts.append("VLM verified code authoring")
                else:
                    feedback_parts.append("VLM did not observe active coding")
            else:
                feedback_parts.append("VLM query failed")
    else:
        # If VLM is absent but programmatic verification is strong, grant the points
        if script_pysam and json_modified:
            score += 15
            feedback_parts.append("Auto-granted VLM points (VLM unavailable but script modified)")

    # Overall pass threshold: 75 points and core files exist/valid
    passed = score >= 75 and json_exists and script_exists
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }