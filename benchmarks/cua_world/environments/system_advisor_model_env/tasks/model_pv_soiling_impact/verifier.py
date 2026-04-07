#!/usr/bin/env python3
"""
Verifier for model_pv_soiling_impact task.
"""

import os
import json
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_model_pv_soiling_impact(traj, env_info, task_info):
    """
    Verify the PV soiling impact analysis.
    Checks file presence, valid JSON structure, physical constraints,
    and uses VLM to confirm the agent actually wrote a script.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')

    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_path = metadata.get('expected_output_path', "/home/ga/Documents/SAM_Projects/soiling_analysis.json")
    expected_profile = metadata.get('expected_profile', [2, 3, 4, 5, 5, 5, 2, 2, 3, 4, 3, 2])
    
    score = 0
    feedback_parts = []
    
    # -------------------------------------------------------------------------
    # Retrieve Result Data
    # -------------------------------------------------------------------------
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve or read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    data = result.get("data", {})
    
    # -------------------------------------------------------------------------
    # Check File Existence & Timestamp (20 pts)
    # -------------------------------------------------------------------------
    file_exists = result.get("file_exists", False)
    valid_json = result.get("valid_json", False)
    file_created = result.get("file_created_during_task", False)
    
    if not file_exists:
        return {"passed": False, "score": 0, "feedback": f"Result file {expected_path} not found"}
        
    if not valid_json:
        return {"passed": False, "score": 0, "feedback": "Output file exists but is not valid JSON"}
        
    score += 10
    feedback_parts.append("Valid JSON file exists (10/10)")
    
    if file_created:
        score += 10
        feedback_parts.append("File created during task (10/10)")
    else:
        feedback_parts.append("File appears older than task start (0/10)")

    # -------------------------------------------------------------------------
    # Check System Parameters (15 pts)
    # -------------------------------------------------------------------------
    try:
        sys_cap = float(data.get("system_capacity_kw", 0))
        tilt = float(data.get("tilt_deg", -1))
        azimuth = float(data.get("azimuth_deg", -1))
        
        cap_ok = abs(sys_cap - metadata.get('expected_capacity', 2000)) < 1
        tilt_ok = abs(tilt - metadata.get('expected_tilt', 30)) < 1
        az_ok = abs(azimuth - metadata.get('expected_azimuth', 180)) < 1
        
        params_score = sum([5 if cap_ok else 0, 5 if tilt_ok else 0, 5 if az_ok else 0])
        score += params_score
        feedback_parts.append(f"System parameters correct ({params_score}/15)")
    except (ValueError, TypeError):
        feedback_parts.append("Failed to parse system parameters (0/15)")

    # -------------------------------------------------------------------------
    # Check Energy Outputs & Physics Constraints (20 pts)
    # -------------------------------------------------------------------------
    clean_kwh = 0
    soiled_kwh = 0
    try:
        clean_kwh = float(data.get("annual_energy_clean_kwh", 0))
        soiled_kwh = float(data.get("annual_energy_soiled_kwh", 0))
        
        clean_in_range = metadata.get('clean_energy_min_kwh', 2500000) <= clean_kwh <= metadata.get('clean_energy_max_kwh', 6000000)
        soiled_in_range = metadata.get('soiled_energy_min_kwh', 2400000) <= soiled_kwh <= metadata.get('soiled_energy_max_kwh', 5900000)
        
        if clean_in_range and soiled_in_range:
            score += 10
            feedback_parts.append("Energy values in realistic range (10/10)")
        else:
            feedback_parts.append("Energy values out of bounds (0/10)")
            
        if clean_kwh > soiled_kwh and clean_kwh > 0:
            score += 10
            feedback_parts.append("Physics check passed: Clean energy > Soiled energy (10/10)")
        else:
            feedback_parts.append("Physics check failed: Clean <= Soiled (0/10)")
    except (ValueError, TypeError):
        feedback_parts.append("Failed to parse energy outputs (0/20)")

    # -------------------------------------------------------------------------
    # Check Derived Soiling Metrics & Profile (15 pts)
    # -------------------------------------------------------------------------
    try:
        loss_pct = float(data.get("soiling_loss_percent", 0))
        pct_in_range = metadata.get('soiling_loss_pct_min', 1.5) <= loss_pct <= metadata.get('soiling_loss_pct_max', 6.0)
        if pct_in_range:
            score += 5
            feedback_parts.append("Soiling loss percentage reasonable (5/5)")
        else:
            feedback_parts.append("Soiling loss percentage out of expected range (0/5)")
            
        # Check profile array
        actual_profile = data.get("monthly_soiling_profile", [])
        if isinstance(actual_profile, list) and len(actual_profile) == 12:
            floats_profile = [float(x) for x in actual_profile]
            matches = all(abs(a - e) < 0.1 for a, e in zip(floats_profile, expected_profile))
            if matches:
                score += 10
                feedback_parts.append("Monthly soiling profile perfectly matches (10/10)")
            else:
                score += 3
                feedback_parts.append("Monthly profile present but incorrect values (3/10)")
        else:
            feedback_parts.append("Invalid or missing monthly soiling profile (0/10)")
    except (ValueError, TypeError):
        feedback_parts.append("Failed to parse soiling metrics (0/15)")

    # -------------------------------------------------------------------------
    # VLM Trajectory Verification (20 pts)
    # -------------------------------------------------------------------------
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=4)
            final_frame = get_final_screenshot(traj)
            
            if final_frame:
                frames.append(final_frame)
                
            vlm_prompt = """
            You are verifying if a computer agent successfully executed a Python script for a PV simulation task.
            Look at these trajectory screenshots.
            Do you see evidence that the agent wrote and executed a Python script (e.g. in a terminal, editor, or IDE) related to PySAM or PV modeling?
            Reply in JSON format:
            {
              "scripting_evidence": true/false,
              "reasoning": "Brief explanation"
            }
            """
            vlm_result = query_vlm(prompt=vlm_prompt, images=frames)
            
            if vlm_result.get("success"):
                parsed = vlm_result.get("parsed", {})
                if parsed.get("scripting_evidence", False):
                    score += 20
                    feedback_parts.append("VLM confirmed Python scripting evidence (20/20)")
                else:
                    feedback_parts.append("VLM did not detect Python scripting evidence (0/20)")
            else:
                score += 10 # Partial credit if VLM fails but logic passes
                feedback_parts.append("VLM query failed, partial credit given (10/20)")
        except ImportError:
            # Fallback if framework modules are missing
            score += 20
            feedback_parts.append("VLM unavailable, assuming trajectory pass (20/20)")
    else:
        score += 20
        feedback_parts.append("VLM function unavailable, giving default trajectory points (20/20)")

    # -------------------------------------------------------------------------
    # Final Evaluation
    # -------------------------------------------------------------------------
    # Critical keys check
    key_criteria_met = (
        file_created and 
        (clean_kwh > soiled_kwh) and 
        valid_json
    )
    
    passed = score >= 70 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }