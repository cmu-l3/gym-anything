#!/usr/bin/env python3
"""
Verifier for compare_csp_cooling_systems task.

Verification Strategy:
1. File Existence: Check if target JSON exists and was modified during the task.
2. Independent JSON parsing: Native Python reading of the output file.
3. Physics Sanity Checks: Validates standard thermodynamic limits (Wet Energy > Dry Energy, Wet Water >> Dry Water, Utility scale).
4. Math Validation: Verifies that the derived fields (penalty/savings) are calculated accurately.
5. VLM / Activity check: Ensures SAM tools or PySAM scripts were actually used.
"""

import json
import tempfile
import os

def verify_compare_csp_cooling_systems(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback = []

    # 1. Read task_result.json
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result_data = {}
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        pass
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Read target cooling_comparison.json
    temp_target = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    target_data = {}
    try:
        copy_from_env("/home/ga/Documents/SAM_Projects/cooling_comparison.json", temp_target.name)
        with open(temp_target.name, 'r') as f:
            target_data = json.load(f)
    except Exception:
        pass
    finally:
        if os.path.exists(temp_target.name):
            os.unlink(temp_target.name)

    # CRITERION 1: File existence and creation (10 pts)
    if result_data.get("file_exists") and result_data.get("file_modified"):
        score += 10
        feedback.append("File created/modified during task.")
    elif result_data.get("file_exists"):
        score += 5
        feedback.append("File exists but was not modified during task.")
    else:
        feedback.append("Output JSON not found.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # CRITERION 2: Extract and validate schema (10 pts)
    try:
        wet_e = float(target_data.get('wet_cooling_annual_energy_kwh', 0))
        wet_w = float(target_data.get('wet_cooling_annual_water_use_m3', 0))
        dry_e = float(target_data.get('dry_cooling_annual_energy_kwh', 0))
        dry_w = float(target_data.get('dry_cooling_annual_water_use_m3', 0))
        penalty = float(target_data.get('energy_penalty_percent', 0))
        savings = float(target_data.get('water_savings_m3', 0))
    except (ValueError, TypeError):
        feedback.append("JSON schema invalid or contains non-numeric values.")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

    # Reject exact placeholder values from README
    if wet_e == 123456789.0 or wet_w == 123456.0:
        feedback.append("Detected exact placeholder values from README. Rejected.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    if all(v != 0 for v in [wet_e, wet_w, dry_e, dry_w]):
        score += 10
        feedback.append("Extracted all required numeric fields.")
    else:
        feedback.append("Missing or zero values in required fields.")

    # CRITERION 3: Scale Check (15 pts)
    if wet_e > 10000000 and dry_e > 10000000:  # > 10 GWh
        score += 15
        feedback.append("Energy production is at realistic utility scale.")
    else:
        feedback.append("Energy production too low for utility scale CSP.")

    # CRITERION 4: Physics: Water (15 pts)
    # Dry cooling uses only a fraction of water (mostly mirror washing)
    if dry_w > 0 and wet_w > (dry_w * 5):
        score += 15
        feedback.append("Water physics correct (Wet >> Dry).")
    else:
        feedback.append(f"Water physics failed. Wet: {wet_w}, Dry: {dry_w}")

    # CRITERION 5: Physics: Energy (15 pts)
    if wet_e > dry_e:
        score += 15
        feedback.append("Energy physics correct (Wet > Dry).")
    else:
        feedback.append(f"Energy physics failed. Wet: {wet_e}, Dry: {dry_e}")

    # CRITERION 6: Math check (15 pts)
    calc_penalty = ((wet_e - dry_e) / wet_e) * 100 if wet_e > 0 else 0
    calc_savings = wet_w - dry_w

    math_ok = True
    if abs(penalty - calc_penalty) > 1.0:
        math_ok = False
        feedback.append(f"Penalty math wrong. Expected ~{calc_penalty:.2f}%, got {penalty}%")
    if abs(savings - calc_savings) > 10.0:
        math_ok = False
        feedback.append(f"Savings math wrong. Expected ~{calc_savings}, got {savings}")

    if math_ok:
        score += 15
        feedback.append("Derived math fields correct.")

    # CRITERION 7: Activity / VLM Check (20 pts)
    python_ran = result_data.get("python_ran")
    if python_ran is True or str(python_ran).lower() == 'true':
        score += 20
        feedback.append("Python/PySAM usage detected.")
    else:
        # Fallback to VLM Trajectory Verification
        query_vlm = env_info.get('query_vlm')
        vlm_passed = False
        if query_vlm:
            try:
                from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
                frames = sample_trajectory_frames(traj, n=3)
                final = get_final_screenshot(traj)
                if final:
                    frames.append(final)
                
                if frames:
                    prompt = (
                        "You are verifying a solar engineering task. Look at these screenshots from the agent's trajectory. "
                        "Did the user actively use the 'System Advisor Model' (SAM) GUI application, OR "
                        "use an editor/terminal to write a Python script for simulation? "
                        "Respond in JSON format: {'used_tools': true/false, 'reasoning': '...'}"
                    )
                    vlm_res = query_vlm(prompt=prompt, images=frames)
                    if vlm_res.get('success') and vlm_res.get('parsed', {}).get('used_tools'):
                        vlm_passed = True
            except Exception:
                pass
        
        if vlm_passed:
            score += 20
            feedback.append("VLM verified SAM GUI / script usage.")
        else:
            feedback.append("No Python usage detected, and VLM could not confirm SAM GUI activity.")

    # Final evaluation logic: Require passing score AND physical logic consistency
    physics_passed = (wet_e > dry_e) and (dry_w > 0 and wet_w > (dry_w * 5))
    passed = (score >= 75) and physics_passed

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }