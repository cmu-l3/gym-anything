#!/usr/bin/env python3
"""
Verifier for model_custom_orc_generator task.

Uses exact analytical cross-checks, file timestamp anti-gaming, and VLM trajectory 
verification to ensure the agent actually modeled the system properly.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def is_close(val, expected, tolerance_pct):
    """Check if value is within tolerance percentage of expected."""
    try:
        val_f = float(val)
        exp_f = float(expected)
        diff = abs(val_f - exp_f)
        max_diff = exp_f * (tolerance_pct / 100.0)
        return diff <= max_diff
    except (ValueError, TypeError):
        return False

def verify_model_custom_orc_generator(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_energy = metadata.get('expected_annual_energy_kwh', 1603200)
    expected_cf = metadata.get('expected_capacity_factor_percent', 73.205)
    expected_lcoe = metadata.get('expected_lcoe_cents_per_kwh', 6.861)
    tolerance = metadata.get('tolerance_pct', 1.0)

    feedback_parts = []
    score = 0

    # 1. Trajectory VLM Check (10 points)
    query_vlm = env_info.get('query_vlm')
    vlm_passed = False
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            images = [f for f in frames if f]
            if final:
                images.append(final)
                
            if images:
                prompt = """Look at these screenshots from a user's session.
Did the user interact with NREL System Advisor Model (SAM) desktop application OR use a terminal/editor to write/run a Python script importing PySAM?
We need to ensure they used the actual modeling tools.
Respond strictly in JSON format:
{"used_modeling_tools": true/false}
"""
                vlm_resp = query_vlm(images=images, prompt=prompt)
                if vlm_resp and vlm_resp.get("parsed", {}).get("used_modeling_tools"):
                    vlm_passed = True
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
            
    if vlm_passed:
        score += 10
        feedback_parts.append("VLM confirmed tool usage")
    else:
        feedback_parts.append("VLM could not confirm SAM/PySAM tool usage")

    # 2. Retrieve JSON result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 3. Assess File/Evidence Criteria (20 points total)
    if result.get("json_exists") and result.get("json_modified"):
        score += 10
        feedback_parts.append("Results JSON valid")
    else:
        feedback_parts.append("Results JSON missing or stale")

    if result.get("evidence_found") and result.get("is_valid_evidence") and result.get("evidence_modified"):
        score += 10
        feedback_parts.append("Modeling evidence valid")
    else:
        feedback_parts.append("Valid modeling evidence file (py/sam) missing or stale")

    # 4. Math / Analytical Verification
    ann_energy = result.get("annual_energy", 0)
    if is_close(ann_energy, expected_energy, tolerance):
        score += 25
        feedback_parts.append(f"Annual Energy exact ({ann_energy} kWh)")
    else:
        feedback_parts.append(f"Annual Energy incorrect (got {ann_energy}, expected ~{expected_energy})")

    cap_factor = result.get("capacity_factor", 0)
    if is_close(cap_factor, expected_cf, tolerance):
        score += 20
        feedback_parts.append(f"Capacity Factor exact ({cap_factor}%)")
    else:
        feedback_parts.append(f"Capacity Factor incorrect (got {cap_factor}, expected ~{expected_cf})")

    lcoe = result.get("lcoe", 0)
    if is_close(lcoe, expected_lcoe, tolerance):
        score += 25
        feedback_parts.append(f"LCOE exact ({lcoe} ¢/kWh)")
    else:
        feedback_parts.append(f"LCOE incorrect (got {lcoe}, expected ~{expected_lcoe})")

    # Final pass logic (Must pass minimum score threshold AND have the core files)
    passed = score >= 80 and result.get("json_exists") and result.get("evidence_found")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }