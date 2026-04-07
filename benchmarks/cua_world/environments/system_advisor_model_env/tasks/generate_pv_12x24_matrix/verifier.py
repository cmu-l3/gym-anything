#!/usr/bin/env python3
"""
Verifier for generate_pv_12x24_matrix task.

Verification Strategy:
1. File Existence & Modification: Checks that the output file was created during the task timeframe.
2. JSON Schema: Verifies the presence of required keys (`project_size_kw`, `annual_energy_kwh`, `matrix_12x24`).
3. Matrix Structure: Ensures the matrix has exactly 12 months, and 24 hours per month.
4. Physical Consistency: Evaluates values logically (Nighttime generation must be 0, Peak midday generation must be appropriately high for a 50 MW system).
5. VLM Trajectory: Uses trajectory frames to verify the agent was actively writing a Python script to compute the results (anti-gaming).
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are verifying a computer agent's trajectory. 
The agent's task was to write a Python script using the PySAM library to simulate a 50 MW solar array and calculate a 12x24 generation matrix.

Look at these screenshots from the agent's trajectory.
Determine if the agent actively wrote or executed a Python script (e.g., using a text editor like nano, vim, gedit, or an IDE, and running it in the terminal).

Respond in JSON format:
{
    "wrote_code": true/false,
    "ran_script_in_terminal": true/false,
    "confidence": "high"/"medium"/"low",
    "reasoning": "brief explanation"
}
"""

def verify_12x24_matrix(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_dc_size_kw = metadata.get('expected_dc_size_kw', 50000)
    annual_energy_min = metadata.get('annual_energy_min_kwh', 90000000)
    annual_energy_max = metadata.get('annual_energy_max_kwh', 125000000)
    peak_hour_min = metadata.get('peak_hour_min_kw', 20000)

    score = 0
    feedback = []

    # 1. Read Metadata Result
    meta_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result_meta.json", meta_temp.name)
        with open(meta_temp.name, 'r') as f:
            meta_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read metadata: {e}"}
    finally:
        if os.path.exists(meta_temp.name):
            os.unlink(meta_temp.name)

    file_exists = meta_result.get('file_exists', False)
    file_modified = meta_result.get('file_modified', False)
    python_ran = meta_result.get('python_ran', False)

    if not file_exists:
        return {"passed": False, "score": 0, "feedback": "Output JSON file was not found."}
    
    if file_modified:
        score += 15
        feedback.append("File created/modified during task (+15)")
    else:
        feedback.append("File exists but not modified during task (+0)")

    # 2. Extract and Validate the Agent's Target File
    agent_output_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    output_data = {}
    try:
        copy_from_env("/home/ga/Documents/SAM_Projects/12x24_profile.json", agent_output_temp.name)
        with open(agent_output_temp.name, 'r') as f:
            output_data = json.load(f)
    except Exception as e:
        feedback.append("Agent output is not valid JSON")
    finally:
        if os.path.exists(agent_output_temp.name):
            os.unlink(agent_output_temp.name)

    # 3. Check JSON Schema & Structure
    if output_data:
        has_size = "project_size_kw" in output_data
        has_energy = "annual_energy_kwh" in output_data
        has_matrix = "matrix_12x24" in output_data

        if has_size and has_energy and has_matrix:
            score += 10
            feedback.append("Correct root JSON schema (+10)")
            
            matrix = output_data["matrix_12x24"]
            
            # Check Matrix structural dimensions (12 months x 24 hours)
            if isinstance(matrix, dict) and len(matrix.keys()) == 12:
                valid_hours = all(isinstance(matrix[str(m)], list) and len(matrix[str(m)]) == 24 for m in range(1, 13))
                if valid_hours:
                    score += 15
                    feedback.append("12x24 matrix structurally valid (+15)")
                else:
                    feedback.append("Matrix does not contain 24 hours per month")
            else:
                feedback.append("Matrix does not contain exactly 12 month keys")
                
            # 4. Physical Consistency Check
            if isinstance(matrix, dict) and matrix.get("1") and len(matrix.get("1")) == 24:
                try:
                    # Annual Energy check
                    annual_energy = float(output_data["annual_energy_kwh"])
                    if annual_energy_min <= annual_energy <= annual_energy_max:
                        score += 10
                        feedback.append(f"Annual energy {annual_energy/1e6:.1f} GWh is physically plausible (+10)")
                    else:
                        feedback.append(f"Annual energy {annual_energy} kWh out of expected bounds")

                    # Nighttime Check (Month 1/Jan & Month 6/Jun at Hour 2/2AM)
                    jan_night = float(matrix["1"][2])
                    jun_night = float(matrix["6"][2])
                    if jan_night == 0.0 and jun_night == 0.0:
                        score += 10
                        feedback.append("Nighttime generation correctly evaluated as 0 kW (+10)")
                    else:
                        feedback.append("Nighttime generation is non-zero (Physical error)")

                    # Peak Daytime Check (Month 6/Jun at Hour 12/Noon)
                    jun_peak = float(matrix["6"][12])
                    if jun_peak > peak_hour_min:
                        score += 10
                        feedback.append(f"Peak midday generation {jun_peak:.0f} kW is realistically high (+10)")
                    else:
                        feedback.append("Peak midday generation is unrealistically low for 50MW")
                
                except (ValueError, TypeError, KeyError) as e:
                    feedback.append(f"Data type error during physical check: {e}")

    # 5. VLM Trajectory Check (Proof of Work)
    # Use trajectory frames instead of just the final screenshot
    if query_vlm:
        from gym_anything.vlm import sample_trajectory_frames
        frames = sample_trajectory_frames(traj, n=4)
        
        vlm_result = query_vlm(images=frames, prompt=VLM_PROMPT)
        if vlm_result.get("success"):
            parsed = vlm_result.get("parsed", {})
            if parsed.get("wrote_code") or parsed.get("ran_script_in_terminal") or python_ran:
                score += 30
                feedback.append("VLM confirms code writing/execution trajectory (+30)")
            else:
                feedback.append("VLM did not observe scripting workflow")
        else:
            feedback.append("VLM query failed, relying on programmatic checks")
            if python_ran:
                score += 30
                feedback.append("Bash history indicates Python was run (+30)")

    passed = score >= 75 and file_modified and file_exists
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }