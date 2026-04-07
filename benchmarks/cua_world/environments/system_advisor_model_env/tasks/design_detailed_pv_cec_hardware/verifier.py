#!/usr/bin/env python3
"""
Verifier for design_detailed_pv_cec_hardware task.

Uses multi-signal verification:
1. File existence and timestamps (anti-gaming).
2. Deep introspection of the .sam file (checks actual hardware IDs were used).
3. Data consistency in the output JSON.
4. Trajectory validation via VLM to ensure SAM UI usage.
"""

import json
import tempfile
import os
import logging
import traceback

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_design_detailed_pv_cec_hardware(traj, env_info, task_info):
    """
    Verify the hardware design task.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_inverter_count = metadata.get('expected_inverter_count', 4)
    expected_dc_capacity_min = metadata.get('expected_dc_capacity_min', 45.0)
    expected_dc_capacity_max = metadata.get('expected_dc_capacity_max', 55.0)
    expected_module_brand = metadata.get('expected_module_brand', 'Canadian Solar').lower()
    expected_inverter_brand = metadata.get('expected_inverter_brand', 'SMA').lower()

    # Read exported JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read result: {traceback.format_exc()}")
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    sam_exists = result.get('sam_exists', False)
    sam_modified = result.get('sam_modified', False)
    json_exists = result.get('json_exists', False)
    json_modified = result.get('json_modified', False)

    # 1. File existence & Modification (20 pts)
    if sam_exists and json_exists and sam_modified and json_modified:
        score += 20
        feedback_parts.append("✅ Files created successfully.")
    elif sam_exists or json_exists:
        score += 5
        feedback_parts.append("❌ Missing one or more required output files.")
    else:
        return {"passed": False, "score": 0, "feedback": "❌ Required output files completely missing."}

    # 2. Detailed PV Technology usage (15 pts)
    if result.get('sam_pvsamv1', False):
        score += 15
        feedback_parts.append("✅ Used Detailed PV (pvsamv1) model.")
    else:
        feedback_parts.append("❌ Did not use Detailed PV model.")

    # 3. Hardware selection matches in both SAM file and JSON
    # Module (15 pts)
    mod_selected = str(result.get('module_selected', '')).lower()
    if result.get('sam_canadian', False) and expected_module_brand in mod_selected:
        score += 15
        feedback_parts.append("✅ Canadian Solar module successfully specified.")
    else:
        feedback_parts.append(f"❌ Module selection incorrect or missing (Expected: {expected_module_brand}).")

    # Inverter (15 pts)
    inv_selected = str(result.get('inverter_selected', '')).lower()
    if result.get('sam_sma', False) and expected_inverter_brand in inv_selected:
        score += 15
        feedback_parts.append("✅ SMA inverter successfully specified.")
    else:
        feedback_parts.append(f"❌ Inverter selection incorrect or missing (Expected: {expected_inverter_brand}).")

    # 4. Check numerical specifications from JSON
    try:
        inv_count = int(result.get('inverter_count', 0))
    except ValueError:
        inv_count = 0

    try:
        dc_cap = float(result.get('dc_capacity', 0.0))
    except ValueError:
        dc_cap = 0.0

    # Inverter Count (15 pts)
    if inv_count == expected_inverter_count:
        score += 15
        feedback_parts.append("✅ Exactly 4 inverters configured.")
    else:
        feedback_parts.append(f"❌ Inverter count was {inv_count}, expected {expected_inverter_count}.")

    # DC Capacity Bounds (20 pts)
    if expected_dc_capacity_min <= dc_cap <= expected_dc_capacity_max:
        score += 20
        feedback_parts.append(f"✅ System capacity ({dc_cap} kW) is within target bounds (45-55 kW).")
    else:
        feedback_parts.append(f"❌ System capacity ({dc_cap} kW) outside expected range.")

    # 5. VLM Trajectory Verification to avoid script-only gaming without tool interaction
    if query_vlm:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        
        prompt = """
        You are verifying a task where an agent uses NREL SAM (System Advisor Model).
        The user must configure a detailed PV system, browsing CEC databases for 'Canadian Solar' and 'SMA' components.
        Look at these trajectory screenshots.
        1. Do you see the SAM desktop GUI being interacted with?
        2. Do you see evidence of the agent browsing the CEC Module or Inverter databases (tables/filters visible)?
        3. Do you see the System Design page (configuring string sizes, inverters)?
        
        Respond with JSON:
        {
            "sam_gui_used": true/false,
            "browsed_databases": true/false,
            "configured_design": true/false
        }
        """
        
        vlm_result = query_vlm(images=frames + [final], prompt=prompt)
        
        if vlm_result and vlm_result.get("success"):
            parsed = vlm_result.get("parsed", {})
            if parsed.get("sam_gui_used") and parsed.get("browsed_databases"):
                feedback_parts.append("✅ VLM verified active SAM GUI database interaction.")
            elif not parsed.get("sam_gui_used"):
                feedback_parts.append("⚠️ VLM did not detect SAM GUI usage (might be script-only).")
                # Penalty if completely hidden but they produced a valid sam file (not inherently wrong, but suspicious)
                if score > 80:
                    score -= 10
        else:
            feedback_parts.append("⚠️ VLM verification skipped or failed.")

    passed = score >= 75 and sam_exists and json_exists and expected_module_brand in mod_selected
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }