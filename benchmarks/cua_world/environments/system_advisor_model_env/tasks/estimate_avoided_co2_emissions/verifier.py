#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are verifying if a computer agent successfully completed a task to calculate solar energy and CO2 emissions.

Look closely at these trajectory screenshots.
1. Is there evidence that the agent wrote a Python script (e.g., in a terminal, text editor, or IDE)?
2. Does the code include PySAM or formulas for energy/CO2 calculations?
3. Is there evidence the script was executed?

Respond in JSON format:
{
    "wrote_code": true/false,
    "executed_script": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation"
}
"""

def verify_estimate_avoided_co2_emissions(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_ef = metadata.get('emission_factor', 0.3856)
    expected_car_factor = metadata.get('car_factor', 4.6)
    expected_tree_factor = metadata.get('tree_factor', 0.060)
    expected_kw = metadata.get('system_capacity_kw', 50.0)
    min_kwh = metadata.get('min_annual_kwh', 50000)
    max_kwh = metadata.get('max_annual_kwh', 100000)

    score = 0
    feedback_parts = []
    
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

    pv = result.get("parsed_values", {})

    # 1. File exists & created during task (15 pts)
    file_exists = result.get("file_exists", False)
    created_during = result.get("file_created_during_task", False)
    
    if file_exists and created_during:
        score += 15
        feedback_parts.append("File exists & created during task (+15)")
    elif file_exists:
        feedback_parts.append("File exists but NOT created during task (potential gaming)")
    else:
        feedback_parts.append("Output file NOT found")
        # Early exit if file is totally missing
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. Valid JSON with all fields (10 pts)
    valid_json = result.get("valid_json", False)
    has_all = result.get("has_all_fields", False)
    if valid_json and has_all:
        score += 10
        feedback_parts.append("Valid JSON with all fields (+10)")
    elif valid_json:
        score += 4
        feedback_parts.append(f"Valid JSON but missing fields: {result.get('missing_fields', [])} (+4)")
    else:
        feedback_parts.append("Invalid or unparseable JSON")

    # Math validations helper
    def get_float(val):
        try:
            return float(val) if val is not None else None
        except (ValueError, TypeError):
            return None

    annual_kwh = get_float(pv.get("annual_energy_kwh"))
    annual_mwh = get_float(pv.get("annual_energy_mwh"))
    ef = get_float(pv.get("emission_factor_mt_co2_per_mwh"))
    co2 = get_float(pv.get("avoided_co2_mt"))
    cars = get_float(pv.get("equivalent_cars_removed"))
    trees = get_float(pv.get("equivalent_trees_planted"))
    cap = get_float(pv.get("system_capacity_kw"))

    # 3. Annual energy in range (10 pts)
    if annual_kwh is not None:
        if min_kwh <= annual_kwh <= max_kwh:
            score += 10
            feedback_parts.append(f"Energy {annual_kwh:.1f} kWh in range (+10)")
        elif 30000 <= annual_kwh <= 120000:
            score += 5
            feedback_parts.append(f"Energy {annual_kwh:.1f} kWh out of ideal range (+5)")
        else:
            feedback_parts.append(f"Energy {annual_kwh:.1f} kWh highly implausible")
    else:
        feedback_parts.append("Missing annual_energy_kwh")

    # 4. MWh consistent (5 pts)
    if annual_kwh is not None and annual_mwh is not None:
        expected_mwh = annual_kwh / 1000.0
        if expected_mwh > 0 and abs(annual_mwh - expected_mwh) / expected_mwh < 0.001:
            score += 5
            feedback_parts.append("MWh calculation correct (+5)")
        else:
            feedback_parts.append(f"MWh mismatch: got {annual_mwh}, expected {expected_mwh}")
    else:
        feedback_parts.append("Cannot verify MWh")

    # 5. Emission factor correct (5 pts)
    if ef is not None:
        if abs(ef - expected_ef) < 0.0001:
            score += 5
            feedback_parts.append("Emission factor correct (+5)")
        else:
            feedback_parts.append(f"Emission factor mismatch: got {ef}")

    # 6. CO2 Calculation (10 pts)
    if co2 is not None and annual_mwh is not None:
        expected_co2 = annual_mwh * expected_ef
        if expected_co2 > 0 and abs(co2 - expected_co2) / expected_co2 < 0.01:
            score += 10
            feedback_parts.append("CO2 calculation correct (+10)")
        else:
            feedback_parts.append(f"CO2 calculation mismatch: got {co2}, expected ~{expected_co2}")
            
    # 7. Cars Equivalency (10 pts)
    if cars is not None and co2 is not None:
        expected_cars = co2 / expected_car_factor
        if expected_cars > 0 and abs(cars - expected_cars) / expected_cars < 0.01:
            score += 10
            feedback_parts.append("Cars equivalency correct (+10)")
        else:
            feedback_parts.append("Cars calculation mismatch")

    # 8. Trees Equivalency (10 pts)
    if trees is not None and co2 is not None:
        expected_trees = co2 / expected_tree_factor
        if expected_trees > 0 and abs(trees - expected_trees) / expected_trees < 0.01:
            score += 10
            feedback_parts.append("Trees equivalency correct (+10)")
        else:
            feedback_parts.append("Trees calculation mismatch")

    # 9. System Capacity (5 pts)
    if cap is not None:
        if abs(cap - expected_kw) < 0.5:
            score += 5
            feedback_parts.append(f"System capacity {cap}kW correct (+5)")
        else:
            feedback_parts.append(f"System capacity mismatch: got {cap}")

    # 10. VLM Trajectory Verification (20 pts)
    vlm_score = 0
    try:
        query_vlm = env_info.get('query_vlm')
        if query_vlm:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames
            
            if images:
                vlm_result = query_vlm(images=images, prompt=VLM_PROMPT)
                if vlm_result.get('success'):
                    parsed = vlm_result.get('parsed', {})
                    if parsed.get('wrote_code'):
                        vlm_score += 10
                        feedback_parts.append("VLM: Agent wrote code (+10)")
                    if parsed.get('executed_script'):
                        vlm_score += 10
                        feedback_parts.append("VLM: Agent executed code (+10)")
                else:
                    feedback_parts.append("VLM query failed")
            else:
                feedback_parts.append("No trajectory images available for VLM")
    except Exception as e:
        logger.error(f"VLM verification error: {e}")
        feedback_parts.append("VLM error occurred")

    score += vlm_score

    # Passing criteria
    passed = score >= 70 and file_exists and created_during

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }