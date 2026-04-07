#!/usr/bin/env python3
"""
Verifier for model_csp_power_tower task.

Verification Strategy:
1. File verification: Uses copy_from_env to read export_result.json.
2. Anti-gaming: Checks creation timestamps for both Python script and Results JSON.
3. Content audit: Checks Python script for TcsmoltenSalt imports, P_ref setting, and execution.
4. Physics sanity check: Annual energy, capacity factor, and LCOE must be physically plausible.
5. VLM verification (Trajectory-based): Verifies agent actually wrote/ran code in the UI.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# VLM Prompt specifically for identifying Python scripting of PySAM models
VLM_PROMPT = """You are verifying if a computer agent successfully modeled a CSP Power Tower using PySAM in a Linux environment.

TASK: Write and execute a Python script to model a 100 MW Molten Salt Power Tower with 10h thermal storage.

Look closely at these trajectory screenshots and determine:
1. Did the agent open a terminal or code editor to write Python code?
2. Is there evidence of PySAM being used (e.g., imports like 'PySAM.TcsmoltenSalt', 'import PySAM')?
3. Did the agent execute the script?

Respond in JSON format:
{
    "wrote_python_code": true/false,
    "used_pysam_module": true/false,
    "executed_script": true/false,
    "confidence": "low/medium/high",
    "reasoning": "Briefly explain what evidence is visible in the screenshots."
}
"""

def verify_model_csp_power_tower(traj, env_info, task_info):
    score = 0
    feedback_parts = []
    
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. READ METADATA BOUNDS
    metadata = task_info.get('metadata', {})
    expected_pref = metadata.get('expected_pref', 100)
    expected_tshours = metadata.get('expected_tshours', 10)
    expected_solarm = metadata.get('expected_solarm', 2.4)
    cf_min = metadata.get('plausible_cf_min', 30)
    cf_max = metadata.get('plausible_cf_max', 75)
    gwh_min = metadata.get('plausible_annual_gwh_min', 200)
    gwh_max = metadata.get('plausible_annual_gwh_max', 800)
    lcoe_min = metadata.get('plausible_lcoe_min', 4)
    lcoe_max = metadata.get('plausible_lcoe_max', 30)

    # 2. RETRIEVE AND PARSE EXPORTED JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 3. VERIFY FILES AND ANTI-GAMING (30 points)
    json_exists = result.get('results_json_exists', False)
    json_fresh = result.get('results_json_modified_after_start', False)
    script_exists = result.get('script_exists', False)
    script_fresh = result.get('script_modified_after_start', False)

    if json_exists and json_fresh:
        score += 15
        feedback_parts.append("✅ Fresh results JSON found")
    elif json_exists:
        feedback_parts.append("❌ Results JSON exists but was not created during task")

    if script_exists and script_fresh:
        score += 15
        feedback_parts.append("✅ Fresh Python script found")
    elif script_exists:
        feedback_parts.append("❌ Script exists but was not created during task")

    # If neither file exists freshly, early fail
    if not (json_fresh and script_fresh):
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts) if feedback_parts else "No valid files created.",
            "details": result
        }

    # 4. VERIFY SCRIPT CONTENT (15 points)
    if result.get('script_imports_tcsmoltensalt'):
        score += 5
    if result.get('script_sets_P_ref'):
        score += 5
    if result.get('script_calls_execute'):
        score += 5
        feedback_parts.append("✅ Script contains correct PySAM logic")
    else:
        feedback_parts.append("❌ Script missing expected execute/PySAM calls")

    # 5. VERIFY CONFIGURATION PARAMETERS (15 points)
    try:
        pref = float(result.get('P_ref_mw', 0))
        tshours = float(result.get('tshours', 0))
        solarm = float(result.get('solar_multiple', 0))
        
        if abs(pref - expected_pref) < 5.0:
            score += 5
        if abs(tshours - expected_tshours) < 1.0:
            score += 5
        if abs(solarm - expected_solarm) < 0.2:
            score += 5
            feedback_parts.append("✅ Configuration parameters closely match spec")
    except (ValueError, TypeError):
        feedback_parts.append("❌ Configuration parameters invalid or missing")

    # 6. PHYSICS SANITY CHECK / RESULTS VALIDATION (20 points)
    has_plausible_results = False
    try:
        cf = float(result.get('capacity_factor_pct', 0))
        lcoe = float(result.get('lcoe_real_cents_per_kwh', 0))
        gwh = result.get('annual_energy_gwh')
        
        # Fallback to convert kwh to gwh if missing
        if not gwh:
            kwh = result.get('annual_energy_kwh')
            if kwh:
                gwh = float(kwh) / 1e6
        else:
            gwh = float(gwh)

        physics_checks_passed = 0
        if gwh and gwh_min <= gwh <= gwh_max:
            physics_checks_passed += 1
        if cf and cf_min <= cf <= cf_max:
            physics_checks_passed += 1
        if lcoe and lcoe_min <= lcoe <= lcoe_max:
            physics_checks_passed += 1

        if physics_checks_passed == 3:
            score += 20
            has_plausible_results = True
            feedback_parts.append(f"✅ Simulation physics plausible (CF: {cf:.1f}%, Energy: {gwh:.1f} GWh)")
        elif physics_checks_passed > 0:
            score += 10
            has_plausible_results = True
            feedback_parts.append("⚠️ Partially plausible physics results")
        else:
            feedback_parts.append(f"❌ Implausible outputs (CF: {cf}%, GWh: {gwh})")

    except (ValueError, TypeError):
        feedback_parts.append("❌ Results fields invalid or missing")

    # 7. VLM TRAJECTORY VERIFICATION (20 points)
    vlm_score = 0
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames
            
            if images:
                vlm_result = query_vlm(prompt=VLM_PROMPT, images=images)
                if vlm_result and vlm_result.get('success'):
                    parsed = vlm_result.get('parsed', {})
                    if parsed.get('wrote_python_code'):
                        vlm_score += 10
                    if parsed.get('used_pysam_module') or parsed.get('executed_script'):
                        vlm_score += 10
                    
                    if vlm_score > 0:
                        feedback_parts.append(f"✅ VLM verified Python execution (Reason: {parsed.get('reasoning', '')})")
                    else:
                        feedback_parts.append("❌ VLM did not observe Python scripting")
                else:
                    logger.warning("VLM query failed or returned no success.")
        except Exception as e:
            logger.warning(f"VLM verification exception: {e}")
            # Do not heavily penalize if VLM infrastructure fails, just pass on other merits if high enough
            vlm_score = 20 if score >= 70 else 0 

    score += vlm_score

    # PASS CRITERIA: Need at least 70/100, files must be fresh, physics must be plausible
    key_criteria_met = json_fresh and script_fresh and has_plausible_results
    passed = (score >= 70) and key_criteria_met

    if passed:
        feedback_parts.insert(0, "🎉 Task passed successfully!")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": result
    }